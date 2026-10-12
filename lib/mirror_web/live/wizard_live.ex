defmodule MirrorWeb.WizardLive do
  @moduledoc """
  `/wizard/:id` (STORY-047): one wizard of the current session's save, read-only.
  `/wizard/1` is the player, `/wizard/2` to `/wizard/5` the rivals; see `MirrorWeb.WizardPanel`.
  """
  use MirrorWeb, :live_view

  alias Mirror.{Editor, SessionStore}
  alias Mirror.SaveFile.Structures
  alias MirrorWeb.WizardPanel

  @impl true
  def mount(%{"id" => id}, session, socket) do
    session_id = session["mirror_session_id"] || "local"
    if connected?(socket), do: SessionStore.subscribe(session_id)

    {:ok,
     socket
     |> assign(:session_id, session_id)
     |> assign(:id_param, id)
     |> assign(:editing, false)
     |> assign(:note, nil)
     |> load()}
  end

  @impl true
  def handle_info({:session_state_updated, session_id, _state, _sender}, socket) do
    if session_id == socket.assigns.session_id,
      do: {:noreply, load(socket)},
      else: {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_edit", _params, socket) do
    {:noreply, socket |> assign(:editing, !socket.assigns.editing) |> assign(:note, nil)}
  end

  def handle_event("wizard_edit", %{"wizard" => params}, socket) do
    case socket.assigns.details do
      nil -> {:noreply, socket}
      details -> {:noreply, apply_edit(socket, details, params)}
    end
  end

  # One apply is one undo step (`Editor.apply_record/5`); undo and Save as are on the map pages.
  defp apply_edit(socket, details, params) do
    {:ok, _state, result} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        raw = current.save.raw

        with {:ok, changes} <- WizardPanel.changes(params, details),
             :ok <- if(changes == [], do: {:error, :nothing_changed}, else: :ok),
             {:ok, edited, _} <- Structures.edit_wizard(raw, details.record, changes),
             label = WizardPanel.label(details, changes),
             {next, {:record, _, _}} <- Editor.apply_record(current, :arcanus, label, edited) do
          {next, {:ok, label}}
        else
          {:error, reason} -> {current, {:error, reason}}
          _ -> {current, {:error, :unchanged}}
        end
      end)

    case result do
      {:ok, label} -> socket |> assign(:note, {:ok, label}) |> load()
      {:error, reason} -> assign(socket, :note, {:error, WizardPanel.error_message(reason)})
    end
  end

  defp load(socket) do
    raw = raw_of(SessionStore.get(socket.assigns.session_id))

    details =
      with {id, ""} <- Integer.parse(socket.assigns.id_param),
           true <- is_binary(raw) do
        WizardPanel.details(raw, id)
      else
        _ -> nil
      end

    socket
    |> assign(:loaded?, is_binary(raw))
    |> assign(:details, details)
    |> assign(:wizards, WizardPanel.wizards(raw))
    |> assign(:page_title, if(details, do: details.name, else: "Wizard"))
  end

  defp raw_of(%{save: %{raw: raw}}) when is_binary(raw), do: raw
  defp raw_of(_state), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="wizard-page"
        class="-mx-6 min-h-[70vh] px-6 pb-12 pt-6"
        style={@details && gradient(@details.colour)}
      >
        <nav id="wizard-switcher" class="mb-6 flex flex-wrap items-center gap-2 text-sm">
          <.link navigate={~p"/arcanus"} class="text-slate-300 hover:text-white">← Map</.link>
          <.link
            :for={{id, name} <- @wizards}
            navigate={~p"/wizard/#{id}"}
            class={[
              "rounded-full border px-3 py-1",
              @details && @details.id == id && "border-white/60 text-white",
              !(@details && @details.id == id) && "border-white/10 text-slate-300 hover:text-white"
            ]}
          >
            {name}
          </.link>
        </nav>

        <div :if={!@loaded?} id="wizard-no-save" class="text-slate-300">
          No save is loaded. Open one on the
          <.link navigate={~p"/arcanus"} class="underline">map</.link>
          first, then come back.
        </div>

        <div :if={@loaded? && !@details} id="wizard-missing" class="text-slate-300">
          There is no wizard {@id_param} in this save.
        </div>

        <div :if={@details} class="space-y-6">
          <header class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p class="text-xs uppercase tracking-[0.3em] text-slate-300">
                Wizard {@details.id} · {@details.banner} banner
              </p>
              <h1 id="wizard-name" class="text-4xl font-semibold text-white">{@details.name}</h1>
            </div>
            <button
              id="wizard-edit-toggle"
              type="button"
              phx-click="toggle_edit"
              class={[
                "rounded-lg px-3 py-1 text-sm font-semibold transition",
                @editing && "bg-emerald-300 text-slate-950 hover:bg-emerald-200",
                !@editing && "border border-emerald-300/50 text-emerald-100 hover:border-emerald-200"
              ]}
            >
              {if @editing, do: "Done", else: "✎ Edit"}
            </button>
          </header>

          <p
            :if={@note}
            id="wizard-note"
            class={[
              "text-sm",
              elem(@note, 0) == :ok && "text-emerald-200",
              elem(@note, 0) == :error && "text-rose-300"
            ]}
          >
            {elem(@note, 1)}
          </p>

          <.form
            :if={@editing}
            for={%{}}
            as={:wizard}
            id="wizard-form"
            phx-submit="wizard_edit"
            class="space-y-4 rounded-xl border border-emerald-300/30 bg-black/40 p-4"
          >
            <input type="hidden" name="wizard[retorts_present]" value="1" />
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <label class="text-sm text-slate-300">
                Name
                <input
                  type="text"
                  name="wizard[name]"
                  value={@details.name}
                  maxlength="19"
                  class="mt-1 w-full rounded bg-slate-900 px-2 py-1 text-white"
                />
              </label>
              <label
                :for={
                  {field, value} <- [gold: @details.gold, mana: @details.mana, fame: @details.fame]
                }
                class="text-sm text-slate-300"
              >
                {String.capitalize(to_string(field))} (0 to 30000)
                <input
                  type="number"
                  min="0"
                  max="30000"
                  name={"wizard[#{field}]"}
                  value={value}
                  class="mt-1 w-full rounded bg-slate-900 px-2 py-1 text-white"
                />
              </label>
            </div>
            <div class="grid grid-cols-5 gap-3">
              <label
                :for={{{realm, n}, i} <- Enum.with_index(@details.book_counts)}
                class="text-sm text-slate-300"
              >
                {realm} books
                <input
                  type="number"
                  min="0"
                  max="13"
                  name={"wizard[books][#{i}]"}
                  value={n}
                  class="mt-1 w-full rounded bg-slate-900 px-2 py-1 text-white"
                />
              </label>
            </div>
            <fieldset>
              <legend class="mb-1 text-sm text-slate-300">Retorts</legend>
              <div class="grid grid-cols-2 gap-1 sm:grid-cols-3">
                <label
                  :for={{{name, on}, i} <- Enum.with_index(@details.retort_flags)}
                  class="flex items-center gap-2 text-sm text-slate-200"
                >
                  <input type="checkbox" name={"wizard[retorts][#{i}]"} checked={on} />
                  {name}
                </label>
              </div>
            </fieldset>
            <p class="text-xs text-slate-400">
              Power base, casting skill and the research list are worked out again by the game.
              Undo and Save as are on the map pages.
            </p>
            <button
              type="submit"
              id="wizard-apply"
              class="rounded-lg bg-emerald-300 px-4 py-1 text-sm font-semibold text-slate-950 hover:bg-emerald-200"
            >
              Apply
            </button>
          </.form>

          <section id="wizard-header" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <.stat label="Fame" value={@details.fame} />
            <.stat label="Gold" value={@details.gold} />
            <.stat label="Mana" value={@details.mana} />
            <.stat label="Casting skill" value={@details.casting_skill} />
            <.stat label="Power base" value={@details.power_base} />
            <.stat label="Tax" value={@details.tax} />
            <.stat label="Portrait" value={@details.portrait} />
            <div class="rounded-xl border border-white/10 bg-black/30 p-3">
              <p class="text-xs text-slate-400">Summoning circle</p>
              <p :if={@details.circle} class="text-white">
                <.link
                  id="wizard-circle"
                  navigate={circle_path(@details.circle)}
                  class="underline"
                >
                  {plane_name(@details.circle.plane)} ({@details.circle.x}, {@details.circle.y})
                </.link>
              </p>
              <p :if={!@details.circle} class="text-slate-500">none</p>
            </div>
          </section>

          <section id="wizard-magic" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Magic</h2>
            <p class="text-slate-200">
              Books: <span :if={@details.books == []} class="text-slate-500">none</span>
              <span :for={{realm, n} <- @details.books} class="mr-3">{n} {realm}</span>
            </p>
            <p class="text-slate-200">
              Retorts: <span :if={@details.retorts == []} class="text-slate-500">none</span>
              {Enum.join(@details.retorts, ", ")}
            </p>
            <p class="text-slate-200">
              Research / mana / skill: {@details.ratios.research}% / {@details.ratios.mana}% / {@details.ratios.skill}%
            </p>
            <p class="text-slate-200">
              Researching: <span :if={!@details.researching} class="text-slate-500">nothing</span>
              <span :if={@details.researching}>
                spell {@details.researching.number}{realm_suffix(@details.researching)}, {@details.research_left} research points left
              </span>
            </p>
          </section>

          <section id="wizard-spells" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Known spells</h2>
            <p class="text-slate-200">
              <span :for={{realm, n} <- @details.spells} class="mr-4">{realm} {n}</span>
            </p>
          </section>

          <section id="wizard-standing" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Standing</h2>
            <p class="text-slate-200">
              {@details.standing.cities} cities · {@details.standing.units} units · {@details.standing.nodes} nodes
            </p>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-xl border border-white/10 bg-black/30 p-3">
      <p class="text-xs text-slate-400">{@label}</p>
      <p class="text-xl text-white">{@value}</p>
    </div>
    """
  end

  # The banner colour at the top, fading to black down the page.
  defp gradient(colour),
    do: "background: linear-gradient(to bottom, #{colour} 0%, #000 90%);"

  defp circle_path(%{plane: :arcanus}), do: ~p"/arcanus"
  defp circle_path(%{plane: :myrror}), do: ~p"/myrror"

  defp plane_name(:arcanus), do: "Arcanus"
  defp plane_name(:myrror), do: "Myrror"

  defp realm_suffix(%{realm: nil}), do: ""
  defp realm_suffix(%{realm: realm}), do: " (#{realm})"
end
