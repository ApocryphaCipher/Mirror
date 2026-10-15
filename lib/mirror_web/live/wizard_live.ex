defmodule MirrorWeb.WizardLive do
  @moduledoc """
  `/wizard/:id` (STORY-047): one wizard of the current session's save, read-only.
  `/wizard/1` is the player, `/wizard/2` to `/wizard/5` the rivals; see `MirrorWeb.WizardPanel`.
  """
  use MirrorWeb, :live_view

  alias Mirror.{Editor, ItemData, ItemPowers, SessionStore, Spells}
  alias Mirror.SaveFile.Structures
  alias MirrorWeb.{ItemPanel, WizardPanel}

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
    {:noreply, apply_edit(socket, &WizardPanel.changes(params, &1))}
  end

  # One hero's name, level, experience and damage (STORY-053), the form is per hero slot.
  def handle_event("hero_edit", %{"slot" => slot, "hero" => params}, socket) do
    with {slot, ""} <- Integer.parse(slot) do
      write = fn raw, details, changes ->
        Structures.edit_hero(raw, details.record, slot, changes)
      end

      label = fn details, changes ->
        WizardPanel.hero_label(Enum.find(details.heroes, &(&1.slot == slot)), changes)
      end

      {:noreply, apply_edit(socket, &WizardPanel.hero_changes(params, &1, slot), write, label)}
    else
      _ -> {:noreply, socket}
    end
  end

  # One item's name, cost, stats and powers (STORY-056), in place wherever it is carried. Only an item this wizard
  # holds (a hero's or the vault's) can be edited from his page.
  def handle_event("item_edit", %{"index" => index, "item" => params}, socket) do
    with {index, ""} <- Integer.parse(index) do
      held = fn details -> Enum.find(held_items(details), &(&1.index == index)) end

      changes_for = fn details ->
        case held.(details) do
          nil -> {:error, :no_such_item}
          item -> WizardPanel.item_changes(params, item, socket.assigns.powers)
        end
      end

      write = fn raw, _details, changes -> Structures.edit_item(raw, index, changes) end
      label = fn details, changes -> WizardPanel.item_label(held.(details), changes) end

      {:noreply, apply_edit(socket, changes_for, write, label)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Move an item between this wizard's hero places and his vault (STORY-056). The source is read from the save, the
  # form only names the destination.
  def handle_event("item_move", %{"index" => index, "to" => to}, socket) do
    with {index, ""} <- Integer.parse(index) do
      held = fn details -> Enum.find(held_items(details), &(&1.index == index)) end

      changes_for = fn details ->
        with {:ok, move} <- WizardPanel.move_request(details, index, to), do: {:ok, [move: move]}
      end

      write = fn raw, details, [move: {from, to}] ->
        Structures.move_item(raw, details.record, from, to)
      end

      label = fn details, [move: {_from, to}] ->
        WizardPanel.move_label(details, held.(details), to)
      end

      {:noreply, apply_edit(socket, changes_for, write, label)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Fill, empty or leave one of the wizard's item places (STORY-056): a premade item for a hero's place of its kind, any
  # for the vault. `place` names the place, `choice` is "keep", "clear" or "item:N".
  def handle_event("place_set", %{"place" => key, "choice" => choice}, socket) do
    case socket.assigns.premade do
      nil ->
        {:noreply, socket}

      premade ->
        # premade name to number, so that an item given up hands its number back to the game
        names = Map.new(premade, &{&1.name, &1.number})

        changes_for = fn details ->
          case WizardPanel.set_request(details, key, choice, premade) do
            {:ok, nil} -> {:ok, []}
            {:ok, request} -> {:ok, [request: request]}
            {:error, _} = error -> error
          end
        end

        write = fn raw, details, [request: request] ->
          case request do
            {:clear, place} ->
              Structures.clear_item(raw, details.record, place, premade_names: names)

            {:set, place, p} ->
              Structures.put_item(raw, details.record, place, ItemData.save_record(p),
                number: p.number,
                premade_names: names
              )
          end
        end

        label = fn details, [request: request] -> WizardPanel.set_label(details, request, nil) end
        {:noreply, apply_edit(socket, changes_for, write, label)}
    end
  end

  # Add a hero (STORY-053) to the first empty hero place: a new hero of the chosen type, level 0, on the wizard's
  # summoning circle. A hero already in play, whoever owns him, is refused.
  def handle_event("hero_add", %{"type" => type}, socket) do
    changes_for = fn details ->
      with {:ok, request} <- WizardPanel.hero_add_request(details, type),
           do: {:ok, [add: request]}
    end

    write = fn raw, details, [add: {slot, type}] ->
      Structures.add_hero(raw, details.record, slot, type)
    end

    label = fn details, [add: {_slot, type}] -> WizardPanel.hero_add_label(details, type) end
    {:noreply, apply_edit(socket, changes_for, write, label)}
  end

  # "Learn every spell of a realm": the common edit, applied at once.
  def handle_event("learn_realm", %{"realm" => realm}, socket) do
    case Enum.find(Spells.realms(), &(Atom.to_string(&1) == realm)) do
      nil -> {:noreply, socket}
      realm -> {:noreply, apply_edit(socket, &{:ok, WizardPanel.learn_realm(&1, realm)})}
    end
  end

  # One apply is one undo step (`Editor.apply_record/5`); undo and Save as are on the map pages.
  #
  # The wizard is read again from the save inside the update, so the form is compared with what is
  # there now, not with what the page showed when it was drawn. (A form from a stale page still
  # submits all of its fields, so another tab's edit to a field this form also shows is put back.)
  # `changes_for` turns the current details into `{:ok, changes}`.
  defp apply_edit(socket, changes_for, write \\ &write_wizard/3, label \\ &WizardPanel.label/2)

  defp apply_edit(%{assigns: %{details: nil}} = socket, _changes_for, _write, _label), do: socket

  defp apply_edit(%{assigns: %{details: %{id: id}}} = socket, changes_for, write, label_for) do
    {:ok, _state, result} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        raw = raw_of(current)

        with true <- is_binary(raw),
             %{} = details <- WizardPanel.details(raw, id) || {:error, :no_such_wizard},
             {:ok, changes} <- changes_for.(details),
             :ok <- if(changes == [], do: {:error, :nothing_changed}, else: :ok),
             {:ok, edited, _} <- write.(raw, details, changes),
             label = label_for.(details, changes),
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

  # The items this wizard holds: his heroes' and the vault's.
  defp held_items(details), do: Enum.flat_map(details.heroes, & &1.item_list) ++ details.vault

  defp write_wizard(raw, details, changes),
    do: Structures.edit_wizard(raw, details.record, changes)

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
    |> assign(:spell_table, spell_table())
    |> assign(:powers, powers())
    |> assign(:moves, moves(details))
    |> assign(:premade, premade())
    |> assign(:places, places(details))
    |> assign(:spell_rows, spell_rows(details))
    |> assign(:page_title, if(details, do: details.name, else: "Wizard"))
  end

  defp spell_rows(nil), do: []
  defp spell_rows(details), do: WizardPanel.spell_rows(details, spell_table())

  # `index => [{value, label}]` of where each held item could go (see `WizardPanel.item_moves/2`).
  defp moves(nil), do: %{}

  defp moves(details),
    do: Map.new(held_items(details), &{&1.index, WizardPanel.item_moves(details, &1)})

  defp places(nil), do: []
  defp places(details), do: WizardPanel.item_places(details)

  defp premade do
    case ItemData.table() do
      {:ok, table} -> table
      _ -> nil
    end
  end

  defp powers do
    case ItemPowers.table() do
      {:ok, table} -> table
      _ -> nil
    end
  end

  defp spell_table do
    case Spells.table() do
      {:ok, table} -> table
      _ -> nil
    end
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
              <p
                :if={@details.banished}
                id="wizard-banished"
                class="mt-1 inline-block rounded border border-rose-300/50 px-2 py-0.5 text-sm text-rose-200"
                title="The game draws this wizard as a cracked stone frame: his fortress is marked inactive. He can come back with Spell of Return."
              >
                Banished
              </p>
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
            <fieldset>
              <legend class="mb-1 text-sm text-slate-300">Global enchantments</legend>
              <input type="hidden" name="wizard[globals_present]" value="1" />
              <div class="grid grid-cols-2 gap-1 sm:grid-cols-3">
                <label
                  :for={{{name, on}, i} <- Enum.with_index(@details.global_flags)}
                  class="flex items-center gap-2 text-sm text-slate-200"
                >
                  <input
                    type="checkbox"
                    name={"wizard[globals][#{i}]"}
                    checked={on}
                    disabled={i == WizardPanel.time_stop_index()}
                  />
                  {name}
                </label>
              </div>
              <p class="mt-1 text-xs text-slate-400">
                Time Stop is not editable: the game keeps more state for it than the flag.
              </p>
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
              <span :if={@details.researching} id="wizard-researching">
                {spell_name(@spell_table, @details.researching.number)}{realm_suffix(
                  @details.researching
                )}, {@details.research_left} research points left
              </span>
            </p>
            <div
              :if={@editing}
              id="wizard-research-edit"
              class="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2"
            >
              <label class="text-sm text-slate-300">
                Researching (the game's research list)
                <select
                  form="wizard-form"
                  name="wizard[researching]"
                  class="mt-1 w-full rounded bg-slate-900 px-2 py-1 text-white"
                >
                  <option :if={@details.researching_number == 0} value="0" selected>
                    nothing
                  </option>
                  <option
                    :for={n <- WizardPanel.research_options(@details)}
                    value={n}
                    selected={n == @details.researching_number}
                  >
                    {spell_name(@spell_table, n)}
                  </option>
                </select>
              </label>
              <label class="text-sm text-slate-300">
                Research points left (0 to 65535)
                <input
                  form="wizard-form"
                  type="number"
                  min="0"
                  max="65535"
                  name="wizard[research_left]"
                  value={@details.research_left}
                  class="mt-1 w-full rounded bg-slate-900 px-2 py-1 text-white"
                />
              </label>
            </div>
          </section>

          <section id="wizard-spells" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Spells</h2>
            <p :if={!@spell_table} class="mb-2 text-xs text-amber-200">
              Spell names need SPELLDAT.LBX in the game folder (run mix mirror.import_game); numbers are shown instead.
            </p>
            <input
              :if={@editing}
              form="wizard-form"
              type="hidden"
              name="wizard[spells_present]"
              value="1"
            />
            <div :for={{realm, rows} <- @spell_rows} id={"wizard-spells-#{realm}"} class="mb-3">
              <div class="flex flex-wrap items-center gap-3">
                <h3 class="font-semibold text-slate-100">
                  {realm_label(realm)}
                  <span class="font-normal text-slate-400">
                    {Enum.count(rows, &(&1.state == 2))} of {length(rows)} known
                  </span>
                </h3>
                <button
                  :if={@editing}
                  id={"learn-#{realm}"}
                  type="button"
                  phx-click="learn_realm"
                  phx-value-realm={realm}
                  class="rounded border border-emerald-300/40 px-2 py-0.5 text-xs text-emerald-100 hover:border-emerald-200"
                >
                  Learn every {realm_label(realm)} spell
                </button>
              </div>
              <p :if={!@editing} class="text-sm text-slate-200">
                <span :if={Enum.all?(rows, &(&1.state != 2))} class="text-slate-500">none</span>
                {rows |> Enum.filter(&(&1.state == 2)) |> Enum.map_join(", ", & &1.name)}
              </p>
              <div :if={@editing} class="mt-1 grid grid-cols-2 gap-x-3 sm:grid-cols-3">
                <label
                  :for={row <- rows}
                  class="flex items-center gap-2 text-sm text-slate-200"
                  title={state_title(row.state)}
                >
                  <input
                    form="wizard-form"
                    type="checkbox"
                    name={"wizard[spells][#{row.number}]"}
                    checked={row.state == 2}
                  />
                  {row.name}
                  <span :if={row.state == 3} class="text-xs text-sky-300">(research list)</span>
                </label>
              </div>
            </div>
            <button
              :if={@editing}
              form="wizard-form"
              type="submit"
              class="rounded-lg bg-emerald-300 px-4 py-1 text-sm font-semibold text-slate-950 hover:bg-emerald-200"
            >
              Apply
            </button>
          </section>

          <section id="wizard-relations" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Relations</h2>
            <input
              :if={@editing}
              form="wizard-form"
              type="hidden"
              name="wizard[relations_present]"
              value="1"
            />
            <table class="w-full text-left text-sm text-slate-200">
              <thead class="text-xs text-slate-400">
                <tr>
                  <th class="pb-1 font-normal">Wizard</th>
                  <th class="pb-1 font-normal">Standing</th>
                  <th class="pb-1 text-right font-normal">Relation</th>
                  <th class="pb-1 pl-4 font-normal">Contact</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={r <- @details.relations}
                  id={"wizard-relation-#{r.other}"}
                  class="border-t border-white/5"
                >
                  <td class="py-1">
                    <.link
                      :if={r.page}
                      navigate={~p"/wizard/#{r.page}"}
                      class="underline decoration-dotted"
                    >
                      {r.name}
                    </.link>
                    <span :if={!r.page}>{r.name}</span>
                  </td>
                  <td
                    class="py-1"
                    title={
                      if WizardPanel.status_checked?(r.status),
                        do: nil,
                        else: "This code's meaning has not been confirmed in the game yet"
                    }
                  >
                    <select
                      :if={@editing and r.other < 5 and not r.banished}
                      form="wizard-form"
                      name={"wizard[relations][#{r.other}][status]"}
                      class="rounded bg-slate-900 px-1 py-0.5 text-white"
                    >
                      <option
                        :for={{value, label} <- WizardPanel.status_options(r.status)}
                        value={value}
                        selected={value == r.status}
                      >
                        {label}
                      </option>
                    </select>
                    <span :if={!(@editing and r.other < 5 and not r.banished)}>
                      {r.tag}{if !WizardPanel.status_checked?(r.status), do: "?"}
                    </span>
                    <span :if={r.banished} class="ml-2 text-xs text-rose-300">banished</span>
                  </td>
                  <td class={["py-1 text-right tabular-nums", relation_class(r.relation)]}>
                    <input
                      :if={@editing and r.other < 5 and not r.banished}
                      form="wizard-form"
                      type="number"
                      min="-100"
                      max="100"
                      name={"wizard[relations][#{r.other}][relation]"}
                      value={r.relation}
                      class="w-20 rounded bg-slate-900 px-1 py-0.5 text-right text-white"
                    />
                    <span :if={!(@editing and r.other < 5 and not r.banished)}>
                      {if r.relation > 0, do: "+"}{r.relation}
                    </span>
                  </td>
                  <td class="py-1 pl-4 text-slate-400">
                    {cond do
                      r.other == 5 -> "–"
                      r.contacted -> "met"
                      true -> "not met"
                    end}
                  </td>
                </tr>
              </tbody>
            </table>
            <p class="mt-2 text-xs text-slate-400">
              The relation is the figure the game's Diplomacy screen shows. A "?" after a standing means the
              code's meaning has not been checked in the game yet.
            </p>
            <p :if={@editing} class="mt-1 text-xs text-slate-400">
              A change is written to both wizards. The treaty codes are what the game keeps; it
              does not check them, so an alliance with someone at war with your ally is yours to sort out.
            </p>
            <button
              :if={@editing}
              form="wizard-form"
              type="submit"
              class="mt-2 rounded-lg bg-emerald-300 px-4 py-1 text-sm font-semibold text-slate-950 hover:bg-emerald-200"
            >
              Apply
            </button>
          </section>

          <section id="wizard-globals" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Global enchantments</h2>
            <p :if={@details.globals == []} class="text-slate-500">none cast by this wizard</p>
            <ul :if={@details.globals != []} class="flex flex-wrap gap-2">
              <li
                :for={name <- @details.globals}
                class="rounded-full border border-white/20 px-3 py-1 text-sm text-slate-100"
              >
                {name}
              </li>
            </ul>
          </section>

          <section id="wizard-heroes" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Heroes</h2>
            <p :if={@details.heroes == []} class="text-slate-500">none</p>
            <ul :if={@details.heroes != []} class="space-y-2">
              <li
                :for={h <- @details.heroes}
                id={"wizard-hero-#{h.slot}"}
                class="rounded-lg border border-white/10 px-3 py-2 text-sm text-slate-200"
              >
                <p>
                  <span class="font-semibold text-white">{h.name}</span>
                  · {h.type_name} · level {h.level} · {h.experience} xp
                  · at {h.location.x}, {h.location.y} {plane_name(h.location.plane)}
                </p>
                <p class="text-slate-400">
                  Casting skill {h.casting_skill}
                  <span :if={h.spells != []}>
                    · {Enum.map_join(h.spells, ", ", &spell_name(@spell_table, &1))}
                  </span>
                </p>
                <.item_list
                  items={Enum.map(h.item_list, &ItemPanel.describe(&1, @powers, @spell_table))}
                  prefix={"wizard-hero-#{h.slot}-item"}
                  editing={@editing}
                  powers={@powers}
                  moves={@moves}
                />
                <.place_forms
                  :if={@editing and @premade}
                  places={Enum.filter(@places, &(&1.hero && &1.place |> elem(1) == h.slot))}
                  premade={@premade}
                />
                <form
                  :if={@editing}
                  id={"wizard-hero-form-#{h.slot}"}
                  phx-submit="hero_edit"
                  class="mt-2 flex flex-wrap items-end gap-2"
                >
                  <input type="hidden" name="slot" value={h.slot} />
                  <label class="text-xs text-slate-400">
                    Name
                    <input
                      type="text"
                      name="hero[name]"
                      value={h.name}
                      maxlength="13"
                      class="mt-1 block w-36 rounded bg-slate-900 px-2 py-1 text-sm text-white"
                    />
                  </label>
                  <label class="text-xs text-slate-400">
                    Level
                    <input
                      type="number"
                      name="hero[level]"
                      value={h.level}
                      min="0"
                      max="9"
                      class="mt-1 block w-20 rounded bg-slate-900 px-2 py-1 text-sm text-white"
                    />
                  </label>
                  <label class="text-xs text-slate-400">
                    Experience
                    <input
                      type="number"
                      name="hero[experience]"
                      value={h.experience}
                      min="0"
                      max="30000"
                      class="mt-1 block w-24 rounded bg-slate-900 px-2 py-1 text-sm text-white"
                    />
                  </label>
                  <label class="text-xs text-slate-400">
                    Damage
                    <input
                      type="number"
                      name="hero[damage]"
                      value={h.damage}
                      min="0"
                      max="255"
                      class="mt-1 block w-20 rounded bg-slate-900 px-2 py-1 text-sm text-white"
                    />
                  </label>
                  <button
                    type="submit"
                    class="rounded-lg bg-emerald-300 px-3 py-1 text-sm font-semibold text-slate-950 hover:bg-emerald-200"
                  >
                    Apply
                  </button>
                </form>
              </li>
            </ul>

            <form
              :if={@editing and WizardPanel.hero_choices(@details) != []}
              id="wizard-hero-add"
              phx-submit="hero_add"
              class="mt-3 flex flex-wrap items-end gap-2"
            >
              <label class="text-xs text-slate-400">
                Add a hero
                <select
                  name="type"
                  class="mt-1 block w-48 rounded bg-slate-900 px-2 py-1 text-sm text-white"
                >
                  <option :for={{type, name} <- WizardPanel.hero_choices(@details)} value={type}>
                    {name}
                  </option>
                </select>
              </label>
              <button
                type="submit"
                class="rounded-lg border border-emerald-300/50 px-3 py-1 text-xs text-emerald-100 hover:border-emerald-200"
              >
                Add
              </button>
              <span class="text-xs text-slate-500">
                A new hero, level 0, on his summoning circle.
              </span>
            </form>
          </section>

          <section id="wizard-vault" class="rounded-xl border border-white/10 bg-black/30 p-4">
            <h2 class="mb-2 text-lg font-semibold text-white">Vault</h2>
            <p :if={@details.vault == []} class="text-slate-500">no spare items</p>
            <.item_list
              items={Enum.map(@details.vault, &ItemPanel.describe(&1, @powers, @spell_table))}
              prefix="wizard-vault-item"
              editing={@editing}
              powers={@powers}
              moves={@moves}
            />
            <.place_forms
              :if={@editing and @premade}
              places={Enum.filter(@places, &is_nil(&1.hero))}
              premade={@premade}
            />
            <p :if={@editing and is_nil(@premade)} class="mt-2 text-xs text-slate-500">
              Filling a place with a premade item needs ITEMDATA.LBX in the game folder (run mix mirror.import_game).
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

  defp relation_class(r) when r >= 10, do: "text-emerald-300"
  defp relation_class(r) when r <= -10, do: "text-rose-300"
  defp relation_class(_), do: "text-slate-200"

  defp spell_name(table, number), do: Spells.name(table, number)

  attr :items, :list, required: true
  attr :prefix, :string, required: true
  attr :editing, :boolean, default: false
  attr :powers, :any, default: nil
  attr :moves, :map, default: %{}

  defp item_list(assigns) do
    ~H"""
    <ul :if={@items != []} class="mt-1 space-y-1">
      <li
        :for={item <- @items}
        id={"#{@prefix}-#{item.index}"}
        class="rounded border border-white/10 px-2 py-1 text-xs text-slate-300"
      >
        <span class="font-semibold text-amber-200">{item.name}</span>
        · {item.kind} · {item.cost} gold
        <span :if={item.stats != []}>· {Enum.join(item.stats, ", ")}</span>
        <span :if={item.powers != []}>· {Enum.join(item.powers, ", ")}</span>
        <span :if={item.spell}>· {item.spell}</span>
        <span :if={item.unnamed_powers} class="text-slate-500">
          · has powers (names need ITEMPOW.LBX; run mix mirror.import_game)
        </span>
        <form
          :if={@editing}
          id={"wizard-item-form-#{item.index}"}
          phx-submit="item_edit"
          class="mt-2 space-y-2"
        >
          <input type="hidden" name="index" value={item.index} />
          <div class="flex flex-wrap items-end gap-2">
            <label class="text-xs text-slate-400">
              Name
              <input
                type="text"
                name="item[name]"
                value={item.name}
                maxlength="26"
                class="mt-1 block w-44 rounded bg-slate-900 px-2 py-1 text-sm text-white"
              />
            </label>
            <label :for={{field, label, max} <- item_fields()} class="text-xs text-slate-400">
              {label}
              <input
                type="number"
                name={"item[#{field}]"}
                value={Map.fetch!(item.raw, field)}
                min="0"
                max={max}
                class="mt-1 block w-20 rounded bg-slate-900 px-2 py-1 text-sm text-white"
              />
            </label>
            <label class="text-xs text-slate-400">
              Movement
              <input
                type="number"
                name="item[movement]"
                value={ItemPanel.movement_shown(item.raw.movement)}
                min="0"
                max="4"
                step="0.5"
                class="mt-1 block w-20 rounded bg-slate-900 px-2 py-1 text-sm text-white"
              />
            </label>
          </div>
          <fieldset :if={is_list(@powers)}>
            <legend class="text-xs text-slate-400">Powers</legend>
            <input type="hidden" name="item[powers_present]" value="1" />
            <div class="grid grid-cols-2 gap-x-3 sm:grid-cols-4">
              <label
                :for={p <- Enum.filter(@powers, &(&1.mask != 0))}
                class="flex items-center gap-1 text-xs text-slate-300"
              >
                <input
                  type="checkbox"
                  name={"item[powers][#{p.mask}]"}
                  checked={Bitwise.band(item.raw.abilities, p.mask) == p.mask}
                />
                {p.name}
              </label>
            </div>
          </fieldset>
          <button
            type="submit"
            class="rounded-lg bg-emerald-300 px-3 py-1 text-xs font-semibold text-slate-950 hover:bg-emerald-200"
          >
            Apply
          </button>
        </form>
        <form
          :if={@editing and Map.get(@moves, item.index, []) != []}
          id={"wizard-item-move-#{item.index}"}
          phx-submit="item_move"
          class="mt-2 flex items-end gap-2"
        >
          <input type="hidden" name="index" value={item.index} />
          <label class="text-xs text-slate-400">
            Move to
            <select
              name="to"
              class="mt-1 block rounded bg-slate-900 px-2 py-1 text-sm text-white"
            >
              <option :for={{value, label} <- Map.fetch!(@moves, item.index)} value={value}>
                {label}
              </option>
            </select>
          </label>
          <button
            type="submit"
            class="rounded-lg border border-emerald-300/50 px-3 py-1 text-xs text-emerald-100 hover:border-emerald-200"
          >
            Move
          </button>
        </form>
      </li>
    </ul>
    """
  end

  # `{field, label, max}` for the plain number boxes; movement has its own (half points).
  defp item_fields do
    [
      {:cost, "Cost", 65_535},
      {:attack, "Attack", 6},
      {:to_hit, "To hit", 3},
      {:defense, "Defense", 6},
      {:resistance, "Resistance", 6},
      {:spell_skill, "Spell skill", 20},
      {:spell_save, "Spell save", 4}
    ]
  end

  attr :places, :list, required: true
  attr :premade, :list, required: true

  # One small form per item place: a select of what could go there (a hero's place takes the premade items of its own
  # kind, the vault any) and a Set button.
  defp place_forms(assigns) do
    ~H"""
    <div class="mt-2 space-y-1">
      <form
        :for={pl <- @places}
        id={"wizard-place-#{String.replace(pl.key, ":", "-")}"}
        phx-submit="place_set"
        class="flex flex-wrap items-end gap-2"
      >
        <input type="hidden" name="place" value={pl.key} />
        <label class="text-xs text-slate-400">
          {place_label(pl)}
          <select
            name="choice"
            class="mt-1 block w-64 rounded bg-slate-900 px-2 py-1 text-sm text-white"
          >
            <option :for={{value, label} <- WizardPanel.place_choices(pl, @premade)} value={value}>
              {label}
            </option>
          </select>
        </label>
        <button
          type="submit"
          class="rounded-lg border border-emerald-300/50 px-3 py-1 text-xs text-emerald-100 hover:border-emerald-200"
        >
          Set
        </button>
      </form>
    </div>
    """
  end

  defp place_label(%{hero: nil, place: {:vault, n}}), do: "Vault place #{n + 1}"

  defp place_label(%{place: {:hero, _, n}, slot_type: type}),
    do: "Place #{n + 1} (#{Mirror.SaveFile.Items.slot_name(type) || "slot #{type}"})"

  defp realm_label(realm), do: realm |> Atom.to_string() |> String.capitalize()

  defp state_title(0), do: "not known"
  defp state_title(1), do: "can be researched later"
  defp state_title(2), do: "known"
  defp state_title(3), do: "on the research list"
  defp state_title(_), do: ""

  defp realm_suffix(%{realm: nil}), do: ""
  defp realm_suffix(%{realm: realm}), do: " (#{realm})"
end
