defmodule MirrorWeb.MapLive do
  use MirrorWeb, :live_view
  import Bitwise

  alias Mirror.Engine.{Delta, Session, SessionSupervisor, View}
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
  @u8_layers @layers -- @u16_layers -- [:computed_adj_mask]

  @layer_labels %{
    terrain: "Terrain (u16)",
    terrain_flags: "Terrain Flags",
    minerals: "Minerals",
    exploration: "Exploration",
    landmass: "Landmass",
    computed_adj_mask: "Adjacency Mask"
  }

  @phase_loop_max 32
  @phase_loop_fallback 8
  @phase_loop_threshold 0

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

    state = ensure_engine_session(state, session_id, connected?(socket))

    socket =
      socket
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
          original_planes: save.planes,
          active_layer: :terrain,
          selection: default_selection(),
          history: %{arcanus: [], myrror: []},
          redo: %{arcanus: [], myrror: []},
          save_path: save.path,
          dataset_id: save.dataset_id,
          render_mode: socket.assigns.state.render_mode || :tiles,
          phase_index: socket.assigns.state.phase_index || 0,
          snapshot_mode: Map.get(socket.assigns.state, :snapshot_mode, true),
          snapshot_values: %{},
          phase_loop_len: Map.get(socket.assigns.state, :phase_loop_len),
          phase_loop_status:
            normalize_phase_loop_status(
              Map.get(socket.assigns.state, :phase_loop_status, :unknown)
            ),
          phase_loop_detecting: false,
          engine_session_id: nil,
          engine_player_id: Map.get(socket.assigns.state, :engine_player_id, :observer)
        }

        state =
          case start_engine_session(path) do
            {:ok, engine_session_id} -> %{state | engine_session_id: engine_session_id}
            {:error, _reason} -> state
          end

        state = normalize_state(state)

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
    state = state |> Map.put(:active_layer, layer) |> ensure_layer_visible(layer)

    SessionStore.put(socket.assigns.session_id, state)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()
      |> refresh_hover()

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

  def handle_event("set_layer_setting", %{"layer" => layer} = params, socket) do
    state = socket.assigns.state
    layer = Enum.find(@layers, state.active_layer, &(&1 |> Atom.to_string() == layer))
    settings = Map.get(params, "layer_#{layer}") || %{}

    current_visible =
      Map.get(Map.get(state, :layer_visibility, %{}), layer, layer == :terrain)

    visible_value = Map.get(settings, "visible", current_visible)

    visibility =
      Map.get(state, :layer_visibility, %{})
      |> Map.put_new(:terrain, true)
      |> Map.put(layer, truthy?(visible_value))

    current_opacity =
      Map.get(
        Map.get(state, :layer_opacity, %{}),
        layer,
        if(layer == :terrain, do: 100, else: 70)
      )

    opacity_value = Map.get(settings, "opacity", current_opacity)

    opacity =
      Map.get(state, :layer_opacity, %{})
      |> Map.put_new(:terrain, 100)
      |> Map.put(layer, parse_opacity(opacity_value))

    state =
      if layer == :terrain do
        state
        |> Map.put(:layer_visibility, Map.put(visibility, :terrain, true))
        |> Map.put(:layer_opacity, opacity)
      else
        state
        |> Map.put(:layer_visibility, visibility)
        |> Map.put(:layer_opacity, opacity)
      end

    SessionStore.put(socket.assigns.session_id, state)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()
      |> refresh_hover()

    socket =
      if connected?(socket) do
        push_map_state(socket)
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

  def handle_event("inspect_toggle_bit", %{"bit" => bit}, socket) do
    bit = parse_int(bit, 0)
    {:noreply, update_inspected_tile(socket, fn value -> bxor(value, 1 <<< bit) end)}
  end

  def handle_event("inspect_set_value", %{"value" => value}, socket) do
    value = parse_int(value, 0)
    {:noreply, update_inspected_tile(socket, fn _value -> value end)}
  end

  def handle_event("inspect_invert", _params, socket) do
    {:noreply, update_inspected_tile(socket, fn value -> bxor(value, 0xFF) end)}
  end

  def handle_event("inspect_revert", _params, socket) do
    {:noreply, revert_inspected_tile(socket)}
  end

  def handle_event("inspect_snapshot_a", _params, socket) do
    {:noreply, snapshot_inspected_value(socket)}
  end

  def handle_event("inspect_restore_a", _params, socket) do
    {:noreply, restore_inspected_snapshot(socket)}
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

  def handle_event("export_snapshot", _params, socket) do
    state = socket.assigns.state
    plane = socket.assigns.plane

    if state.save do
      phase_input = state.phase_index || 0
      effective_phase = effective_phase_index(state)

      socket =
        socket
        |> push_tile_assets(state)
        |> push_event("snapshot_export", %{
          filename: "mirror-snapshot-#{plane}-phase-#{effective_phase}.png",
          phase_index: effective_phase,
          phase_input: phase_input,
          effective_phase: effective_phase,
          loop_len: phase_loop_len(state)
        })

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Load a save to export snapshots.")}
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

  def handle_event("toggle_snapshot_mode", _params, socket) do
    state = socket.assigns.state
    snapshot_mode = not Map.get(state, :snapshot_mode, true)
    state = %{state | snapshot_mode: snapshot_mode}
    SessionStore.put(socket.assigns.session_id, state)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()

    socket =
      if connected?(socket) do
        push_map_state(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("detect_phase_loop", _params, socket) do
    state = socket.assigns.state

    cond do
      not state.save ->
        {:noreply, put_flash(socket, :error, "Load a save to detect the phase loop.")}

      state.render_mode != :tiles ->
        {:noreply, put_flash(socket, :error, "Switch to Tiles render mode to detect phases.")}

      true ->
        state = %{state | phase_loop_detecting: true}
        SessionStore.put(socket.assigns.session_id, state)

        socket =
          socket
          |> assign_from_state(state)
          |> assign_forms()

        socket =
          if connected?(socket) do
            socket
            |> push_tile_assets(state)
            |> push_event("phase_loop_detect", %{
              max_phases: @phase_loop_max,
              threshold: @phase_loop_threshold,
              fallback: @phase_loop_fallback
            })
          else
            socket
          end

        {:noreply, socket}
    end
  end

  def handle_event("phase_loop_detected", params, socket) do
    state = socket.assigns.state
    status = Map.get(params, "status", "unknown")

    {next_state, socket} =
      case status do
        "detected" ->
          loop_len =
            params
            |> Map.get("loop_len")
            |> parse_int(state.phase_loop_len || @phase_loop_fallback)
            |> max(1)

          state = %{
            state
            | phase_loop_len: loop_len,
              phase_loop_status: :detected,
              phase_loop_detecting: false
          }

          {state, put_flash(socket, :info, "Detected phase loop length: #{loop_len}.")}

        "assumed" ->
          loop_len =
            params
            |> Map.get("loop_len")
            |> parse_int(@phase_loop_fallback)
            |> max(1)

          state = %{
            state
            | phase_loop_len: loop_len,
              phase_loop_status: :assumed,
              phase_loop_detecting: false
          }

          {state, put_flash(socket, :info, "No loop found. Using #{loop_len} as a fallback.")}

        _ ->
          state = %{state | phase_loop_detecting: false, phase_loop_status: :unknown}
          {state, put_flash(socket, :error, "Phase loop detection failed.")}
      end

    SessionStore.put(socket.assigns.session_id, next_state)

    socket =
      socket
      |> assign_from_state(next_state)
      |> assign_forms()

    socket =
      if connected?(socket) do
        push_map_state(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("set_phase_index", %{"phase" => %{"index" => index}}, socket) do
    state = socket.assigns.state
    phase_index = index |> parse_int(state.phase_index || 0) |> max(0)
    state = %{state | phase_index: phase_index}
    SessionStore.put(socket.assigns.session_id, state)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()

    socket =
      if connected?(socket) do
        push_map_state(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("reload_tiles", _params, socket) do
    socket =
      if connected?(socket) do
        Mirror.MomimePngIndex.reset()

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
                    id="snapshot-mode-button"
                    type="button"
                    phx-click="toggle_snapshot_mode"
                    class="rounded-full border border-sky-300/40 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-sky-100 transition hover:border-sky-200"
                  >
                    Snapshot: {if @snapshot_mode, do: "On", else: "Off"}
                  </button>
                  <div class="flex flex-col gap-1">
                    <.form
                      for={@phase_form}
                      id="phase-form"
                      phx-change="set_phase_index"
                      class="rounded-full border border-white/20 px-4 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-slate-200"
                    >
                      <.input
                        field={@phase_form[:index]}
                        type="number"
                        label="Phase"
                        class="w-20 rounded-2xl border border-white/10 bg-slate-950/70 text-slate-200"
                      />
                    </.form>
                    <div class="flex flex-wrap items-center gap-2 text-[0.65rem] uppercase tracking-[0.2em] text-slate-400">
                      <span>Input: {@phase_input}</span>
                      <span>Effective: {@phase_index}</span>
                      <span>
                        Loop: {if(@phase_loop_len, do: @phase_loop_len, else: "Unknown")}
                      </span>
                      <%= case @phase_loop_status do %>
                        <% :detected -> %>
                          <span class="text-emerald-300/80">Detected</span>
                        <% :assumed -> %>
                          <span class="text-amber-300/80">Assumed</span>
                        <% _ -> %>
                          <span class="text-slate-500">Unknown</span>
                      <% end %>
                    </div>
                  </div>
                  <button
                    :if={@render_mode == :tiles}
                    id="detect-phase-loop-button"
                    type="button"
                    phx-click="detect_phase_loop"
                    disabled={@phase_loop_detecting}
                    class={[
                      "rounded-full border border-fuchsia-300/40 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-fuchsia-100 transition hover:border-fuchsia-200",
                      @phase_loop_detecting && "cursor-not-allowed opacity-60"
                    ]}
                  >
                    {if @phase_loop_detecting, do: "Detecting...", else: "Detect loop"}
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
                    id="export-snapshot-button"
                    type="button"
                    phx-click="export_snapshot"
                    class="rounded-full border border-indigo-300/40 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-indigo-100 transition hover:border-indigo-200"
                  >
                    Export snapshot
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
                        <div class="space-y-3">
                          <%= for layer <- @layers do %>
                            <div
                              id={"layer-row-#{layer}"}
                              class={[
                                "rounded-2xl border p-3",
                                layer == @active_layer && "border-amber-300/40 bg-amber-300/10",
                                layer != @active_layer && "border-white/10 bg-slate-950/40"
                              ]}
                            >
                              <div class="flex items-center justify-between gap-3">
                                <button
                                  id={"layer-#{layer}"}
                                  type="button"
                                  phx-click="set_active_layer"
                                  phx-value-layer={Atom.to_string(layer)}
                                  class={[
                                    "text-left text-sm transition",
                                    layer == @active_layer && "text-white",
                                    layer != @active_layer && "text-slate-300 hover:text-white"
                                  ]}
                                >
                                  <span class="font-semibold">{@layer_labels[layer]}</span>
                                  <%= if layer == :computed_adj_mask do %>
                                    <span class="ml-2 text-[0.65rem] uppercase tracking-[0.2em] text-slate-500">
                                      Derived
                                    </span>
                                  <% end %>
                                </button>
                                <span class="text-xs text-slate-400">
                                  {Map.get(@layer_opacity, layer, 100)}%
                                </span>
                              </div>

                              <.form
                                for={@layer_forms[layer]}
                                id={"layer-form-#{layer}"}
                                phx-change="set_layer_setting"
                                phx-value-layer={Atom.to_string(layer)}
                                class="mt-3 grid gap-2"
                              >
                                <.input
                                  field={@layer_forms[layer][:visible]}
                                  type="checkbox"
                                  label={
                                    if(layer == :terrain, do: "Base (always on)", else: "Show layer")
                                  }
                                  disabled={layer == :terrain}
                                  class="h-4 w-4 rounded border border-white/20 bg-slate-950 text-amber-300 focus:ring-2 focus:ring-amber-300/40"
                                />
                                <.input
                                  field={@layer_forms[layer][:opacity]}
                                  type="range"
                                  label="Opacity"
                                  min="0"
                                  max="100"
                                  step="5"
                                  phx-debounce="100"
                                  class="h-2 w-full cursor-pointer appearance-none rounded-full bg-white/10 accent-amber-300"
                                />
                              </.form>
                            </div>
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

              <div class="relative overflow-auto bg-slate-950">
                <canvas
                  id="map-canvas"
                  phx-hook="MapCanvas"
                  phx-update="ignore"
                  data-map-width={@map_width}
                  data-map-height={@map_height}
                  data-plane={Atom.to_string(@plane)}
                  data-layer={Atom.to_string(@active_layer)}
                  data-layer-type={layer_type(@active_layer)}
                  data-tiles={@encoded_layer}
                  data-terrain={@terrain_encoded}
                  data-terrain-flags={@terrain_flags_encoded}
                  data-minerals={@minerals_encoded}
                  data-exploration={@exploration_encoded}
                  data-landmass={@landmass_encoded}
                  data-computed-adj-mask={@adj_mask_encoded}
                  data-render-mode={Atom.to_string(@render_mode)}
                  data-phase-index={@phase_index}
                  data-snapshot-mode={@snapshot_mode}
                  data-tile-size="32"
                  class="block"
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
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Tile inspector</p>
                  <h3 class="mt-2 text-lg font-semibold text-white">Bit flag lab</h3>
                  <div class="mt-4 space-y-4 text-sm text-slate-300">
                    <%= if @state.save && @hover do %>
                      <% value = @hover.layer_value || 0 %>
                      <% original_value = @hover.original_value %>
                      <% snapshot_value = snapshot_value(@state, @plane, @active_layer) %>
                      <% unsupported_layer = not u8_layer?(@active_layer) %>
                      <div class="rounded-2xl border border-white/10 bg-slate-950/50 p-4">
                        <div class="flex flex-wrap items-center justify-between gap-3 text-[0.65rem] uppercase tracking-[0.2em] text-slate-500">
                          <span>Tile ({@hover.x}, {@hover.y})</span>
                          <span>{@layer_labels[@active_layer]}</span>
                        </div>
                        <div class="mt-3 flex flex-wrap items-end justify-between gap-4">
                          <div>
                            <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Current</p>
                            <div class="flex items-baseline gap-3">
                              <span class="text-3xl font-semibold text-white">{value}</span>
                              <span class="text-sm font-semibold text-slate-400">
                                {hex_byte(value)}
                              </span>
                            </div>
                          </div>
                          <div class="text-xs text-slate-500">
                            <%= if is_integer(original_value) do %>
                              <p class="uppercase tracking-[0.2em] text-slate-500">Original</p>
                              <p class="text-sm text-slate-300">
                                {original_value} ({hex_byte(original_value)})
                              </p>
                            <% else %>
                              <p class="text-slate-600">Original value unavailable</p>
                            <% end %>
                          </div>
                        </div>
                      </div>

                      <%= if unsupported_layer do %>
                        <p class="text-xs text-slate-500">
                          Bit toggles only apply to u8 layers. Switch to Terrain Flags, Minerals,
                          Exploration, or Landmass.
                        </p>
                      <% else %>
                        <div class="grid gap-2 sm:grid-cols-2">
                          <%= for bit <- 0..7 do %>
                            <% bit_on = bit_set?(value, bit) %>
                            <% bit_name = Map.get(@bit_names, bit) %>
                            <button
                              id={"inspect-bit-#{bit}"}
                              type="button"
                              phx-click="inspect_toggle_bit"
                              phx-value-bit={bit}
                              class={[
                                "group flex items-center justify-between rounded-xl border px-3 py-2 text-xs transition",
                                bit_on &&
                                  "border-emerald-300/50 bg-emerald-300/10 text-emerald-100",
                                not bit_on &&
                                  "border-white/10 text-slate-300 hover:border-white/30"
                              ]}
                              aria-pressed={bit_on}
                            >
                              <div class="flex items-center gap-3">
                                <span class={[
                                  "inline-flex h-6 w-6 items-center justify-center rounded-lg border text-[0.65rem] font-semibold",
                                  bit_on &&
                                    "border-emerald-300/60 bg-emerald-300/20 text-emerald-100",
                                  not bit_on && "border-white/10 text-slate-400"
                                ]}>
                                  {if bit_on, do: "1", else: "0"}
                                </span>
                                <div>
                                  <p class="text-[0.65rem] uppercase tracking-[0.2em] text-slate-400">
                                    Bit {bit}
                                  </p>
                                  <p class="text-xs text-slate-500">
                                    {if bit_name in [nil, ""], do: "Unlabeled", else: bit_name}
                                  </p>
                                </div>
                              </div>
                              <span class="text-[0.6rem] uppercase tracking-[0.2em] text-slate-500">
                                Toggle
                              </span>
                            </button>
                          <% end %>
                        </div>

                        <div class="grid gap-2 sm:grid-cols-2">
                          <button
                            id="inspect-set-zero"
                            type="button"
                            phx-click="inspect_set_value"
                            phx-value-value="0"
                            class="rounded-xl border border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-200 transition hover:border-white/30"
                          >
                            Set 0
                          </button>
                          <button
                            id="inspect-set-255"
                            type="button"
                            phx-click="inspect_set_value"
                            phx-value-value="255"
                            class="rounded-xl border border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-200 transition hover:border-white/30"
                          >
                            Set 255
                          </button>
                          <button
                            id="inspect-invert"
                            type="button"
                            phx-click="inspect_invert"
                            class="rounded-xl border border-white/10 px-3 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-200 transition hover:border-white/30"
                          >
                            Invert
                          </button>
                          <button
                            id="inspect-revert"
                            type="button"
                            phx-click="inspect_revert"
                            disabled={is_nil(original_value)}
                            class={[
                              "rounded-xl border px-3 py-2 text-xs font-semibold uppercase tracking-[0.2em] transition",
                              is_nil(original_value) &&
                                "cursor-not-allowed border-white/5 text-slate-600",
                              not is_nil(original_value) &&
                                "border-white/10 text-slate-200 hover:border-white/30"
                            ]}
                          >
                            Revert tile
                          </button>
                        </div>

                        <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-3">
                          <div class="grid gap-2 sm:grid-cols-2">
                            <button
                              id="inspect-snapshot-a"
                              type="button"
                              phx-click="inspect_snapshot_a"
                              class="rounded-xl border border-white/10 px-3 py-2 text-[0.65rem] font-semibold uppercase tracking-[0.2em] text-slate-200 transition hover:border-white/30"
                            >
                              Snapshot A
                            </button>
                            <button
                              id="inspect-restore-a"
                              type="button"
                              phx-click="inspect_restore_a"
                              disabled={is_nil(snapshot_value)}
                              class={[
                                "rounded-xl border px-3 py-2 text-[0.65rem] font-semibold uppercase tracking-[0.2em] transition",
                                is_nil(snapshot_value) &&
                                  "cursor-not-allowed border-white/5 text-slate-600",
                                not is_nil(snapshot_value) &&
                                  "border-white/10 text-slate-200 hover:border-white/30"
                              ]}
                            >
                              Restore A
                            </button>
                          </div>
                          <%= if is_integer(snapshot_value) do %>
                            <p class="mt-2 text-[0.65rem] uppercase tracking-[0.2em] text-slate-500">
                              A: {snapshot_value} ({hex_byte(snapshot_value)})
                            </p>
                          <% else %>
                            <p class="mt-2 text-[0.65rem] uppercase tracking-[0.2em] text-slate-600">
                              A: Empty
                            </p>
                          <% end %>
                        </div>
                      <% end %>
                    <% else %>
                      <%= if @state.save do %>
                        <p class="text-slate-500">Hover a tile to inspect bit flags.</p>
                      <% else %>
                        <p class="text-slate-500">Load a save to inspect tile flags.</p>
                      <% end %>
                    <% end %>
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
        changes = change && [{x, y, elem(change, 0), elem(change, 1)}]

        socket =
          socket
          |> assign(:state, updated_state)
          |> maybe_push_updates(layer, updates, changes)

        socket =
          if changes do
            emit_engine_delta(socket, plane, layer, changes)
          else
            socket
          end

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
        changes = stroke_changes(stroke, :undo)
        redo = [stroke | Map.get(state.redo, plane, [])]

        state = %{
          state
          | history: Map.put(state.history, plane, rest),
            redo: Map.put(state.redo, plane, redo)
        }

        SessionStore.put(socket.assigns.session_id, state)

        socket
        |> assign(:state, state)
        |> maybe_push_updates(layer, updates, changes)
        |> emit_engine_delta(plane, layer, changes)

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
        changes = stroke_changes(stroke, :redo)
        history = [stroke | Map.get(state.history, plane, [])]

        state = %{
          state
          | history: Map.put(state.history, plane, history),
            redo: Map.put(state.redo, plane, rest)
        }

        SessionStore.put(socket.assigns.session_id, state)

        socket
        |> assign(:state, state)
        |> maybe_push_updates(layer, updates, changes)
        |> emit_engine_delta(plane, layer, changes)

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

  defp phase_loop_len(%{phase_loop_len: len}) when is_integer(len) and len > 0, do: len
  defp phase_loop_len(_), do: nil

  defp effective_phase_index(state) do
    phase_input = state.phase_index || 0

    case phase_loop_len(state) do
      nil -> phase_input
      len -> rem(phase_input, len)
    end
  end

  defp normalize_phase_loop_status(status) do
    case status do
      :detected -> :detected
      "detected" -> :detected
      :assumed -> :assumed
      "assumed" -> :assumed
      _ -> :unknown
    end
  end

  defp assign_from_state(socket, state) do
    plane = socket.assigns.plane
    plane_layers = Map.get(state.planes, plane)
    phase_input = state.phase_index || 0
    loop_len = phase_loop_len(state)
    effective_phase = effective_phase_index(state)
    phase_loop_status = normalize_phase_loop_status(Map.get(state, :phase_loop_status))

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

    exploration_encoded =
      if plane_layers do
        Base.encode64(plane_layers.exploration)
      else
        ""
      end

    landmass_encoded =
      if plane_layers do
        Base.encode64(plane_layers.landmass)
      else
        ""
      end

    adj_mask_encoded =
      if plane_layers do
        Base.encode64(plane_layers.computed_adj_mask)
      else
        ""
      end

    layer_visibility =
      Map.get(state, :layer_visibility, default_layer_visibility(state.active_layer))

    layer_opacity = Map.get(state, :layer_opacity, default_layer_opacity())

    assign(socket,
      state: state,
      plane_layers: plane_layers,
      encoded_layer: encoded_layer,
      terrain_encoded: terrain_encoded,
      terrain_flags_encoded: terrain_flags_encoded,
      minerals_encoded: minerals_encoded,
      exploration_encoded: exploration_encoded,
      landmass_encoded: landmass_encoded,
      adj_mask_encoded: adj_mask_encoded,
      active_layer: state.active_layer,
      selection_value: Map.get(state.selection, state.active_layer, 0),
      layers: @layers,
      layer_labels: @layer_labels,
      layer_visibility: layer_visibility,
      layer_opacity: layer_opacity,
      map_width: MirrorMap.width(),
      map_height: MirrorMap.height(),
      render_mode: state.render_mode,
      phase_index: effective_phase,
      phase_input: phase_input,
      phase_loop_len: loop_len,
      phase_loop_status: phase_loop_status,
      phase_loop_detecting: Map.get(state, :phase_loop_detecting, false),
      snapshot_mode: Map.get(state, :snapshot_mode, true),
      engine_session_id: Map.get(state, :engine_session_id)
    )
  end

  defp assign_forms(socket) do
    state = socket.assigns.state

    load_form = to_form(%{"path" => socket.assigns.load_path || ""}, as: :load)

    save_form =
      to_form(%{"path" => socket.assigns.save_path_input || state.save_path || ""}, as: :save)

    selection_form =
      to_form(%{"value" => Map.get(state.selection, state.active_layer, 0)}, as: :selection)

    phase_form = to_form(%{"index" => state.phase_index || 0}, as: :phase)

    layer_forms = layer_forms(state)

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
      phase_form: phase_form,
      layer_forms: layer_forms,
      value_name_form: value_name_form,
      bit_forms: bit_forms,
      bit_names: Enum.into(0..7, %{}, fn bit -> {bit, current_bit_name(state, bit)} end)
    )
  end

  defp layer_forms(state) do
    visibility = Map.get(state, :layer_visibility, %{})
    opacity = Map.get(state, :layer_opacity, %{})

    Enum.into(@layers, %{}, fn layer ->
      visible_value = Map.get(visibility, layer, layer == :terrain)
      opacity_value = Map.get(opacity, layer, if(layer == :terrain, do: 100, else: 70))

      form =
        to_form(
          %{"visible" => visible_value, "opacity" => opacity_value},
          as: "layer_#{layer}"
        )

      {layer, form}
    end)
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
        engine_tile = engine_tile(state, plane, x, y)
        engine_terrain = engine_tile && Map.get(engine_tile, :terrain_u16)
        terrain_value = engine_terrain || MirrorMap.get_tile_u16_le(plane_layers.terrain, x, y)
        adj = MirrorMap.get_tile_u8(plane_layers.computed_adj_mask, x, y)
        layer = state.active_layer

        engine_layer_value =
          case engine_tile do
            nil -> nil
            _ -> engine_layer(layer) && Map.get(engine_tile, engine_layer(layer))
          end

        layer_value =
          cond do
            layer == :computed_adj_mask ->
              MirrorMap.get_tile_u8(plane_layers.computed_adj_mask, x, y)

            not is_nil(engine_layer_value) ->
              engine_layer_value

            layer in @u16_layers ->
              MirrorMap.get_tile_u16_le(plane_layers[layer], x, y)

            true ->
              MirrorMap.get_tile_u8(plane_layers[layer], x, y)
          end

        rays =
          Mirror.Map.Rays.ray_observations(plane_layers.terrain, x, y)
          |> Enum.map(fn {dir, hit, dist} -> %{dir: dir, hit: hit, dist: dist} end)

        %{
          x: x,
          y: y,
          terrain: terrain_value,
          terrain_class: MirrorMap.terrain_class(terrain_value),
          layer_value: layer_value,
          original_value: original_tile_value(state, plane, layer, x, y),
          adj_mask: adj,
          rays: rays,
          engine_tile: engine_tile
        }
      else
        nil
      end

    assign(socket, :hover, hover)
  end

  defp refresh_hover(socket) do
    case socket.assigns.hover do
      %{x: x, y: y} -> assign_hover(socket, x, y)
      _ -> socket
    end
  end

  defp update_inspected_tile(socket, updater) do
    state = socket.assigns.state
    layer = state.active_layer
    plane = socket.assigns.plane

    with true <- state.save != nil,
         true <- u8_layer?(layer),
         %{x: x, y: y} <- socket.assigns.hover,
         true <- valid_coord?(x, y),
         value when is_integer(value) <- tile_value(state, plane, layer, x, y) do
      updated_value = updater.(value)
      apply_single_tile_change(socket, layer, x, y, clamp_value(layer, updated_value))
    else
      _ -> socket
    end
  end

  defp revert_inspected_tile(socket) do
    state = socket.assigns.state
    layer = state.active_layer
    plane = socket.assigns.plane

    with true <- state.save != nil,
         true <- u8_layer?(layer),
         %{x: x, y: y} <- socket.assigns.hover,
         true <- valid_coord?(x, y),
         value when is_integer(value) <- original_tile_value(state, plane, layer, x, y) do
      apply_single_tile_change(socket, layer, x, y, clamp_value(layer, value))
    else
      _ -> socket
    end
  end

  defp snapshot_inspected_value(socket) do
    state = socket.assigns.state
    layer = state.active_layer
    plane = socket.assigns.plane

    with true <- state.save != nil,
         true <- u8_layer?(layer),
         %{x: x, y: y} <- socket.assigns.hover,
         true <- valid_coord?(x, y),
         value when is_integer(value) <- tile_value(state, plane, layer, x, y) do
      snapshot_values =
        state.snapshot_values
        |> Map.put({plane, layer}, value)

      updated_state = %{state | snapshot_values: snapshot_values}
      SessionStore.put(socket.assigns.session_id, updated_state)
      assign(socket, :state, updated_state)
    else
      _ -> socket
    end
  end

  defp restore_inspected_snapshot(socket) do
    state = socket.assigns.state
    layer = state.active_layer
    plane = socket.assigns.plane

    with true <- state.save != nil,
         true <- u8_layer?(layer),
         %{x: x, y: y} <- socket.assigns.hover,
         true <- valid_coord?(x, y),
         value when is_integer(value) <- snapshot_value(state, plane, layer) do
      apply_single_tile_change(socket, layer, x, y, clamp_value(layer, value))
    else
      _ -> socket
    end
  end

  defp snapshot_value(state, plane, layer) do
    state.snapshot_values
    |> Map.get({plane, layer})
  end

  defp apply_single_tile_change(socket, layer, x, y, value) do
    state = socket.assigns.state
    plane = socket.assigns.plane

    {updated_state, change, updates} = do_apply_change(state, plane, layer, x, y, value)

    case change do
      nil ->
        socket

      {prev, new} ->
        stroke = %{layer: layer, changes: [{x, y, prev, new}]}
        history = [stroke | Map.get(updated_state.history, plane, [])]
        redo = Map.put(updated_state.redo, plane, [])

        updated_state = %{
          updated_state
          | history: Map.put(updated_state.history, plane, history),
            redo: redo
        }

        SessionStore.put(socket.assigns.session_id, updated_state)

        socket
        |> assign(:state, updated_state)
        |> maybe_push_updates(layer, updates, stroke.changes)
        |> emit_engine_delta(plane, layer, stroke.changes)
        |> assign_hover(x, y)
    end
  end

  defp push_map_state(socket) do
    state = socket.assigns.state

    layer_visibility =
      Map.get(state, :layer_visibility, default_layer_visibility(state.active_layer))

    layer_opacity = Map.get(state, :layer_opacity, default_layer_opacity())

    push_event(socket, "map_state", %{
      layer: Atom.to_string(state.active_layer),
      layer_type: layer_type(state.active_layer),
      render_mode: Atom.to_string(state.render_mode),
      phase_index: effective_phase_index(state),
      snapshot_mode: Map.get(state, :snapshot_mode, true),
      layer_visibility: stringify_layer_map(layer_visibility),
      layer_opacity: stringify_layer_map(layer_opacity)
    })
  end

  defp push_map_reload(socket) do
    state = socket.assigns.state
    plane = socket.assigns.plane
    plane_layers = Map.fetch!(state.planes, plane)
    layer = state.active_layer
    values = Base.encode64(Map.fetch!(plane_layers, layer))

    layer_visibility =
      Map.get(state, :layer_visibility, default_layer_visibility(state.active_layer))

    layer_opacity = Map.get(state, :layer_opacity, default_layer_opacity())

    push_event(socket, "map_reload", %{
      plane: Atom.to_string(plane),
      layer: Atom.to_string(layer),
      layer_type: layer_type(layer),
      values: values,
      terrain: Base.encode64(plane_layers.terrain),
      terrain_flags: Base.encode64(plane_layers.terrain_flags),
      minerals: Base.encode64(plane_layers.minerals),
      exploration: Base.encode64(plane_layers.exploration),
      landmass: Base.encode64(plane_layers.landmass),
      computed_adj_mask: Base.encode64(plane_layers.computed_adj_mask),
      render_mode: Atom.to_string(state.render_mode),
      phase_index: effective_phase_index(state),
      snapshot_mode: Map.get(state, :snapshot_mode, true),
      layer_visibility: stringify_layer_map(layer_visibility),
      layer_opacity: stringify_layer_map(layer_opacity)
    })
  end

  defp maybe_push_updates(socket, layer, updates, changes) do
    if connected?(socket) and layer == socket.assigns.active_layer and updates != [] do
      payload_changes =
        if is_list(changes) do
          Enum.map(changes, fn {x, y, prev, new} ->
            %{x: x, y: y, value: new, prev: prev, new: new}
          end)
        else
          updates
        end

      push_event(socket, "engine_delta", %{
        plane: Atom.to_string(socket.assigns.plane),
        layer: Atom.to_string(layer),
        layer_type: layer_type(layer),
        delta_type: "tile_set",
        changes: payload_changes
      })
    end

    socket
  end

  defp emit_engine_delta(socket, plane, layer, changes) when is_list(changes) do
    state = socket.assigns.state
    engine_layer = engine_layer(layer)

    if engine_layer && Map.get(state, :engine_session_id) do
      delta = %Delta{
        type: :tile_set,
        plane: plane,
        layer: engine_layer,
        changes: changes,
        meta: %{source: :map_live}
      }

      case Session.whereis(state.engine_session_id) do
        nil -> :noop
        pid -> Session.apply_delta(pid, delta)
      end
    end

    socket
  end

  defp stroke_changes(stroke, :undo) do
    Enum.map(stroke.changes, fn {x, y, prev, new} -> {x, y, new, prev} end)
  end

  defp stroke_changes(stroke, :redo), do: stroke.changes

  defp maybe_push_tile_assets(socket) do
    state = socket.assigns.state

    if connected?(socket) and state.render_mode == :tiles do
      push_tile_assets(socket, state)
    else
      socket
    end
  end

  defp push_tile_assets(socket, state) do
    socket =
      case socket.assigns.tile_assets do
        nil -> assign(socket, :tile_assets, TileAtlas.build())
        _ -> socket
      end

    atlas = socket.assigns.tile_assets
    terrain_names = terrain_name_map(state)
    terrain_flag_names = terrain_flag_name_map(state)
    terrain_water_values = Application.get_env(:mirror, :terrain_water_values, [0])

    push_event(socket, "tile_assets", %{
      backend: Atom.to_string(Map.get(atlas, :backend, :lbx)),
      images: atlas.images,
      terrain_groups: atlas.terrain_groups,
      overlay_groups: atlas.overlay_groups,
      momime: atlas.momime,
      terrain_names: terrain_names,
      terrain_flag_names: terrain_flag_names,
      terrain_water_values: terrain_water_values
    })
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

  defp terrain_flag_name_map(%{dataset_id: nil}), do: %{}

  defp terrain_flag_name_map(state) do
    0..7
    |> Enum.reduce(%{}, fn bit, acc ->
      case Stats.bit_name(state.dataset_id, :terrain_flags, bit) do
        nil -> acc
        name -> Map.put(acc, Integer.to_string(bit), name)
      end
    end)
  end

  defp layer_type(layer) do
    if layer in @u16_layers, do: "u16", else: "u8"
  end

  defp engine_layer(:terrain), do: :terrain_u16
  defp engine_layer(:terrain_flags), do: :terrain_flags_u8
  defp engine_layer(:minerals), do: :minerals_u8
  defp engine_layer(:exploration), do: :exploration_u8
  defp engine_layer(:landmass), do: :landmass_u8
  defp engine_layer(_layer), do: nil

  defp engine_tile(state, plane, x, y) do
    with session_id when not is_nil(session_id) <- Map.get(state, :engine_session_id),
         tile when is_map(tile) <- View.tile_truth(session_id, plane, x, y),
         true <- map_size(tile) > 0 do
      tile
    else
      _ -> nil
    end
  end

  defp u8_layer?(layer), do: layer in @u8_layers

  defp bit_set?(value, bit) when is_integer(value) and is_integer(bit) do
    (value &&& 1 <<< bit) != 0
  end

  defp bit_set?(_value, _bit), do: false

  defp hex_byte(value) when is_integer(value) do
    value
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(2, "0")
    |> then(&("0x" <> &1))
  end

  defp hex_byte(_value), do: "0x00"

  defp original_tile_value(state, plane, layer, x, y) do
    with planes when is_map(planes) <- Map.get(state, :original_planes),
         plane_layers when is_map(plane_layers) <- Map.get(planes, plane),
         binary when is_binary(binary) <- Map.get(plane_layers, layer) do
      if layer in @u16_layers do
        MirrorMap.get_tile_u16_le(binary, x, y)
      else
        MirrorMap.get_tile_u8(binary, x, y)
      end
    else
      _ -> nil
    end
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

  defp default_layer_visibility(active_layer) do
    Enum.into(@layers, %{}, fn layer ->
      visible = layer == :terrain || layer == active_layer
      {layer, visible}
    end)
  end

  defp default_layer_opacity do
    Enum.into(@layers, %{}, fn layer ->
      {layer, if(layer == :terrain, do: 100, else: 70)}
    end)
  end

  defp normalize_layer_visibility(active_layer, visibility) when is_map(visibility) do
    Enum.into(@layers, %{}, fn layer ->
      default_visible = layer == :terrain || layer == active_layer
      value = Map.get(visibility, layer, default_visible)
      {layer, if(layer == :terrain, do: true, else: value)}
    end)
  end

  defp normalize_layer_visibility(active_layer, _visibility) do
    default_layer_visibility(active_layer)
  end

  defp normalize_layer_opacity(opacity) when is_map(opacity) do
    defaults = default_layer_opacity()

    Enum.into(@layers, %{}, fn layer ->
      {layer, Map.get(opacity, layer, Map.fetch!(defaults, layer))}
    end)
  end

  defp normalize_layer_opacity(_opacity), do: default_layer_opacity()

  defp ensure_layer_visible(state, layer) do
    visibility = Map.get(state, :layer_visibility, default_layer_visibility(state.active_layer))
    visibility = visibility |> Map.put(:terrain, true) |> Map.put(layer, true)
    Map.put(state, :layer_visibility, visibility)
  end

  defp parse_opacity(value) when is_integer(value) do
    value |> min(100) |> max(0)
  end

  defp parse_opacity(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> parse_opacity(int)
      :error -> 100
    end
  end

  defp parse_opacity(_value), do: 100

  defp stringify_layer_map(map) do
    Enum.into(map || %{}, %{}, fn {key, value} ->
      {to_string(key), value}
    end)
  end

  defp normalize_state(nil) do
    %{
      save: nil,
      planes: %{},
      original_planes: nil,
      active_layer: :terrain,
      selection: default_selection(),
      history: %{arcanus: [], myrror: []},
      redo: %{arcanus: [], myrror: []},
      save_path: nil,
      dataset_id: nil,
      render_mode: :tiles,
      phase_index: 0,
      snapshot_mode: true,
      snapshot_values: %{},
      phase_loop_len: nil,
      phase_loop_status: :unknown,
      phase_loop_detecting: false,
      layer_visibility: default_layer_visibility(:terrain),
      layer_opacity: default_layer_opacity(),
      engine_session_id: nil,
      engine_player_id: :observer
    }
  end

  defp normalize_state(state) do
    state =
      state
      |> Map.put_new(:active_layer, :terrain)
      |> Map.put_new(:selection, default_selection())
      |> Map.put_new(:history, %{arcanus: [], myrror: []})
      |> Map.put_new(:redo, %{arcanus: [], myrror: []})
      |> Map.put_new(:render_mode, :tiles)
      |> Map.put_new(:phase_index, 0)
      |> Map.put_new(:snapshot_mode, true)
      |> Map.put_new(:snapshot_values, %{})
      |> Map.put_new(:original_planes, Map.get(state, :save) && Map.get(state.save, :planes))
      |> Map.put_new(:phase_loop_len, nil)
      |> Map.put_new(:phase_loop_status, :unknown)
      |> Map.update(:phase_loop_status, :unknown, &normalize_phase_loop_status/1)
      |> Map.put_new(:phase_loop_detecting, false)
      |> Map.put_new(:engine_session_id, nil)
      |> Map.put_new(:engine_player_id, :observer)

    visibility = normalize_layer_visibility(state.active_layer, Map.get(state, :layer_visibility))
    opacity = normalize_layer_opacity(Map.get(state, :layer_opacity))

    state
    |> Map.put(:layer_visibility, visibility)
    |> Map.put(:layer_opacity, opacity)
  end

  defp ensure_engine_session(state, session_id, connected?) do
    cond do
      not connected? ->
        state

      is_nil(state.save) ->
        state

      engine_session_alive?(Map.get(state, :engine_session_id)) ->
        state

      true ->
        case start_engine_session(state.save.path) do
          {:ok, engine_session_id} ->
            state = %{state | engine_session_id: engine_session_id}
            SessionStore.put(session_id, state)
            state

          {:error, _reason} ->
            state
        end
    end
  end

  defp engine_session_alive?(nil), do: false

  defp engine_session_alive?(session_id) do
    case Session.whereis(session_id) do
      nil -> false
      _pid -> true
    end
  end

  defp start_engine_session(path) when is_binary(path) and path != "" do
    with {:ok, pid} <- SessionSupervisor.start_session(seed: System.unique_integer([:positive])),
         {:ok, session_id} <- Session.load_save(pid, path) do
      {:ok, session_id}
    end
  end

  defp start_engine_session(_path), do: {:error, :missing_path}

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
