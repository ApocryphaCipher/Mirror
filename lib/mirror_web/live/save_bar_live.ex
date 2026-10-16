defmodule MirrorWeb.SaveBarLive do
  @moduledoc """
  The strip at the top of every page (EPIC-012): pick the game folder once, then load a save by
  clicking its slot, or save into a slot.

  The browser holds the folder (File System Access API, Chrome and Edge) and reads and writes
  the files, so this works the same from Docker: the `SaveSlots` hook (`assets/js/save_slots.js`)
  sends a slot's bytes up, and this view sends the bytes to write down. The server never sees the
  user's disk. It is rendered once in the root layout as a sticky child, so it stays put (and
  keeps the folder) while the pages change under it.

  Slot 9 is the game's autosave: it can be loaded, never saved to.
  """
  use MirrorWeb, :live_view

  alias Mirror.{SaveManager, SessionStore}

  @slots 1..9//1
  @max_bytes 4_000_000

  @impl true
  def mount(_params, session, socket) do
    session_id = session["mirror_session_id"] || "local"
    if connected?(socket), do: SessionStore.subscribe(session_id)

    {:ok,
     socket
     |> assign(:session_id, session_id)
     |> assign(:supported, true)
     |> assign(:folder, nil)
     |> assign(:needs_permission, false)
     |> assign(:filled, MapSet.new())
     |> assign(:mode, :open)
     |> assign(:confirm, nil)
     |> assign(:pending, nil)
     |> assign(:status, nil)
     |> refresh(), layout: false}
  end

  @impl true
  def handle_info({:session_state_updated, session_id, _state, _sender}, socket) do
    if session_id == socket.assigns.session_id,
      do: {:noreply, refresh(socket)},
      else: {:noreply, socket}
  end

  # --- what the browser tells us ---

  @impl true
  def handle_event("unsupported", _params, socket) do
    {:noreply, assign(socket, :supported, false)}
  end

  def handle_event("folder", %{"name" => name, "slots" => slots}, socket) do
    {:noreply,
     socket
     |> assign(:folder, name)
     |> assign(:needs_permission, false)
     |> assign(:filled, slot_set(slots))}
  end

  def handle_event("needs_permission", %{"name" => name}, socket) do
    {:noreply, socket |> assign(:folder, name) |> assign(:needs_permission, true)}
  end

  def handle_event("slot_bytes", %{"slot" => slot, "data" => data}, socket) do
    with {:ok, slot} <- parse_slot(slot),
         {:ok, raw} <- decode(data),
         name = slot_name(slot),
         {:ok, state, _} <- SaveManager.load_bytes(raw, name, SessionStore.get(sid(socket))) do
      SessionStore.put(sid(socket), state)

      {:noreply,
       socket
       |> assign(:confirm, nil)
       |> assign(:status, {:ok, "Loaded #{name}."})
       |> refresh()}
    else
      {:error, reason} -> {:noreply, assign(socket, :status, {:error, load_error(reason)})}
    end
  end

  def handle_event("slot_written", %{"slot" => slot}, socket) do
    with {:ok, slot} <- parse_slot(slot),
         {^slot, bytes} <- socket.assigns.pending do
      name = slot_name(slot)

      {:ok, _} =
        SessionStore.update(sid(socket), fn state ->
          SaveManager.mark_saved(state, name, bytes)
        end)

      {:noreply,
       socket
       |> assign(:pending, nil)
       |> assign(:filled, MapSet.put(socket.assigns.filled, slot))
       |> assign(:status, {:ok, "Saved to #{name}. The game can load it now."})
       |> refresh()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("slot_error", %{"message" => message}, socket) do
    {:noreply, socket |> assign(:pending, nil) |> assign(:status, {:error, to_string(message)})}
  end

  # --- what the user clicks ---

  def handle_event("set_mode", %{"mode" => mode}, socket) when mode in ["open", "save"] do
    {:noreply, socket |> assign(:mode, String.to_existing_atom(mode)) |> assign(:confirm, nil)}
  end

  def handle_event("pick_slot", %{"slot" => slot}, socket) do
    with {:ok, slot} <- parse_slot(slot) do
      {:noreply, pick(socket, slot, socket.assigns.mode)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("confirm_replace", _params, socket) do
    case socket.assigns.confirm do
      nil -> {:noreply, socket}
      slot -> {:noreply, socket |> assign(:confirm, nil) |> start_write(slot, true)}
    end
  end

  def handle_event("cancel_replace", _params, socket) do
    {:noreply, assign(socket, :confirm, nil)}
  end

  # Opening a slot: only one the folder has.
  defp pick(socket, slot, :open) do
    if MapSet.member?(socket.assigns.filled, slot) do
      socket |> assign(:status, nil) |> push_event("read_slot", %{slot: slot})
    else
      assign(socket, :status, {:error, "#{slot_name(slot)} is empty."})
    end
  end

  # Saving into a slot: never 9, only with a save loaded, and a full slot asks first.
  defp pick(socket, 9, :save) do
    assign(socket, :status, {:error, "Slot 9 is the game's autosave. Pick a slot from 1 to 8."})
  end

  defp pick(socket, slot, :save) do
    cond do
      not has_save?(socket) ->
        assign(socket, :status, {:error, "Load a save first, then save it into a slot."})

      MapSet.member?(socket.assigns.filled, slot) ->
        socket |> assign(:status, nil) |> assign(:confirm, slot)

      true ->
        start_write(socket, slot, false)
    end
  end

  defp start_write(socket, slot, backup?) do
    case SessionStore.get(sid(socket)) |> SaveManager.slot_bytes() do
      {:ok, bytes} ->
        socket
        |> assign(:pending, {slot, bytes})
        |> assign(:status, nil)
        |> push_event("write_slot", %{slot: slot, data: Base.encode64(bytes), backup: backup?})

      {:error, reason} ->
        assign(socket, :status, {:error, "Could not build the save: #{inspect(reason)}"})
    end
  end

  # --- state ---

  defp refresh(socket) do
    state = SessionStore.get(socket.assigns.session_id) || %{}
    loaded? = Map.get(state, :save) != nil
    path = Map.get(state, :save_path)

    socket
    |> assign(:save_name, if(loaded? && path, do: Path.basename(path)))
    |> assign(:unsaved, if(loaded?, do: SaveManager.unsaved_count(state), else: 0))
  end

  defp has_save?(socket), do: socket.assigns.save_name != nil
  defp sid(socket), do: socket.assigns.session_id

  defp parse_slot(value) when is_integer(value) and value in @slots, do: {:ok, value}

  defp parse_slot(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in @slots -> {:ok, n}
      _ -> {:error, :bad_slot}
    end
  end

  defp parse_slot(_), do: {:error, :bad_slot}

  defp slot_set(slots) when is_list(slots) do
    for n <- slots, {:ok, n} <- [parse_slot(n)], into: MapSet.new(), do: n
  end

  defp slot_set(_), do: MapSet.new()

  defp slot_name(n), do: "SAVE#{n}.GAM"

  defp decode(data) when is_binary(data) and byte_size(data) <= div(@max_bytes * 4, 3) + 4 do
    case Base.decode64(data) do
      {:ok, raw} when byte_size(raw) <= @max_bytes -> {:ok, raw}
      _ -> {:error, :bad_data}
    end
  end

  defp decode(_), do: {:error, :bad_data}

  defp load_error(:bad_data), do: "That file did not come through intact. Try again."
  defp load_error(:bad_slot), do: "That is not a save slot."

  defp load_error(reason),
    do: "That does not look like a Master of Magic save (#{inspect(reason)})."

  # --- view ---

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="save-bar"
      phx-hook="SaveSlots"
      class="flex h-10 items-center gap-3 overflow-hidden whitespace-nowrap border-b border-white/10 bg-slate-900 px-4 text-xs text-slate-300"
    >
      <%= cond do %>
        <% !@supported -> %>
          <span id="save-bar-unsupported" class="text-slate-400">
            Opening and saving from here needs Chrome or Edge. Use the path box on the map page.
          </span>
        <% @folder == nil -> %>
          <button
            type="button"
            id="choose-folder"
            data-action="choose-folder"
            class="rounded-md bg-amber-300 px-3 py-1 font-semibold text-slate-950 hover:bg-amber-200"
          >
            Choose game folder
          </button>
          <span class="text-slate-400">to open and save games here</span>
        <% @needs_permission -> %>
          <span class="font-medium text-slate-100">{@folder}</span>
          <button
            type="button"
            id="reconnect-folder"
            data-action="reconnect-folder"
            class="rounded-md bg-amber-300 px-3 py-1 font-semibold text-slate-950 hover:bg-amber-200"
          >
            Reconnect folder
          </button>
        <% true -> %>
          <span
            id="save-bar-folder"
            class="max-w-40 truncate font-medium text-slate-100"
            title={@folder}
          >
            {@folder}
          </span>
          <div class="flex overflow-hidden rounded-md border border-white/15" role="group">
            <button
              :for={{mode, label} <- [open: "Open", save: "Save to"]}
              type="button"
              id={"mode-#{mode}"}
              phx-click="set_mode"
              phx-value-mode={mode}
              class={[
                "px-2.5 py-1",
                @mode == mode && "bg-white/15 text-white",
                @mode != mode && "text-slate-400 hover:text-white"
              ]}
            >
              {label}
            </button>
          </div>
          <div class="flex gap-1" id="slot-buttons">
            <button
              :for={n <- 1..9}
              type="button"
              id={"slot-#{n}"}
              phx-click="pick_slot"
              phx-value-slot={n}
              title={slot_title(n, @filled, @mode)}
              disabled={disabled?(n, @filled, @mode)}
              class={[
                "h-6 w-6 rounded font-semibold",
                MapSet.member?(@filled, n) && "bg-emerald-500 text-slate-950 hover:bg-emerald-400",
                !MapSet.member?(@filled, n) && "bg-slate-700 text-slate-400",
                @save_name == slot_name(n) && "ring-2 ring-amber-300",
                disabled?(n, @filled, @mode) && "cursor-not-allowed opacity-40"
              ]}
            >
              {n}
            </button>
          </div>
          <span :if={@confirm} id="replace-confirm" class="flex items-center gap-2 text-amber-200">
            Replace {slot_name(@confirm)}? The old one is kept as a backup.
            <button
              type="button"
              id="confirm-replace"
              phx-click="confirm_replace"
              class="rounded bg-rose-500 px-2 py-0.5 font-semibold text-white hover:bg-rose-400"
            >
              Replace
            </button>
            <button
              type="button"
              id="cancel-replace"
              phx-click="cancel_replace"
              class="rounded border border-white/20 px-2 py-0.5 text-slate-200 hover:text-white"
            >
              Cancel
            </button>
          </span>
          <span
            :if={@status && !@confirm}
            id="save-bar-status"
            class={elem(@status, 0) == :error && "text-rose-300"}
          >
            {elem(@status, 1)}
          </span>
      <% end %>

      <span class="ml-auto flex items-center gap-3">
        <span :if={@save_name} id="save-bar-name" class="text-slate-400">{@save_name}</span>
        <%!-- always in the same place; hidden with `invisible`, not removed, so nothing shifts --%>
        <span
          id="unsaved-badge"
          class={[
            "rounded-full bg-amber-300/20 px-2.5 py-0.5 font-semibold text-amber-200",
            @unsaved == 0 && "invisible"
          ]}
        >
          Unsaved changes
        </span>
      </span>
    </div>
    """
  end

  defp disabled?(n, filled, :open), do: not MapSet.member?(filled, n)
  defp disabled?(9, _filled, :save), do: true
  defp disabled?(_n, _filled, :save), do: false

  defp slot_title(n, filled, :open),
    do:
      if(MapSet.member?(filled, n), do: "Open #{slot_name(n)}", else: "#{slot_name(n)} is empty")

  defp slot_title(9, _filled, :save), do: "Slot 9 is the game's autosave"

  defp slot_title(n, filled, :save),
    do:
      if(MapSet.member?(filled, n),
        do: "Replace #{slot_name(n)}",
        else: "Save into #{slot_name(n)}"
      )
end
