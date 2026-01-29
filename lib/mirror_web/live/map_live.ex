defmodule MirrorWeb.MapLive do
  use MirrorWeb, :live_view

  alias Mirror.{Paths, SaveFile, SessionStore, Stats, TileAtlas}
  alias Mirror.Map, as: MirrorMap

  @layers [
    :terrain,
    :terrain_flags,
    :minerals,
    :exploration,
    :landmass,
    :computed_adj_mask
  ]

  @u16_layers [:terrain]

  @layer_labels %{
    terrain: "Terrain (u16)",
    terrain_flags: "Terrain Flags",
    minerals: "Minerals",
    exploration: "Exploration",
    landmass: "Landmass",
    computed_adj_mask: "Adjacency Mask"
  }

  @impl true
  def mount(_params, session, socket) do
    session_id = session["mirror_session_id"] || "local"
    plane = socket.assigns.live_action || :arcanus

    state =
      session_id
      |> SessionStore.get()
      |> normalize_state()

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:plane, plane)
      |> assign_from_state(state)
      |> assign(:active_stroke, nil)
      |> assign(:hover, nil)
      |> assign(:tile_assets, nil)
      |> assign(:load_path, default_load_path())
      |> assign(:save_path_input, state.save_path || "")
      |> assign_forms()

    if connected?(socket) and state.save do
      socket = push_map_state(socket)
      socket = push_map_reload(socket)
      socket = maybe_push_tile_assets(socket)
      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("load_save", %{"load" => %{"path" => path}}, socket) do
    path = String.trim(path || "")

    socket =
      socket
      |> assign(:load_path, path)
      |> assign_forms()

    case SaveFile.load(path) do
      {:ok, save} ->
        planes =
          save.planes
          |> Enum.into(%{}, fn {plane_key, plane_layers} ->
            computed = MirrorMap.computed_adj_mask(plane_layers.terrain)
            {plane_key, Map.put(plane_layers, :computed_adj_mask, computed)}
          end)

        state = %{
          save: save,
          planes: planes,
          active_layer: :terrain,
          selection: default_selection(),
          history: %{arcanus: [], myrror: []},
          redo: %{arcanus: [], myrror: []},
          save_path: save.path,
          dataset_id: save.dataset_id,
          render_mode: socket.assigns.state.render_mode || :tiles
        }

        SessionStore.put(socket.assigns.session_id, state)
        observe_stats(state)

        socket =
          socket
          |> assign_from_state(state)
          |> assign_forms()
          |> put_flash(:info, "Loaded save from #{path}.")

        socket =
          if connected?(socket) do
            socket
            |> push_map_state()
            |> push_map_reload()
            |> maybe_push_tile_assets()
          else
            socket
          end

        {:noreply, socket}

      {:error, {:missing_offset, layer}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Missing block offset for #{layer}. Set config before loading."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Unable to load save: #{inspect(reason)}")}
    end
  end

  def handle_event("save_file", %{"save" => %{"path" => path}}, socket) do
    path = String.trim(path || "")
    target_path = if path == "", do: nil, else: path
    state = socket.assigns.state
    socket = assign(socket, :save_path_input, path)

    with %SaveFile{} = save <- state.save,
         {:ok, save_path} <-
           SaveFile.write(%{save | planes: strip_computed(state.planes)}, target_path) do
      state = %{state | save_path: save_path}
      SessionStore.put(socket.assigns.session_id, state)
      {:noreply, put_flash(assign(socket, :state, state), :info, "Saved to #{save_path}.")}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Load a save before saving.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
    end
  end

  def handle_event("set_active_layer", %{"layer" => layer}, socket) do
    state = socket.assigns.state
    layer = Enum.find(@layers, state.active_layer, &(&1 |> Atom.to_string() == layer))
    state = %{state | active_layer: layer}

    SessionStore.put(socket.assigns.session_id, state)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()

    socket =
      if connected?(socket) do
        socket
        |> push_map_state()
        |> push_map_reload()
        |> maybe_push_tile_assets()
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("set_selection", %{"selection" => %{"value" => value}}, socket) do
    set_selection_from_value(socket, value)
  end

  def handle_event("set_selection", %{"value" => value}, socket) do
    set_selection_from_value(socket, value)
  end

  def handle_event(
        "set_value_name",
        %{"value_name" => %{"value" => value, "name" => name}},
        socket
      ) do
    state = socket.assigns.state

    if state.dataset_id do
      value = parse_int(value, 0)
      _ = Stats.set_value_name(state.dataset_id, state.active_layer, value, name || "")
    end

    {:noreply, assign_forms(socket)}
  end

  def handle_event("set_bit_name", %{"bit_name" => %{"bit" => bit, "name" => name}}, socket) do
    state = socket.assigns.state

    if state.dataset_id do
      bit = parse_int(bit, 0)
      _ = Stats.set_bit_name(state.dataset_id, state.active_layer, bit, name || "")
    end

    {:noreply, assign_forms(socket)}
  end

  def handle_event("map_pointer", params, socket) do
    state = socket.assigns.state

    if state.save do
      action = params["action"]
      {x, y} = {parse_int(params["x"], -1), parse_int(params["y"], -1)}
      button = parse_int(params["button"], 0)
      mods = params["mods"] || %{}

      socket =
        case action do
          "hover" ->
            assign_hover(socket, x, y)

          "wheel" ->
            apply_wheel(socket, mods, params["delta"])

          "start" ->
            handle_pointer_start(socket, x, y, button, mods)

          "drag" ->
            handle_pointer_drag(socket, x, y)

          "end" ->
            handle_pointer_end(socket)

          _ ->
            socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("undo", _params, socket) do
    {:noreply, apply_undo(socket)}
  end

  def handle_event("redo", _params, socket) do
    {:noreply, apply_redo(socket)}
  end

  def handle_event("export_stats", _params, socket) do
    state = socket.assigns.state

    if state.dataset_id do
      export = Stats.export(state.dataset_id)
      json = Jason.encode!(export, pretty: true)

      {:noreply,
       push_event(socket, "stats_export", %{
         filename: "mirror-stats-#{encode_dataset(state.dataset_id)}.json",
         content: json
       })}
    else
      {:noreply, put_flash(socket, :error, "Load a save to export stats.")}
    end
  end

  def handle_event("update_load_path", %{"load" => %{"path" => path}}, socket) do
    {:noreply, assign(socket, :load_path, path)}
  end

  def handle_event("update_save_path", %{"save" => %{"path" => path}}, socket) do
    {:noreply, assign(socket, :save_path_input, path)}
  end

  def handle_event("toggle_render_mode", _params, socket) do
    state = socket.assigns.state

    render_mode =
      case state.render_mode do
        :tiles -> :values
        _ -> :tiles
      end

    state = %{state | render_mode: render_mode}
    SessionStore.put(socket.assigns.session_id, state)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()

    socket =
      if connected?(socket) do
        socket = push_event(socket, "map_render_mode", %{mode: Atom.to_string(render_mode)})

        if render_mode == :tiles do
          maybe_push_tile_assets(socket)
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("reload_tiles", _params, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign(:tile_assets, nil)
        |> maybe_push_tile_assets()
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_bleed>
      <div class="relative min-h-[100svh]">
        <div class="relative flex min-h-[100svh] flex-col">
          <header class="pointer-events-auto border-b border-white/10 bg-slate-950/80 px-6 py-5 shadow-lg shadow-black/60 backdrop-blur">
            <div class="rounded-3xl border border-white/10 bg-slate-950/70 p-6 shadow-xl shadow-black/60 backdrop-blur">
              <div class="flex flex-wrap items-end justify-between gap-4">
                <div>
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Plane view</p>
                  <h2 class="text-3xl font-semibold text-white">
                    {if @plane == :arcanus, do: "Arcanus", else: "Myrror"}
                  </h2>
                  <p class="text-sm text-slate-400">
                    {if @state.save_path, do: @state.save_path, else: "No save loaded yet."}
                  </p>
                </div>
                <div class="flex flex-wrap gap-3">
                  <button
                    id="undo-button"
                    type="button"
                    phx-click="undo"
                    class="rounded-full border border-white/20 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                  >
                    Undo
                  </button>
                  <button
                    id="redo-button"
                    type="button"
                    phx-click="redo"
                    class="rounded-full border border-white/20 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                  >
                    Redo
                  </button>
                  <button
                    id="render-mode-button"
                    type="button"
                    phx-click="toggle_render_mode"
                    class="rounded-full border border-amber-300/40 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-amber-100 transition hover:border-amber-200"
                  >
                    Render: {if @render_mode == :tiles, do: "Tiles", else: "Values"}
                  </button>
                  <button
                    :if={@render_mode == :tiles}
                    id="reload-tiles-button"
                    type="button"
                    phx-click="reload_tiles"
                    class="rounded-full border border-emerald-300/40 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-emerald-100 transition hover:border-emerald-200"
                  >
                    Reload tiles
                  </button>
                  <button
                    id="export-stats-button"
                    type="button"
                    phx-click="export_stats"
                    class="rounded-full border border-white/20 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                  >
                    Export stats
                  </button>
                </div>
              </div>
            </div>
            <div class="mt-4 grid gap-3 lg:grid-cols-[1.2fr_0.8fr]">
              <.form
                for={@load_form}
                id="load-form"
                phx-submit="load_save"
                phx-change="update_load_path"
                class="grid gap-3 md:grid-cols-[1fr_auto]"
              >
                <.input
                  field={@load_form[:path]}
                  type="text"
                  placeholder="C:\\games\\MOM\\SAVES\\SAVE1.SAV"
                  class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200 placeholder:text-slate-500"
                />
                <button
                  id="load-save-button"
                  type="submit"
                  class="rounded-2xl bg-amber-300 px-5 py-2 text-sm font-semibold text-slate-950 shadow-lg shadow-amber-500/30 transition hover:-translate-y-0.5 hover:bg-amber-200"
                >
                  Load save
                </button>
              </.form>
              <.form
                for={@save_form}
                id="save-form"
                phx-submit="save_file"
                phx-change="update_save_path"
                class="grid gap-3 md:grid-cols-[1fr_auto]"
              >
                <.input
                  field={@save_form[:path]}
                  type="text"
                  placeholder="Output path (optional)"
                  class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200 placeholder:text-slate-500"
                />
                <button
                  id="save-button"
                  type="submit"
                  class="rounded-2xl border border-emerald-300/40 px-5 py-2 text-sm font-semibold text-emerald-100 transition hover:border-emerald-200"
                >
                  Save
                </button>
              </.form>
            </div>
          </header>

          <div class="flex-1 min-h-0">
            <div class="grid h-full gap-0 lg:grid-cols-[minmax(18rem,24rem)_minmax(0,1fr)_minmax(18rem,24rem)]">
              <div class="flex h-full flex-col gap-6 overflow-y-auto border-r border-white/10 bg-slate-950/90 p-4">
                <div class="rounded-3xl border border-white/10 bg-slate-950/70 p-6 shadow-lg shadow-black/60 backdrop-blur">
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Map editor</p>
                      <h3 class="text-lg font-semibold text-white">Layer stack + tools</h3>
                    </div>
                  </div>

                  <div class="mt-6 grid gap-6 lg:grid-cols-[0.5fr_1fr]">
                    <div class="space-y-4">
                      <div class="space-y-2">
                        <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Layers</p>
                        <div class="space-y-2">
                          <%= for layer <- @layers do %>
                            <button
                              id={"layer-#{layer}"}
                              type="button"
                              phx-click="set_active_layer"
                              phx-value-layer={Atom.to_string(layer)}
                              class={[
                                "w-full rounded-2xl border px-3 py-2 text-left text-sm transition",
                                layer == @active_layer &&
                                  "border-amber-300/60 bg-amber-300/10 text-white",
                                layer != @active_layer &&
                                  "border-white/10 text-slate-300 hover:border-white/30"
                              ]}
                            >
                              <span class="font-semibold">{@layer_labels[layer]}</span>
                              <%= if layer == :computed_adj_mask do %>
                                <span class="ml-2 text-[0.65rem] uppercase tracking-[0.2em] text-slate-500">
                                  Derived
                                </span>
                              <% end %>
                            </button>
                          <% end %>
                        </div>
                      </div>

                      <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-4">
                        <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Selection</p>
                        <.form
                          for={@selection_form}
                          id="selection-form"
                          phx-submit="set_selection"
                          class="mt-3 space-y-3"
                        >
                          <.input
                            field={@selection_form[:value]}
                            type="number"
                            class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200"
                          />
                          <button
                            id="apply-selection-button"
                            type="submit"
                            class="w-full rounded-2xl border border-white/20 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                          >
                            Apply value
                          </button>
                        </.form>
                        <p class="mt-3 text-xs text-slate-500">
                          Scroll to cycle values. Right-click to sample.
                        </p>
                      </div>
                    </div>

                    <div class="space-y-4">
                      <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-4 text-xs text-slate-400">
                        <p class="uppercase tracking-[0.3em] text-slate-500">Controls</p>
                        <div class="mt-3 grid gap-2 sm:grid-cols-2">
                          <div class="flex items-start gap-2">
                            <.icon name="hero-hand-raised" class="size-4 text-amber-300" />
                            <span>Left drag paints with the current selection.</span>
                          </div>
                          <div class="flex items-start gap-2">
                            <.icon name="hero-eye" class="size-4 text-sky-300" />
                            <span>Right click samples the current layer.</span>
                          </div>
                          <div class="flex items-start gap-2">
                            <.icon name="hero-adjustments-horizontal" class="size-4 text-emerald-300" />
                            <span>Alt/Shift modify the scroll step size.</span>
                          </div>
                          <div class="flex items-start gap-2">
                            <.icon name="hero-command-line" class="size-4 text-indigo-300" />
                            <span>Ctrl toggles sampling mode.</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div class="relative bg-slate-950">
                <canvas
                  id="map-canvas"
                  phx-hook="MapCanvas"
                  phx-update="ignore"
                  data-map-width={@map_width}
                  data-map-height={@map_height}
                  data-layer-type={layer_type(@active_layer)}
                  data-tiles={@encoded_layer}
                  data-terrain={@terrain_encoded}
                  data-terrain-flags={@terrain_flags_encoded}
                  data-minerals={@minerals_encoded}
                  data-render-mode={Atom.to_string(@render_mode)}
                  data-tile-size="32"
                  class="absolute inset-0 h-full w-full"
                >
                </canvas>
              </div>

              <aside class="flex h-full flex-col gap-6 overflow-y-auto border-l border-white/10 bg-slate-950/90 p-4">
                <div class="rounded-3xl border border-white/10 bg-slate-950/70 p-6 shadow-lg shadow-black/60 backdrop-blur pointer-events-auto">
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Research</p>
                  <h3 class="mt-2 text-lg font-semibold text-white">Value intel</h3>
                  <div class="mt-4 space-y-3">
                    <.form
                      for={@value_name_form}
                      id="value-name-form"
                      phx-submit="set_value_name"
                      class="grid gap-3"
                    >
                      <div class="grid gap-3 sm:grid-cols-2">
                        <.input
                          field={@value_name_form[:value]}
                          type="number"
                          class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200"
                        />
                        <.input
                          field={@value_name_form[:name]}
                          type="text"
                          placeholder="Label this value"
                          class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200 placeholder:text-slate-500"
                        />
                      </div>
                      <button
                        id="save-value-name-button"
                        type="submit"
                        class="rounded-2xl border border-white/20 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                      >
                        Save label
                      </button>
                    </.form>

                    <div class="rounded-2xl border border-white/10 bg-slate-950/50 p-4">
                      <p class="text-xs uppercase tracking-[0.3em] text-slate-500">Histogram</p>
                      <div class="mt-3 space-y-2">
                        <%= for entry <- hist_entries(@state, @active_layer) do %>
                          <button
                            id={"hist-#{entry.value}"}
                            type="button"
                            phx-click="set_selection"
                            phx-value-value={entry.value}
                            class="flex w-full items-center justify-between rounded-xl border border-white/10 px-3 py-2 text-xs text-slate-200 transition hover:border-white/30"
                          >
                            <span class="font-semibold">#{entry.value}</span>
                            <span class="text-slate-500">{entry.name || "???"}</span>
                            <span class="text-slate-400">{entry.count}</span>
                          </button>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="rounded-3xl border border-white/10 bg-slate-950/70 p-6 shadow-lg shadow-black/60 backdrop-blur pointer-events-auto">
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Bit names</p>
                  <div class="mt-4 space-y-3">
                    <%= for {bit, form} <- @bit_forms do %>
                      <.form
                        for={form}
                        id={"bit-form-#{bit}"}
                        phx-submit="set_bit_name"
                        class="flex items-center gap-3"
                      >
                        <.input field={form[:bit]} type="hidden" />
                        <span class="text-xs font-semibold text-slate-300">Bit {bit}</span>
                        <.input
                          field={form[:name]}
                          type="text"
                          placeholder="Name"
                          class="flex-1 rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200 placeholder:text-slate-500"
                        />
                        <button
                          type="submit"
                          class="rounded-full border border-white/20 px-3 py-2 text-[0.6rem] font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                        >
                          Save
                        </button>
                      </.form>
                    <% end %>
                  </div>
                </div>

                <div class="rounded-3xl border border-white/10 bg-slate-950/70 p-6 shadow-lg shadow-black/60 backdrop-blur pointer-events-auto">
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Hover vision</p>
                  <div class="mt-4 space-y-2 text-sm text-slate-300">
                    <%= if @hover do %>
                      <p>Tile: ({@hover.x}, {@hover.y})</p>
                      <p>Terrain: {@hover.terrain} ({@hover.terrain_class})</p>
                      <p>Adj mask: {@hover.adj_mask}</p>
                      <div class="mt-3 grid gap-2 text-xs">
                        <%= for ray <- @hover.rays do %>
                          <div class="flex items-center justify-between rounded-lg border border-white/10 px-3 py-2">
                            <span class="uppercase text-slate-400">{ray.dir}</span>
                            <span class="text-slate-200">{ray.hit}</span>
                            <span class="text-slate-500">d{ray.dist}</span>
                          </div>
                        <% end %>
                      </div>
                    <% else %>
                      <p class="text-slate-500">Hover a tile to inspect adjacency and ray hits.</p>
                    <% end %>
                  </div>
                </div>
              </aside>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp set_selection_from_value(socket, value) do
    state = socket.assigns.state
    layer = state.active_layer
    value = parse_int(value, 0)
    selection = Map.put(state.selection, layer, clamp_value(layer, value))
    state = %{state | selection: selection}

    SessionStore.put(socket.assigns.session_id, state)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()

    {:noreply, socket}
  end

  defp handle_pointer_start(socket, x, y, button, mods) do
    {tool, layer} = tool_and_layer(socket, button, mods)

    cond do
      tool == :sample ->
        sample_tile(socket, layer, x, y)

      tool == :paint ->
        start_stroke(socket, layer, x, y)

      true ->
        socket
    end
  end

  defp handle_pointer_drag(socket, x, y) do
    case socket.assigns.active_stroke do
      %{layer: layer} ->
        apply_stroke_change(socket, layer, x, y)

      _ ->
        socket
    end
  end

  defp handle_pointer_end(socket) do
    case socket.assigns.active_stroke do
      nil ->
        socket

      stroke ->
        finalize_stroke(socket, stroke)
    end
  end

  defp apply_wheel(socket, mods, delta) do
    state = socket.assigns.state
    layer = state.active_layer
    delta = parse_int(delta, 0)

    step =
      cond do
        truthy?(mods["alt"]) -> if layer in @u16_layers, do: 256, else: 16
        truthy?(mods["shift"]) -> if layer in @u16_layers, do: 64, else: 4
        true -> 1
      end

    direction = if delta > 0, do: -1, else: 1
    next_value = Map.get(state.selection, layer, 0) + direction * step

    selection = Map.put(state.selection, layer, clamp_value(layer, next_value))
    state = %{state | selection: selection}

    SessionStore.put(socket.assigns.session_id, state)

    socket
    |> assign_from_state(state)
    |> assign_forms()
  end

  defp start_stroke(socket, layer, x, y) do
    {socket, change} = apply_tile_change(socket, layer, x, y)

    case change do
      nil ->
        socket

      {prev, new} ->
        stroke = %{
          layer: layer,
          changes: %{{x, y} => {prev, new}}
        }

        assign(socket, :active_stroke, stroke)
    end
  end

  defp apply_stroke_change(socket, layer, x, y) do
    {socket, change} = apply_tile_change(socket, layer, x, y)

    case change do
      nil ->
        socket

      {prev, new} ->
        stroke = socket.assigns.active_stroke

        changes =
          Map.update(stroke.changes, {x, y}, {prev, new}, fn {old_prev, _old_new} ->
            {old_prev, new}
          end)

        assign(socket, :active_stroke, %{stroke | changes: changes})
    end
  end

  defp finalize_stroke(socket, stroke) do
    state = socket.assigns.state
    plane = socket.assigns.plane
    history = Map.get(state.history, plane, [])
    redo = Map.put(state.redo, plane, [])

    changes =
      stroke.changes
      |> Enum.map(fn {{x, y}, {prev, new}} -> {x, y, prev, new} end)

    history = [%{layer: stroke.layer, changes: changes} | history]

    state = %{state | history: Map.put(state.history, plane, history), redo: redo}
    SessionStore.put(socket.assigns.session_id, state)

    socket
    |> assign(:state, state)
    |> assign(:active_stroke, nil)
  end

  defp sample_tile(socket, layer, x, y) do
    state = socket.assigns.state
    plane = socket.assigns.plane

    case tile_value(state, plane, layer, x, y) do
      nil ->
        socket

      value ->
        selection = Map.put(state.selection, layer, value)
        state = %{state | selection: selection}
        SessionStore.put(socket.assigns.session_id, state)

        socket
        |> assign_from_state(state)
        |> assign_forms()
    end
  end

  defp apply_tile_change(socket, layer, x, y) do
    state = socket.assigns.state
    plane = socket.assigns.plane

    cond do
      layer == :computed_adj_mask ->
        {socket, nil}

      not valid_coord?(x, y) ->
        {socket, nil}

      true ->
        value = Map.get(state.selection, layer, 0)
        {updated_state, change, updates} = do_apply_change(state, plane, layer, x, y, value)

        socket =
          socket
          |> assign(:state, updated_state)
          |> maybe_push_updates(layer, updates)

        SessionStore.put(socket.assigns.session_id, updated_state)
        {socket, change}
    end
  end

  defp do_apply_change(state, plane, layer, x, y, value) do
    old_plane = Map.fetch!(state.planes, plane)

    {new_plane, prev_value} =
      if layer in @u16_layers do
        {updated, prev} = MirrorMap.put_tile_u16_le(old_plane[layer], x, y, value)
        {Map.put(old_plane, layer, updated), prev}
      else
        {updated, prev} = MirrorMap.put_tile_u8(old_plane[layer], x, y, value)
        {Map.put(old_plane, layer, updated), prev}
      end

    if prev_value == value do
      {state, nil, []}
    else
      new_plane = maybe_update_adj_mask(new_plane, x, y, layer)
      new_planes = Map.put(state.planes, plane, new_plane)
      save = %{state.save | planes: strip_computed(new_planes)}
      updated_state = %{state | planes: new_planes, save: save}

      update_stats(updated_state, plane, layer, x, y, prev_value, value, old_plane, new_plane)

      updates = [%{x: x, y: y, value: value}]
      {updated_state, {prev_value, value}, updates}
    end
  end

  defp apply_undo(socket) do
    state = socket.assigns.state
    plane = socket.assigns.plane
    history = Map.get(state.history, plane, [])

    case history do
      [stroke | rest] ->
        {state, updates, layer} = apply_stroke(state, plane, stroke, :undo)
        redo = [stroke | Map.get(state.redo, plane, [])]

        state = %{
          state
          | history: Map.put(state.history, plane, rest),
            redo: Map.put(state.redo, plane, redo)
        }

        SessionStore.put(socket.assigns.session_id, state)

        socket
        |> assign(:state, state)
        |> maybe_push_updates(layer, updates)

      [] ->
        socket
    end
  end

  defp apply_redo(socket) do
    state = socket.assigns.state
    plane = socket.assigns.plane
    redo = Map.get(state.redo, plane, [])

    case redo do
      [stroke | rest] ->
        {state, updates, layer} = apply_stroke(state, plane, stroke, :redo)
        history = [stroke | Map.get(state.history, plane, [])]

        state = %{
          state
          | history: Map.put(state.history, plane, history),
            redo: Map.put(state.redo, plane, rest)
        }

        SessionStore.put(socket.assigns.session_id, state)

        socket
        |> assign(:state, state)
        |> maybe_push_updates(layer, updates)

      [] ->
        socket
    end
  end

  defp apply_stroke(state, plane, stroke, mode) do
    layer = stroke.layer
    plane_layers = Map.fetch!(state.planes, plane)

    {updated_layer, updates} =
      Enum.reduce(stroke.changes, {plane_layers[layer], []}, fn {x, y, prev, new},
                                                                {acc, updates} ->
        value = if mode == :undo, do: prev, else: new

        {updated, _old} =
          if layer in @u16_layers do
            MirrorMap.put_tile_u16_le(acc, x, y, value)
          else
            MirrorMap.put_tile_u8(acc, x, y, value)
          end

        {updated, [%{x: x, y: y, value: value} | updates]}
      end)

    new_plane = Map.put(plane_layers, layer, updated_layer)
    new_plane = maybe_update_adj_mask_batch(new_plane, stroke, layer)
    new_planes = Map.put(state.planes, plane, new_plane)
    save = %{state.save | planes: strip_computed(new_planes)}

    {%{state | planes: new_planes, save: save}, updates, layer}
  end

  defp tile_value(state, plane, layer, x, y) do
    plane_layers = Map.fetch!(state.planes, plane)

    if valid_coord?(x, y) do
      if layer in @u16_layers do
        MirrorMap.get_tile_u16_le(plane_layers[layer], x, y)
      else
        MirrorMap.get_tile_u8(plane_layers[layer], x, y)
      end
    else
      nil
    end
  end

  defp update_stats(state, plane, layer, x, y, prev_value, new_value, old_plane, new_plane) do
    if state.dataset_id do
      case layer do
        :terrain ->
          update_adjacent_stats(state, old_plane, new_plane, x, y)
          update_ray_stats(state, new_plane, x, y)

        _ ->
          terrain_type =
            MirrorMap.terrain_type(MirrorMap.get_tile_u16_le(new_plane.terrain, x, y))

          Stats.bump_hist(state.dataset_id, layer, :global, prev_value, -1)
          Stats.bump_hist(state.dataset_id, layer, :global, new_value, 1)
          Stats.bump_hist(state.dataset_id, layer, {:plane, plane}, prev_value, -1)
          Stats.bump_hist(state.dataset_id, layer, {:plane, plane}, new_value, 1)
          Stats.bump_hist(state.dataset_id, layer, {:terrain_type, terrain_type}, prev_value, -1)
          Stats.bump_hist(state.dataset_id, layer, {:terrain_type, terrain_type}, new_value, 1)
      end
    end
  end

  defp update_adjacent_stats(state, old_plane, new_plane, x, y) do
    if state.dataset_id do
      coords = MirrorMap.adj_update_coords(x, y)

      Enum.each(coords, fn {cx, cy} ->
        old = MirrorMap.get_tile_u8(old_plane.computed_adj_mask, cx, cy)
        new = MirrorMap.get_tile_u8(new_plane.computed_adj_mask, cx, cy)

        if old != new do
          Stats.bump_hist(state.dataset_id, :computed_adj_mask, :global, old, -1)
          Stats.bump_hist(state.dataset_id, :computed_adj_mask, :global, new, 1)
        end
      end)
    end
  end

  defp update_ray_stats(state, plane_layers, x, y) do
    if state.dataset_id do
      for dy <- -2..2, dx <- -2..2 do
        nx = MirrorMap.wrap_x(x + dx)
        ny = MirrorMap.clamp_y(y + dy)

        if ny != :off do
          Mirror.Map.Rays.observe_tile(state.dataset_id, plane_layers.terrain, nx, ny)
        end
      end
    end
  end

  defp maybe_update_adj_mask(plane_layers, x, y, layer) do
    if layer == :terrain do
      coords = MirrorMap.adj_update_coords(x, y)

      updated =
        Enum.reduce(coords, plane_layers.computed_adj_mask, fn {cx, cy}, acc ->
          value = MirrorMap.adj_mask(plane_layers.terrain, cx, cy)
          {updated_bin, _old} = MirrorMap.put_tile_u8(acc, cx, cy, value)
          updated_bin
        end)

      Map.put(plane_layers, :computed_adj_mask, updated)
    else
      plane_layers
    end
  end

  defp maybe_update_adj_mask_batch(plane_layers, stroke, layer) do
    if layer == :terrain do
      coords =
        stroke
        |> Enum.flat_map(fn {x, y, _prev, _new} -> MirrorMap.adj_update_coords(x, y) end)
        |> Enum.uniq()

      updated =
        Enum.reduce(coords, plane_layers.computed_adj_mask, fn {cx, cy}, acc ->
          value = MirrorMap.adj_mask(plane_layers.terrain, cx, cy)
          {updated_bin, _old} = MirrorMap.put_tile_u8(acc, cx, cy, value)
          updated_bin
        end)

      Map.put(plane_layers, :computed_adj_mask, updated)
    else
      plane_layers
    end
  end

  defp strip_computed(planes) do
    Enum.into(planes, %{}, fn {plane_key, layers} ->
      {plane_key, Map.drop(layers, [:computed_adj_mask])}
    end)
  end

  defp assign_from_state(socket, state) do
    plane = socket.assigns.plane
    plane_layers = Map.get(state.planes, plane)

    encoded_layer =
      if plane_layers do
        Base.encode64(Map.fetch!(plane_layers, state.active_layer))
      else
        ""
      end

    terrain_encoded =
      if plane_layers do
        Base.encode64(plane_layers.terrain)
      else
        ""
      end

    terrain_flags_encoded =
      if plane_layers do
        Base.encode64(plane_layers.terrain_flags)
      else
        ""
      end

    minerals_encoded =
      if plane_layers do
        Base.encode64(plane_layers.minerals)
      else
        ""
      end

    assign(socket,
      state: state,
      plane_layers: plane_layers,
      encoded_layer: encoded_layer,
      terrain_encoded: terrain_encoded,
      terrain_flags_encoded: terrain_flags_encoded,
      minerals_encoded: minerals_encoded,
      active_layer: state.active_layer,
      selection_value: Map.get(state.selection, state.active_layer, 0),
      layers: @layers,
      layer_labels: @layer_labels,
      map_width: MirrorMap.width(),
      map_height: MirrorMap.height(),
      render_mode: state.render_mode
    )
  end

  defp assign_forms(socket) do
    state = socket.assigns.state

    load_form = to_form(%{"path" => socket.assigns.load_path || ""}, as: :load)

    save_form =
      to_form(%{"path" => socket.assigns.save_path_input || state.save_path || ""}, as: :save)

    selection_form =
      to_form(%{"value" => Map.get(state.selection, state.active_layer, 0)}, as: :selection)

    value_name_form =
      to_form(
        %{
          "value" => Map.get(state.selection, state.active_layer, 0),
          "name" => current_value_name(state)
        },
        as: :value_name
      )

    bit_forms =
      0..7
      |> Enum.into(%{}, fn bit ->
        form =
          to_form(%{"bit" => bit, "name" => current_bit_name(state, bit)},
            as: :bit_name
          )

        {bit, form}
      end)

    assign(socket,
      load_form: load_form,
      save_form: save_form,
      selection_form: selection_form,
      value_name_form: value_name_form,
      bit_forms: bit_forms
    )
  end

  defp current_value_name(%{dataset_id: nil}), do: ""

  defp current_value_name(state) do
    Stats.value_name(
      state.dataset_id,
      state.active_layer,
      Map.get(state.selection, state.active_layer, 0)
    ) || ""
  end

  defp current_bit_name(%{dataset_id: nil}, _bit), do: ""

  defp current_bit_name(state, bit) do
    Stats.bit_name(state.dataset_id, state.active_layer, bit) || ""
  end

  defp assign_hover(socket, x, y) do
    state = socket.assigns.state
    plane = socket.assigns.plane

    hover =
      if state.save && valid_coord?(x, y) do
        plane_layers = Map.fetch!(state.planes, plane)
        terrain_value = MirrorMap.get_tile_u16_le(plane_layers.terrain, x, y)
        adj = MirrorMap.get_tile_u8(plane_layers.computed_adj_mask, x, y)

        rays =
          Mirror.Map.Rays.ray_observations(plane_layers.terrain, x, y)
          |> Enum.map(fn {dir, hit, dist} -> %{dir: dir, hit: hit, dist: dist} end)

        %{
          x: x,
          y: y,
          terrain: terrain_value,
          terrain_class: MirrorMap.terrain_class(terrain_value),
          adj_mask: adj,
          rays: rays
        }
      else
        nil
      end

    assign(socket, :hover, hover)
  end

  defp push_map_state(socket) do
    state = socket.assigns.state

    push_event(socket, "map_state", %{
      layer: Atom.to_string(state.active_layer),
      layer_type: layer_type(state.active_layer),
      render_mode: Atom.to_string(state.render_mode)
    })
  end

  defp push_map_reload(socket) do
    state = socket.assigns.state
    plane = socket.assigns.plane
    plane_layers = Map.fetch!(state.planes, plane)
    layer = state.active_layer
    values = Base.encode64(Map.fetch!(plane_layers, layer))

    push_event(socket, "map_reload", %{
      plane: Atom.to_string(plane),
      layer: Atom.to_string(layer),
      layer_type: layer_type(layer),
      values: values,
      terrain: Base.encode64(plane_layers.terrain),
      terrain_flags: Base.encode64(plane_layers.terrain_flags),
      minerals: Base.encode64(plane_layers.minerals),
      render_mode: Atom.to_string(state.render_mode)
    })
  end

  defp maybe_push_updates(socket, layer, updates) do
    if connected?(socket) and layer == socket.assigns.active_layer and updates != [] do
      push_event(socket, "tile_updates", %{
        layer: Atom.to_string(layer),
        layer_type: layer_type(layer),
        updates: updates
      })
    end

    socket
  end

  defp maybe_push_tile_assets(socket) do
    state = socket.assigns.state

    if connected?(socket) and state.render_mode == :tiles do
      socket =
        case socket.assigns.tile_assets do
          nil -> assign(socket, :tile_assets, TileAtlas.build())
          _ -> socket
        end

      atlas = socket.assigns.tile_assets
      terrain_names = terrain_name_map(state)

      push_event(socket, "tile_assets", %{
        images: atlas.images,
        terrain_groups: atlas.terrain_groups,
        overlay_groups: atlas.overlay_groups,
        terrain_names: terrain_names
      })
    else
      socket
    end
  end

  defp terrain_name_map(%{dataset_id: nil}), do: %{}

  defp terrain_name_map(state) do
    0..255
    |> Enum.reduce(%{}, fn value, acc ->
      case Stats.value_name(state.dataset_id, :terrain, value) do
        nil -> acc
        name -> Map.put(acc, Integer.to_string(value), name)
      end
    end)
  end

  defp layer_type(layer) do
    if layer in @u16_layers, do: "u16", else: "u8"
  end

  defp tool_and_layer(socket, button, mods) do
    layer = socket.assigns.state.active_layer

    tool =
      cond do
        button == 2 -> :sample
        truthy?(mods["ctrl"]) -> :sample
        true -> :paint
      end

    {tool, layer}
  end

  defp valid_coord?(x, y) do
    x in 0..(MirrorMap.width() - 1) and y in 0..(MirrorMap.height() - 1)
  end

  defp clamp_value(layer, value) do
    if layer in @u16_layers do
      value |> max(0) |> min(65_535)
    else
      value |> max(0) |> min(255)
    end
  end

  defp parse_int(nil, fallback), do: fallback
  defp parse_int(value, _fallback) when is_integer(value), do: value

  defp parse_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> fallback
    end
  end

  defp truthy?(value) do
    value in [true, "true", "1", 1, "on"]
  end

  defp normalize_state(nil) do
    %{
      save: nil,
      planes: %{},
      active_layer: :terrain,
      selection: default_selection(),
      history: %{arcanus: [], myrror: []},
      redo: %{arcanus: [], myrror: []},
      save_path: nil,
      dataset_id: nil,
      render_mode: :tiles
    }
  end

  defp normalize_state(state) do
    state
    |> Map.put_new(:selection, default_selection())
    |> Map.put_new(:history, %{arcanus: [], myrror: []})
    |> Map.put_new(:redo, %{arcanus: [], myrror: []})
    |> Map.put_new(:render_mode, :tiles)
  end

  defp default_load_path do
    case Paths.mom_path() do
      nil -> ""
      "" -> ""
      path -> path |> Path.join("SAVE1.GAM") |> String.replace("/", "\\")
    end
  end

  defp default_selection do
    Enum.into(@layers, %{}, fn layer -> {layer, 0} end)
  end

  defp observe_stats(%{dataset_id: nil}), do: :ok

  defp observe_stats(state) do
    Stats.ensure_dataset(state.dataset_id)

    u8_layers = @layers -- @u16_layers
    global_init = Enum.into(u8_layers, %{}, fn layer -> {layer, empty_hist()} end)

    {global, _} =
      Enum.reduce(state.planes, {global_init, :ok}, fn {plane, layers}, {global_acc, _} ->
        global_acc =
          Enum.reduce(u8_layers, global_acc, fn layer, acc ->
            hist = histogram_from_binary(Map.fetch!(layers, layer))
            Stats.set_histogram(state.dataset_id, layer, {:plane, plane}, hist)
            Map.update!(acc, layer, &sum_hist(&1, hist))
          end)

        Mirror.Map.Rays.observe_plane(state.dataset_id, layers.terrain)
        {global_acc, :ok}
      end)

    Enum.each(global, fn {layer, hist} ->
      Stats.set_histogram(state.dataset_id, layer, :global, hist)
    end)
  end

  defp histogram_from_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.reduce(List.duplicate(0, 256), fn value, acc ->
      List.update_at(acc, value, &(&1 + 1))
    end)
  end

  defp empty_hist do
    List.duplicate(0, 256)
  end

  defp sum_hist(left, right) do
    Enum.zip_with(left, right, fn a, b -> a + b end)
  end

  defp hist_entries(%{dataset_id: nil}, _layer), do: []
  defp hist_entries(_state, layer) when layer in @u16_layers, do: []

  defp hist_entries(state, layer) do
    hist = Stats.histogram(state.dataset_id, layer, :global)

    hist
    |> Enum.with_index()
    |> Enum.map(fn {count, value} ->
      %{
        value: value,
        count: count,
        name: Stats.value_name(state.dataset_id, layer, value)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(10)
  end

  defp encode_dataset({:mom_classic, fingerprint}), do: "mom-classic-#{fingerprint}"
  defp encode_dataset(other), do: Base.url_encode64(:erlang.term_to_binary(other), padding: false)
end
