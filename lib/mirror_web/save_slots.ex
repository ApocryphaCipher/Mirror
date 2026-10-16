defmodule MirrorWeb.SaveSlots do
  @moduledoc """
  Opening and saving from the browser (EPIC-012): the user picks the game folder once, then
  opens a save by clicking its slot on the start page, and saves into a slot from the header
  on every other page.

  The browser holds the folder (File System Access API, Chrome and Edge) and reads and writes
  the files, so this works the same from Docker: the `SaveSlots` hook (`assets/js/save_slots.js`)
  sends a slot's bytes up, and the server sends the bytes to write down. The server never sees
  the user's disk.

  Every LiveView mounts this module (`on_mount`, see `MirrorWeb`), which gives the socket a
  `:slots` assign and handles the `slots:` events, so the pages share one implementation. The
  loaded save itself lives in `Mirror.SessionStore`, not here. Slot 9 is the game's autosave: it
  can be opened, never saved to.
  """
  use MirrorWeb, :html

  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, push_navigate: 2]

  alias Mirror.{SaveManager, SessionStore}
  alias MirrorWeb.Toast

  @slots 1..9//1
  @save_slots 1..8//1
  @max_bytes 4_000_000

  # --- the hooks every page gets ---

  def on_mount(:default, _params, session, socket) do
    session_id = session["mirror_session_id"] || "local"
    if Phoenix.LiveView.connected?(socket), do: SessionStore.subscribe(session_id)

    slots = %{
      session_id: session_id,
      supported: true,
      folder: nil,
      needs_permission: false,
      filled: MapSet.new(),
      confirm: nil,
      pending: nil,
      save_name: nil,
      unsaved: 0,
      wizards: []
    }

    {:cont,
     socket
     |> Phoenix.Component.assign(:slots, slots)
     |> refresh()
     |> attach_hook(:slots_events, :handle_event, &handle_event/3)
     |> attach_hook(:slots_session, :handle_info, &handle_info/2)}
  end

  defp handle_info({:session_state_updated, session_id, _state, _sender}, socket) do
    if session_id == socket.assigns.slots.session_id,
      do: {:cont, refresh(socket)},
      else: {:cont, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp handle_event("slots:" <> name, params, socket), do: {:halt, event(name, params, socket)}
  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # --- what the browser tells us ---

  defp event("unsupported", _params, socket), do: put(socket, supported: false)

  defp event("folder", %{"name" => name, "slots" => slots}, socket),
    do: put(socket, folder: name, needs_permission: false, filled: slot_set(slots))

  defp event("needs_permission", %{"name" => name}, socket),
    do: put(socket, folder: name, needs_permission: true)

  defp event("bytes", %{"slot" => slot, "data" => data}, socket) do
    sid = socket.assigns.slots.session_id

    with {:ok, slot} <- parse_slot(slot),
         {:ok, raw} <- decode(data),
         name = slot_name(slot),
         {:ok, state, _} <- SaveManager.load_bytes(raw, name, SessionStore.get(sid)) do
      SessionStore.put(sid, state)
      socket = socket |> put(confirm: nil) |> Toast.push(:ok, "Opened #{name}.") |> refresh()

      # the start page goes on to the map once a save is open
      if socket.view == MirrorWeb.LandingLive,
        do: push_navigate(socket, to: ~p"/arcanus"),
        else: socket
    else
      {:error, reason} -> Toast.push(socket, :error, load_error(reason))
    end
  end

  defp event("written", %{"slot" => slot} = params, socket) do
    %{session_id: sid, pending: pending, filled: filled} = socket.assigns.slots

    with {:ok, slot} <- parse_slot(slot),
         {^slot, bytes} <- pending do
      name = slot_name(slot)

      {:ok, _} =
        SessionStore.update(sid, fn state -> SaveManager.mark_saved(state, name, bytes) end)

      socket
      |> put(pending: nil, filled: MapSet.put(filled, slot))
      |> Toast.push(:ok, saved_message(name, params["named"]))
      |> refresh()
    else
      _ -> socket
    end
  end

  defp event("error", %{"message" => message}, socket),
    do: socket |> put(pending: nil) |> Toast.push(:error, to_string(message))

  # --- what the user clicks ---

  # Open: only a slot the folder has (the start page).
  defp event("open", %{"slot" => slot}, socket) do
    with {:ok, slot} <- parse_slot(slot) do
      if MapSet.member?(socket.assigns.slots.filled, slot) do
        push_event(socket, "slots:read", %{slot: slot})
      else
        Toast.push(socket, :error, "#{slot_name(slot)} is empty.")
      end
    else
      _ -> socket
    end
  end

  # Save: never 9, only with a save loaded, and a full slot asks first (the header).
  defp event("save", %{"slot" => slot}, socket) do
    with {:ok, slot} when slot in @save_slots <- parse_slot(slot) do
      slots = socket.assigns.slots

      cond do
        slots.save_name == nil ->
          Toast.push(socket, :error, "Open a save first, then save it into a slot.")

        MapSet.member?(slots.filled, slot) ->
          put(socket, confirm: slot)

        true ->
          start_write(socket, slot, false)
      end
    else
      _ ->
        Toast.push(socket, :error, "Slot 9 is the game's autosave. Pick a slot from 1 to 8.")
    end
  end

  defp event("confirm", _params, socket) do
    case socket.assigns.slots.confirm do
      nil -> socket
      slot -> socket |> put(confirm: nil) |> start_write(slot, true)
    end
  end

  defp event("cancel", _params, socket), do: put(socket, confirm: nil)
  defp event(_unknown, _params, socket), do: socket

  defp start_write(socket, slot, backup?) do
    case SessionStore.get(socket.assigns.slots.session_id) |> SaveManager.slot_bytes() do
      {:ok, bytes} ->
        socket
        |> put(pending: {slot, bytes})
        |> push_event("slots:write", %{slot: slot, data: Base.encode64(bytes), backup: backup?})

      {:error, reason} ->
        Toast.push(socket, :error, "Could not build the save: #{inspect(reason)}")
    end
  end

  # --- state ---

  defp put(socket, changes) do
    Phoenix.Component.assign(socket, :slots, Map.merge(socket.assigns.slots, Map.new(changes)))
  end

  defp refresh(socket) do
    state = SessionStore.get(socket.assigns.slots.session_id) || %{}
    save = Map.get(state, :save)
    path = Map.get(state, :save_path)

    put(socket,
      save_name: if(save && path, do: Path.basename(path)),
      unsaved: if(save, do: SaveManager.unsaved_count(state), else: 0),
      wizards: if(save, do: MirrorWeb.WizardPanel.wizards(save.raw), else: [])
    )
  end

  defp saved_message(name, label) when is_binary(label) and label != "",
    do: "Saved to #{name} and named \"#{label}\" in the game's list. The game can load it now."

  defp saved_message(name, _), do: "Saved to #{name}. The game can load it now."

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

  # --- the start page ---

  attr :slots, :map, required: true

  def landing(assigns) do
    ~H"""
    <main class="mx-auto flex min-h-[100svh] max-w-2xl flex-col px-6 py-6 text-slate-100">
      <.logo />

      <div
        id="slots-landing"
        phx-hook="SaveSlots"
        class="flex flex-1 flex-col items-center justify-center gap-8 pb-16 text-center"
      >
        <div class="space-y-3">
          <h1 class="text-4xl font-semibold text-white sm:text-5xl">Welcome to Mirror!</h1>
          <p class="text-lg text-slate-300">
            To get started, pick your game folder.
          </p>
        </div>

        <%= cond do %>
          <% !@slots.supported -> %>
            <p
              id="slots-unsupported"
              class="max-w-md rounded-xl border border-amber-300/30 bg-amber-300/10 p-4 text-amber-100"
            >
              Mirror opens and saves games through your browser's folder picker, which needs
              <strong>Chrome</strong>
              or <strong>Edge</strong>. Please open this page in one of them.
            </p>
          <% @slots.needs_permission -> %>
            <div class="flex flex-col items-center gap-3">
              <p class="text-slate-300">
                Mirror needs your OK again to use <strong class="text-white">{@slots.folder}</strong>.
              </p>
              <button
                type="button"
                id="reconnect-folder"
                data-action="reconnect-folder"
                class="rounded-xl bg-amber-300 px-6 py-3 text-lg font-semibold text-slate-950 hover:bg-amber-200"
              >
                Reconnect folder
              </button>
            </div>
          <% true -> %>
            <div class="flex items-stretch gap-2">
              <div
                id="folder-name"
                class="flex min-w-64 items-center rounded-xl border border-white/15 bg-slate-900 px-4 py-3 text-left text-slate-200"
              >
                {@slots.folder || "No folder picked yet"}
              </div>
              <button
                type="button"
                id="choose-folder"
                data-action="choose-folder"
                title="Pick your game folder"
                class="flex items-center gap-2 rounded-xl bg-amber-300 px-5 py-3 font-semibold text-slate-950 hover:bg-amber-200"
              >
                <.icon name="hero-folder-open" class="size-6" />
                {if @slots.folder, do: "Change", else: "Choose folder"}
              </button>
            </div>

            <div :if={@slots.folder} id="slot-picker" class="space-y-4">
              <p class="text-xl text-white">Select your save:</p>
              <div class="flex flex-wrap items-center justify-center gap-6">
                <div class="grid grid-cols-4 gap-3">
                  <.slot_button :for={n <- 1..8} n={n} slots={@slots} event="slots:open" size="lg" />
                </div>
                <div class="flex flex-col items-center gap-1 text-sm text-slate-400">
                  <.slot_button n={9} slots={@slots} event="slots:open" size="lg" /> autosave
                </div>
              </div>
              <p :if={MapSet.size(@slots.filled) == 0} id="no-saves" class="text-slate-400">
                There are no SAVE1.GAM to SAVE9.GAM files in that folder.
              </p>
            </div>
        <% end %>

        <.link
          :if={@slots.save_name}
          id="continue-link"
          navigate={~p"/arcanus"}
          class="text-amber-200 underline decoration-dotted hover:text-amber-100"
        >
          Continue with {@slots.save_name} →
        </.link>

        <.confirm slots={@slots} class="static" />
      </div>
    </main>
    """
  end

  # --- the header on every other page ---

  attr :slots, :map, default: nil
  attr :active, :any, default: nil, doc: ":arcanus, :myrror, or {:wizard, id}"
  attr :history, :map, default: nil, doc: "`%{undo: bool, redo: bool}` when the page can undo"

  def header(assigns) do
    ~H"""
    <%!-- backdrop-blur makes the header its own stacking layer, so it needs its own z-index
         or the map (positioned, later in the page) paints over the floating messages below it --%>
    <header
      id="app-header"
      class="relative z-50 border-b border-white/10 bg-slate-950/80 backdrop-blur"
    >
      <div class="relative flex items-start justify-between gap-4 px-4 pb-2 pt-3">
        <.logo />

        <div
          :if={@slots}
          id="slots-bar"
          phx-hook="SaveSlots"
          class="flex items-center gap-3 text-sm text-slate-300"
        >
          <div :if={@history} class="flex gap-1" id="header-history">
            <button
              :for={
                {id, event, label, on} <- [
                  {"header-undo", "undo", "Undo", @history.undo},
                  {"header-redo", "redo", "Redo", @history.redo}
                ]
              }
              type="button"
              id={id}
              phx-click={event}
              disabled={!on}
              class="rounded-lg border border-white/20 px-3 py-1 font-medium text-slate-200 hover:border-white/50 hover:text-white disabled:cursor-not-allowed disabled:opacity-40"
            >
              {label}
            </button>
          </div>

          <%!-- always in the same place; hidden with `invisible`, not removed, so nothing shifts --%>
          <span
            id="unsaved-badge"
            class={[
              "flex items-center gap-1.5 rounded-full bg-amber-300/20 px-3 py-1 font-semibold text-amber-200",
              @slots.unsaved == 0 && "invisible"
            ]}
          >
            <.icon name="hero-exclamation-circle-mini" class="size-4" /> Unsaved changes
          </span>

          <%= cond do %>
            <% !@slots.supported -> %>
              <span class="text-slate-400">Saving needs Chrome or Edge</span>
            <% @slots.needs_permission -> %>
              <button
                type="button"
                id="reconnect-folder"
                data-action="reconnect-folder"
                class="rounded-lg bg-amber-300 px-3 py-1.5 font-semibold text-slate-950 hover:bg-amber-200"
              >
                Reconnect folder
              </button>
            <% @slots.folder == nil -> %>
              <.link
                navigate={~p"/"}
                id="pick-folder-link"
                class="rounded-lg bg-amber-300 px-3 py-1.5 font-semibold text-slate-950 hover:bg-amber-200"
              >
                Pick your game folder to save
              </.link>
            <% true -> %>
              <span class="font-medium text-slate-200">Save to:</span>
              <div class="grid grid-cols-4 gap-1" id="slot-buttons">
                <.slot_button :for={n <- 1..8} n={n} slots={@slots} event="slots:save" size="sm" />
              </div>
          <% end %>

          <.confirm slots={@slots} class="absolute right-4 top-full z-40 mt-1" />
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-x-5 gap-y-2 px-4 pb-3">
        <nav class="flex rounded-xl border border-white/10 p-0.5 text-sm" aria-label="Plane">
          <.link
            :for={
              {plane, label, path} <- [
                {:arcanus, "Arcanus", ~p"/arcanus"},
                {:myrror, "Myrror", ~p"/myrror"}
              ]
            }
            navigate={path}
            class={[
              "rounded-lg px-4 py-1 transition",
              @active == plane && "bg-white/15 font-semibold text-white",
              @active != plane && "text-slate-400 hover:text-white"
            ]}
            aria-current={@active == plane && "page"}
          >
            {label}
          </.link>
        </nav>

        <nav
          :if={@slots && @slots.wizards != []}
          id="header-wizards"
          class="flex flex-wrap items-center gap-1.5 text-sm"
          aria-label="Wizards"
        >
          <.link
            :for={{id, name} <- @slots.wizards}
            navigate={~p"/wizard/#{id}"}
            class={[
              "rounded-full border px-3 py-1 transition",
              @active == {:wizard, id} && "border-white/60 bg-white/10 text-white",
              @active != {:wizard, id} && "border-white/10 text-slate-300 hover:text-white"
            ]}
          >
            {name}
          </.link>
        </nav>

        <span class="ml-auto flex items-center gap-4 text-sm">
          <.link navigate={~p"/lab/arcanus"} class="text-slate-500 transition hover:text-white">
            Lab
          </.link>
          <.link navigate={~p"/tile-probe"} class="text-slate-500 transition hover:text-white">
            Tile probe
          </.link>
          <MirrorWeb.Layouts.theme_toggle />
        </span>
      </div>
    </header>
    """
  end

  # --- pieces ---

  defp logo(assigns) do
    ~H"""
    <.link navigate={~p"/"} id="logo" class="flex items-center gap-3" title="Back to the start page">
      <span class="flex h-10 w-10 items-center justify-center rounded-2xl bg-gradient-to-br from-amber-300/80 via-sky-300/70 to-emerald-300/80 text-slate-950 shadow-lg">
        <.icon name="hero-sparkles" class="size-5" />
      </span>
      <span class="text-left">
        <span class="block text-xs uppercase tracking-[0.3em] text-slate-400">Mirror</span>
        <span class="block text-lg font-semibold text-white">Master of Magic Classic</span>
      </span>
    </.link>
    """
  end

  attr :n, :integer, required: true
  attr :slots, :map, required: true
  attr :event, :string, required: true
  attr :size, :string, default: "sm"

  # One slot: green when the folder has a save in it, grey when empty. In the header (saving)
  # every slot but 9 is clickable; on the start page (opening) only a full one.
  defp slot_button(assigns) do
    filled = MapSet.member?(assigns.slots.filled, assigns.n)
    opening = assigns.event == "slots:open"

    assigns =
      assign(assigns,
        filled: filled,
        disabled: if(opening, do: not filled, else: assigns.n == 9),
        current: assigns.slots.save_name == slot_name(assigns.n)
      )

    ~H"""
    <button
      type="button"
      id={"#{if @event == "slots:open", do: "open", else: "save"}-slot-#{@n}"}
      phx-click={@event}
      phx-value-slot={@n}
      disabled={@disabled}
      title={slot_title(@n, @filled, @event)}
      class={[
        "rounded-md font-semibold transition",
        @size == "lg" && "h-14 w-14 text-xl",
        @size == "sm" && "h-7 w-7 text-xs",
        @filled && "bg-emerald-500 text-slate-950 hover:bg-emerald-400",
        !@filled && "bg-slate-600 text-slate-300",
        !@filled && !@disabled && "hover:bg-slate-500 hover:text-white",
        @current && "ring-2 ring-amber-300",
        @disabled && "cursor-not-allowed opacity-60"
      ]}
    >
      {@n}
    </button>
    """
  end

  defp slot_title(n, filled, "slots:open"),
    do: if(filled, do: "Open #{slot_name(n)}", else: "#{slot_name(n)} is empty")

  defp slot_title(9, _filled, _event), do: "Slot 9 is the game's autosave"

  defp slot_title(n, filled, _event),
    do: if(filled, do: "Replace #{slot_name(n)}", else: "Save into #{slot_name(n)}")

  attr :slots, :map, required: true
  attr :class, :string, default: ""

  # "Replace SAVE3.GAM?": a question, not a message, so it is not a toast and does not fade. It floats, so it
  # never moves the page under the pointer.
  defp confirm(assigns) do
    ~H"""
    <div
      :if={@slots.confirm}
      id="replace-confirm"
      class={[
        "max-w-sm rounded-xl border border-amber-300/40 bg-slate-900 px-4 py-3 text-sm text-amber-100 shadow-xl shadow-black/50",
        @class
      ]}
    >
      <p>
        Replace <strong>{slot_name(@slots.confirm)}</strong>?
        The old one is kept as a backup.
      </p>
      <div class="mt-2 flex gap-2">
        <button
          type="button"
          id="confirm-replace"
          phx-click="slots:confirm"
          class="rounded-lg bg-rose-500 px-3 py-1 font-semibold text-white hover:bg-rose-400"
        >
          Replace
        </button>
        <button
          type="button"
          id="cancel-replace"
          phx-click="slots:cancel"
          class="rounded-lg border border-white/20 px-3 py-1 text-slate-200 hover:text-white"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end
end
