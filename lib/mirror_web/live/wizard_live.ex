defmodule MirrorWeb.WizardLive do
  @moduledoc """
  `/wizard/:id` (STORY-047): one wizard of the current session's save, read-only.
  `/wizard/1` is the player, `/wizard/2` to `/wizard/5` the rivals; see `MirrorWeb.WizardPanel`.
  """
  use MirrorWeb, :live_view

  alias Mirror.SessionStore
  alias MirrorWeb.WizardPanel

  @impl true
  def mount(%{"id" => id}, session, socket) do
    session_id = session["mirror_session_id"] || "local"
    if connected?(socket), do: SessionStore.subscribe(session_id)

    {:ok, socket |> assign(:session_id, session_id) |> assign(:id_param, id) |> load()}
  end

  @impl true
  def handle_info({:session_state_updated, session_id, _state, _sender}, socket) do
    if session_id == socket.assigns.session_id,
      do: {:noreply, load(socket)},
      else: {:noreply, socket}
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
          <header>
            <p class="text-xs uppercase tracking-[0.3em] text-slate-300">
              Wizard {@details.id} · {@details.banner} banner
            </p>
            <h1 id="wizard-name" class="text-4xl font-semibold text-white">{@details.name}</h1>
          </header>

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
