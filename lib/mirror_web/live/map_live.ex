defmodule MirrorWeb.MapLive do
  use MirrorWeb, :live_view
  import Bitwise

  alias Mirror.Engine.{Delta, Session, View}

  alias Mirror.{
    Editor,
    OverlaySprites,
    Paths,
    SaveFile,
    SaveManager,
    SessionStore,
    Stats,
    Surveyor,
    TerrainLbx,
    TerrainPaint
  }

  alias Mirror.TileAtlas
  alias Mirror.SaveFile.{Cities, Roads, Sites, Units, Wizards}
  alias Mirror.Map, as: MirrorMap
  alias MirrorWeb.PaintTool

  @layers [
    :terrain,
    :terrain_flags,
    :minerals,
    :exploration,
    :landmass,
    :computed_adj_mask
  ]

  @u16_layers [:terrain]
  @u8_layers @layers -- (@u16_layers -- [:computed_adj_mask])

  @layer_labels %{
    terrain: "Terrain (u16)",
    terrain_flags: "Terrain Flags",
    minerals: "Minerals",
    exploration: "Exploration",
    landmass: "Landmass",
    computed_adj_mask: "Adjacency Mask"
  }

  # Map-page overlay layers (STORY-009), bottom to top, and whether each is
  # on until the viewer changes it. Drawn client-side by map_overlays.js on a
  # canvas above the terrain; each story that decodes a layer's save data
  # fills it in.
  @overlay_layers [
    {:settleable, "Settleable tiles", "STORY-035", false},
    {:roads, "Roads & specials", "STORY-013", true},
    {:auras, "Node auras", "STORY-008", true},
    {:sites, "Sites", "STORY-011", true},
    {:cities, "Cities", "STORY-010", true},
    {:units, "Units", "STORY-012", true},
    {:fog, "Fog of war", "STORY-036", false}
  ]

  @phase_loop_max 32
  @phase_loop_fallback 8
  @phase_loop_threshold 0

  @impl true
  def mount(params, session, socket) do
    session_id = session["mirror_session_id"] || "local"

    {plane, lab?} =
      case socket.assigns.live_action do
        :lab -> {parse_plane(params["plane"]), true}
        action -> {action || :arcanus, false}
      end

    state =
      session_id
      |> SessionStore.get()
      |> SaveManager.normalize_state()

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:plane, plane)
      |> assign(:lab?, lab?)
      |> assign(:edit, nil)
      |> assign(:tool, :cycle)
      |> assign(:paint_kind, PaintTool.default_kind())
      |> assign(:paint_size, PaintTool.default_size())
      |> assign(:paint_fill, false)
      |> assign(:paint_report, nil)
      |> assign(:discard_armed, false)
      |> assign(:fresh_mount, true)

    state = SaveManager.ensure_engine_session(state, session_id, connected?(socket))

    socket =
      socket
      |> assign_from_state(state)
      |> assign(:active_stroke, nil)
      |> assign(:hover, nil)
      |> assign(:tile_assets, nil)
      |> assign(:load_path, SaveManager.default_load_path())
      |> assign(:save_path_input, state.save_path || "")
      |> assign_forms()

    if connected?(socket) do
      SessionStore.subscribe(session_id)
    end

    if connected?(socket) and state.save do
      socket = push_map_state(socket)
      socket = push_map_reload(socket)
      socket = maybe_push_tile_assets(socket)
      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  # `?edit=terrain` turns on edit mode on the map pages (never in the Lab).
  @impl true
  def handle_params(params, _uri, socket) do
    requested = not socket.assigns.lab? and params["edit"] == "terrain"

    # A fresh page load (including reload) always opens in view mode; edits
    # are kept as a draft and shown by the unsaved-changes notice (STORY-026).
    if requested and socket.assigns.fresh_mount and connected?(socket) do
      {:noreply,
       socket
       |> assign(:fresh_mount, false)
       |> push_patch(to: map_path(socket.assigns.plane), replace: true)}
    else
      handle_edit_params(requested, assign(socket, :fresh_mount, not connected?(socket)))
    end
  end

  defp handle_edit_params(_requested, %{assigns: %{lab?: true}} = socket) do
    {:noreply, socket}
  end

  defp handle_edit_params(requested, socket) do
    edit = if requested, do: :terrain, else: nil
    socket = socket |> assign(:edit, edit) |> assign(:discard_armed, false) |> assign_forms()

    # Edits go through the terrain layer; keep the session's active layer in
    # step so stroke updates reach the canvas.
    socket =
      if edit && socket.assigns.state.active_layer != :terrain do
        {:ok, state} =
          SessionStore.update(socket.assigns.session_id, fn current ->
            SaveManager.ensure_layer_visible(%{current | active_layer: :terrain}, :terrain)
          end)

        socket |> assign_from_state(state) |> assign_forms()
      else
        socket
      end

    socket =
      if connected?(socket) do
        socket
        |> push_event("edit_mode", %{mode: if(edit, do: "edit", else: "view")})
        |> push_brush()
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:session_state_updated, session_id, new_state, sender}, socket) do
    if session_id == socket.assigns.session_id and sender != self() do
      current_state = SessionStore.get(session_id) || new_state

      socket =
        socket
        |> assign_from_state(current_state)
        |> assign_forms()
        |> refresh_hover()

      socket =
        if connected?(socket) do
          socket
          |> push_map_state()
          |> push_map_reload()
          |> push_map_layers()
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_edit", _params, socket) do
    to =
      if socket.assigns.edit,
        do: map_path(socket.assigns.plane),
        else: edit_path(socket.assigns.plane)

    {:noreply, push_patch(socket, to: to)}
  end

  def handle_event("exit_edit", _params, socket) do
    if socket.assigns.edit do
      {:noreply, push_patch(socket, to: map_path(socket.assigns.plane))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_tool", %{"tool" => tool}, socket)
      when tool in ["cycle", "paint", "type"] do
    {:noreply, assign(socket, :tool, String.to_existing_atom(tool))}
  end

  # The "Paint type" tool's options: terrain, brush size, fill.
  def handle_event("set_paint", %{"paint" => params}, socket) do
    {:noreply,
     socket
     |> assign(:paint_kind, PaintTool.parse_kind(params["kind"]) || socket.assigns.paint_kind)
     |> assign(:paint_size, PaintTool.parse_size(params["size"], socket.assigns.paint_size))
     |> assign(:paint_fill, PaintTool.parse_flag(params["fill"]))}
  end

  # Raw painter: pick a plain tile for a terrain from the dropdown.
  def handle_event("set_quick_tile", %{"quick" => %{"tile" => tile}}, socket) do
    case Integer.parse(to_string(tile)) do
      {value, ""} -> handle_event("set_brush", %{"brush" => %{"tile" => value}}, socket)
      _ -> {:noreply, socket}
    end
  end

  # Discard is a two-step in-page confirmation: native confirm() dialogs are
  # silently cancelled in some embedded browsers (STORY-026).
  def handle_event("arm_discard", _params, socket) do
    {:noreply, assign(socket, :discard_armed, socket.assigns.changed_tiles > 0)}
  end

  def handle_event("cancel_discard", _params, socket) do
    {:noreply, assign(socket, :discard_armed, false)}
  end

  def handle_event("set_brush", %{"brush" => %{"tile" => tile}}, socket) do
    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        value =
          tile
          |> parse_int(Map.get(current.selection, :terrain, 0))
          |> then(&clamp_value(:terrain, &1))

        %{current | selection: Map.put(current.selection, :terrain, value)}
      end)

    {:noreply, socket |> assign_from_state(state) |> assign_forms() |> push_brush()}
  end

  def handle_event("discard_edits", _params, socket) do
    socket = assign(socket, :discard_armed, false)

    case SessionStore.update(socket.assigns.session_id, fn current ->
           if current.save do
             {state, restored_save} = Editor.discard(current)
             SaveManager.restore_engine_session(state, restored_save)
           else
             current
           end
         end) do
      {:ok, %{save: %SaveFile{}} = state} ->
        socket =
          socket
          |> assign_from_state(state)
          |> assign_forms()
          |> refresh_hover()
          |> put_flash(:info, "Edits discarded.")

        socket =
          if connected?(socket),
            do: socket |> push_map_state() |> push_map_reload() |> push_map_layers(),
            else: socket

        {:noreply, socket}

      {:ok, state} ->
        {:noreply, socket |> assign_from_state(state) |> assign_forms()}
    end
  end

  @impl true
  def handle_event("load_save", %{"load" => %{"path" => path}}, socket) do
    path = SaveManager.normalize_path(path)

    socket =
      socket
      |> assign(:load_path, path)
      |> assign_forms()

    case SaveManager.load(path, socket.assigns.state) do
      {:ok, state, normalized_path} ->
        SessionStore.put(socket.assigns.session_id, state)

        socket =
          socket
          |> assign_from_state(state)
          |> assign_forms()
          |> put_flash(:info, "Loaded save from #{normalized_path}.")

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

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, SaveManager.load_error_message(reason, path))}
    end
  end

  def handle_event("save_file", %{"save" => %{"path" => path}}, socket) do
    path = SaveManager.normalize_path(path)
    socket = assign(socket, :save_path_input, path)

    update_result =
      SessionStore.update(socket.assigns.session_id, fn current ->
        case SaveManager.save(current, path) do
          {:ok, updated_state, save_path} ->
            {updated_state, save_path}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    case update_result do
      {:ok, state, save_path} ->
        {:noreply,
         put_flash(assign_state(socket, state), :info, SaveManager.saved_message(save_path))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, SaveManager.save_error_message(reason))}
    end
  end

  def handle_event("set_active_layer", %{"layer" => layer}, socket) do
    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        layer_atom = Enum.find(@layers, current.active_layer, &(&1 |> Atom.to_string() == layer))

        current
        |> Map.put(:active_layer, layer_atom)
        |> SaveManager.ensure_layer_visible(layer_atom)
      end)

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
    settings = Map.get(params, "layer_#{layer}") || %{}

    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        layer_atom = Enum.find(@layers, current.active_layer, &(&1 |> Atom.to_string() == layer))

        current_visible =
          Map.get(Map.get(current, :layer_visibility, %{}), layer_atom, layer_atom == :terrain)

        visible_value = Map.get(settings, "visible", current_visible)

        visibility =
          Map.get(current, :layer_visibility, %{})
          |> Map.put_new(:terrain, true)
          |> Map.put(layer_atom, truthy?(visible_value))

        current_opacity =
          Map.get(
            Map.get(current, :layer_opacity, %{}),
            layer_atom,
            if(layer_atom == :terrain, do: 100, else: 70)
          )

        opacity_value = Map.get(settings, "opacity", current_opacity)

        opacity =
          Map.get(current, :layer_opacity, %{})
          |> Map.put_new(:terrain, 100)
          |> Map.put(layer_atom, parse_opacity(opacity_value))

        if layer_atom == :terrain do
          current
          |> Map.put(:layer_visibility, Map.put(visibility, :terrain, true))
          |> Map.put(:layer_opacity, opacity)
        else
          current
          |> Map.put(:layer_visibility, visibility)
          |> Map.put(:layer_opacity, opacity)
        end
      end)

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

    if state.save && pointer_allowed?(socket, params["action"]) do
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
    load_form = to_form(%{"path" => path || ""}, as: :load)
    {:noreply, assign(socket, load_path: path, load_form: load_form)}
  end

  def handle_event("update_save_path", %{"save" => %{"path" => path}}, socket) do
    save_form = to_form(%{"path" => path || ""}, as: :save)
    {:noreply, assign(socket, save_path_input: path, save_form: save_form)}
  end

  def handle_event("toggle_render_mode", _params, socket) do
    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        render_mode =
          case current.render_mode do
            :tiles -> :values
            _ -> :tiles
          end

        %{current | render_mode: render_mode}
      end)

    render_mode = state.render_mode

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
    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        snapshot_mode = not Map.get(current, :snapshot_mode, true)
        %{current | snapshot_mode: snapshot_mode}
      end)

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
        {:ok, state} =
          SessionStore.update(socket.assigns.session_id, fn current ->
            %{current | phase_loop_detecting: true}
          end)

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
    status = Map.get(params, "status", "unknown")

    {:ok, next_state, flash} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        case status do
          "detected" ->
            loop_len =
              params
              |> Map.get("loop_len")
              |> parse_int(current.phase_loop_len || @phase_loop_fallback)
              |> max(1)

            state = %{
              current
              | phase_loop_len: loop_len,
                phase_loop_status: :detected,
                phase_loop_detecting: false
            }

            {state, {:info, "Detected phase loop length: #{loop_len}."}}

          "assumed" ->
            loop_len =
              params
              |> Map.get("loop_len")
              |> parse_int(@phase_loop_fallback)
              |> max(1)

            state = %{
              current
              | phase_loop_len: loop_len,
                phase_loop_status: :assumed,
                phase_loop_detecting: false
            }

            {state, {:info, "No loop found. Using #{loop_len} as a fallback."}}

          _ ->
            state = %{current | phase_loop_detecting: false, phase_loop_status: :unknown}
            {state, {:error, "Phase loop detection failed."}}
        end
      end)

    {flash_type, flash_msg} = flash
    socket = put_flash(socket, flash_type, flash_msg)

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
    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        phase_index = index |> parse_int(current.phase_index || 0) |> max(0)
        %{current | phase_index: phase_index}
      end)

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
      <%= if @lab? do %>
        <div class="relative min-h-[100svh]">
          <div class="relative flex min-h-[100svh] flex-col">
            <header class="pointer-events-auto border-b border-white/10 bg-slate-950/80 px-6 py-5 shadow-lg shadow-black/60 backdrop-blur">
              <div class="rounded-3xl border border-white/10 bg-slate-950/70 p-6 shadow-xl shadow-black/60 backdrop-blur">
                <div class="flex flex-wrap items-end justify-between gap-4">
                  <div>
                    <p class="text-xs uppercase tracking-[0.3em] text-slate-400">
                      Lab ·
                      <.link
                        navigate={~p"/lab/#{other_plane(@plane)}"}
                        class="underline decoration-dotted hover:text-white"
                      >
                        switch to {plane_name(other_plane(@plane))}
                      </.link>
                      ·
                      <.link
                        navigate={map_path(@plane)}
                        class="underline decoration-dotted hover:text-white"
                      >
                        back to map
                      </.link>
                    </p>

                    <h2 class="text-3xl font-semibold text-white">
                      {plane_name(@plane)}
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
                        <span>Input: {@phase_input}</span> <span>Effective: {@phase_index}</span>
                        <span>Loop: {if(@phase_loop_len, do: @phase_loop_len, else: "Unknown")}</span>
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
                    placeholder="C:\\games\\MOM\\SAVES\\SAVE1.GAM"
                    phx-hook="StableInput"
                    class="w-full rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200 placeholder:text-slate-500"
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
                    phx-hook="StableInput"
                    class="w-full rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200 placeholder:text-slate-500"
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
                                      if(layer == :terrain,
                                        do: "Base (always on)",
                                        else: "Show layer"
                                      )
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
                              <.icon
                                name="hero-adjustments-horizontal"
                                class="size-4 text-emerald-300"
                              />
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
                  <.map_canvas
                    plane={@plane}
                    map_width={@map_width}
                    map_height={@map_height}
                    active_layer={@active_layer}
                    encoded_layer={@encoded_layer}
                    terrain_encoded={@terrain_encoded}
                    terrain_flags_encoded={@terrain_flags_encoded}
                    minerals_encoded={@minerals_encoded}
                    exploration_encoded={@exploration_encoded}
                    landmass_encoded={@landmass_encoded}
                    adj_mask_encoded={@adj_mask_encoded}
                    render_mode={@render_mode}
                    phase_index={@phase_index}
                    snapshot_mode={@snapshot_mode}
                  />
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
                        <% value = @hover.layer_value || 0 %> <% original_value =
                          @hover.original_value %> <% snapshot_value =
                          snapshot_value(@state, @plane, @active_layer) %> <% unsupported_layer =
                          not u8_layer?(@active_layer) %>
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
                              <% bit_on = bit_set?(value, bit) %> <% bit_name =
                                Map.get(@bit_names, bit) %>
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
                          <.input field={form[:bit]} type="hidden" id={"bit_name_bit_#{bit}"} />
                          <span class="text-xs font-semibold text-slate-300">Bit {bit}</span>
                          <.input
                            field={form[:name]}
                            id={"bit_name_name_#{bit}"}
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
      <% else %>
        <div class="flex flex-col">
          <header class="flex flex-wrap items-center justify-between gap-3 border-b border-white/10 bg-slate-950/80 px-4 py-2">
            <div class="flex items-center gap-4">
              <nav class="flex rounded-xl border border-white/10 p-0.5 text-sm" aria-label="Plane">
                <.link
                  :for={plane <- [:arcanus, :myrror]}
                  navigate={map_path(plane)}
                  class={[
                    "rounded-lg px-3 py-1 transition",
                    plane == @plane && "bg-white/10 font-semibold text-white",
                    plane != @plane && "text-slate-400 hover:text-white"
                  ]}
                  aria-current={plane == @plane && "page"}
                >
                  {plane_name(plane)}
                </.link>
              </nav>
              <span class="truncate text-sm text-slate-400">
                {if @state.save_path, do: Path.basename(@state.save_path), else: "No save loaded"}
              </span>
            </div>

            <div class="flex flex-wrap items-center gap-2">
              <.form
                for={@load_form}
                id="load-form"
                phx-submit="load_save"
                phx-change="update_load_path"
                class="flex items-center gap-2"
              >
                <.input
                  field={@load_form[:path]}
                  type="text"
                  placeholder="Path to SAVEn.GAM"
                  phx-hook="StableInput"
                  class="w-72 rounded-lg border border-white/10 bg-slate-950/60 py-1 text-sm text-slate-200 placeholder:text-slate-500"
                />
                <button
                  id="load-save-button"
                  type="submit"
                  class="rounded-lg bg-amber-300 px-3 py-1 text-sm font-semibold text-slate-950 transition hover:bg-amber-200"
                >
                  Load
                </button>
              </.form>

              <button
                id="toggle-edit-button"
                type="button"
                phx-click="toggle_edit"
                disabled={is_nil(@state.save)}
                class={[
                  "rounded-lg px-3 py-1 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-40",
                  @edit && "bg-emerald-300 text-slate-950 hover:bg-emerald-200",
                  !@edit && "border border-emerald-300/50 text-emerald-100 hover:border-emerald-200"
                ]}
              >
                {if @edit, do: "Done", else: "✎ Edit"}
              </button>

              <.link
                id="open-lab-link"
                navigate={~p"/lab/#{@plane}"}
                class="rounded-lg border border-white/15 px-3 py-1 text-sm text-slate-300 transition hover:border-white/40 hover:text-white"
              >
                Lab
              </.link>
            </div>
          </header>

          <%!-- Notice and toolbar float over the map so their size never shifts
               the map under the pointer (a click would land on another tile). --%>
          <div class="relative">
            <div
              :if={!@edit && @changed_tiles > 0}
              id="unsaved-notice"
              class="absolute inset-x-0 top-0 z-20 flex flex-wrap items-center gap-3 border-b border-amber-300/20 bg-amber-950/85 px-4 py-1.5 text-sm text-amber-100 backdrop-blur"
            >
              <span>
                {@changed_tiles} unsaved {if @changed_tiles == 1, do: "change", else: "changes"} (not in the save file yet)
              </span>
              <button
                type="button"
                phx-click="toggle_edit"
                class="rounded-lg border border-amber-200/40 px-2.5 py-0.5 hover:border-amber-100"
              >
                Review in edit mode
              </button>
              <.discard_control changed_tiles={@changed_tiles} armed={@discard_armed} />
            </div>

            <div
              :if={@edit}
              id="edit-toolbar"
              class="absolute inset-x-0 top-0 z-20 flex flex-wrap items-center gap-x-5 gap-y-2 border-b border-emerald-300/20 bg-emerald-950/85 px-4 py-2 text-sm text-slate-200 backdrop-blur"
            >
              <div
                class="flex rounded-lg border border-white/10 p-0.5"
                role="group"
                aria-label="Edit layer"
              >
                <span class="rounded-md bg-white/10 px-2.5 py-0.5 font-semibold text-white">
                  Terrain
                </span>
                <span
                  :for={label <- ["Roads", "Structures", "Units"]}
                  class="px-2.5 py-0.5 text-slate-500"
                  title="Coming once this data is decoded (EPIC-004)"
                >
                  {label}
                </span>
              </div>

              <div class="flex rounded-lg border border-white/10 p-0.5" role="group" aria-label="Tool">
                <button
                  :for={
                    {tool, label, hint} <- [
                      {:cycle, "🔄 Cycle", "Step a tile to the next picture"},
                      {:type, "🌍 Paint type",
                       "Paint water or a land type; neighbouring tiles re-tile automatically"},
                      {:paint, "🎨 Paint tile",
                       "Paint one exact tile number; neighbours are not touched"}
                    ]
                  }
                  id={"tool-#{tool}"}
                  title={hint}
                  type="button"
                  phx-click="set_tool"
                  phx-value-tool={tool}
                  aria-pressed={to_string(@tool == tool)}
                  class={[
                    "rounded-md px-2.5 py-0.5 transition",
                    @tool == tool && "bg-emerald-300 font-semibold text-slate-950",
                    @tool != tool && "text-slate-300 hover:text-white"
                  ]}
                >
                  {label}
                </button>
              </div>

              <.form
                :if={@tool == :type}
                for={%{}}
                as={:paint}
                id="paint-form"
                phx-change="set_paint"
                class="flex flex-wrap items-center gap-x-3 gap-y-1"
              >
                <label class="flex items-center gap-1.5">
                  <span class="text-slate-400">Terrain</span>
                  <select
                    id="paint-kind"
                    name="paint[kind]"
                    class="rounded-lg border border-white/10 bg-slate-950/60 py-0.5 text-sm text-slate-200"
                  >
                    <option
                      :for={{label, value} <- PaintTool.kind_options()}
                      value={value}
                      selected={value == Atom.to_string(@paint_kind)}
                    >
                      {label}
                    </option>
                  </select>
                </label>
                <label class="flex items-center gap-1.5">
                  <span class="text-slate-400">Brush</span>
                  <select
                    id="paint-size"
                    name="paint[size]"
                    disabled={@paint_fill}
                    class="rounded-lg border border-white/10 bg-slate-950/60 py-0.5 text-sm text-slate-200 disabled:opacity-40"
                  >
                    <option
                      :for={{label, value} <- PaintTool.size_options()}
                      value={value}
                      selected={value == Integer.to_string(@paint_size)}
                    >
                      {label}
                    </option>
                  </select>
                </label>
                <label class="flex items-center gap-1.5">
                  <input type="hidden" name="paint[fill]" value="false" />
                  <input
                    id="paint-fill"
                    type="checkbox"
                    name="paint[fill]"
                    value="true"
                    checked={@paint_fill}
                  />
                  <span class="text-slate-400">Fill</span>
                </label>
              </.form>

              <span
                :if={@tool == :type && @paint_report && @paint_report[:message]}
                id="paint-report"
                class={[
                  "text-xs",
                  elem(@paint_report.message, 0) == :warn && "text-amber-200",
                  elem(@paint_report.message, 0) == :ok && "text-emerald-200"
                ]}
              >
                {elem(@paint_report.message, 1)}
              </span>

              <.form
                :if={@tool == :paint}
                for={%{}}
                as={:quick}
                id="quick-tile-form"
                phx-change="set_quick_tile"
                class="flex items-center gap-1.5"
              >
                <span class="text-slate-400">Quick</span>
                <select
                  id="quick-tile"
                  name="quick[tile]"
                  class="rounded-lg border border-white/10 bg-slate-950/60 py-0.5 text-sm text-slate-200"
                >
                  <option value="">Plain tile…</option>
                  <option
                    :for={{label, tile} <- PaintTool.quick_tile_options()}
                    value={tile}
                    selected={tile == Map.get(@state.selection, :terrain)}
                  >
                    {label} ({tile})
                  </option>
                </select>
              </.form>

              <.form
                :if={@tool == :paint}
                for={@brush_form}
                id="brush-form"
                phx-change="set_brush"
                phx-submit="set_brush"
                class="flex items-center gap-2"
              >
                <span class="text-slate-400">Tile</span>
                <canvas
                  id="brush-preview"
                  phx-update="ignore"
                  width="20"
                  height="18"
                  class="h-[27px] w-[30px] rounded border border-white/20"
                  style="image-rendering: pixelated"
                >
                </canvas>
                <.input
                  field={@brush_form[:tile]}
                  type="number"
                  min="0"
                  max="761"
                  phx-debounce="200"
                  class="w-20 rounded-lg border border-white/10 bg-slate-950/60 py-0.5 text-sm text-slate-200"
                />
              </.form>

              <span class="text-xs text-slate-400">
                {case @tool do
                  :cycle ->
                    "Click: next tile · right-click or shift-click: previous · space-drag or middle-drag to pan · Esc to finish"

                  :type ->
                    "Click or drag: paint the terrain, neighbours re-tile · right-click: pick the terrain under the pointer · space-drag or middle-drag to pan · Esc to finish"

                  _ ->
                    "Click or drag: paint this exact tile (neighbours are not re-tiled; use Paint type for that) · right-click: pick tile · space-drag or middle-drag to pan · Esc to finish"
                end}
              </span>

              <div class="ml-auto flex flex-wrap items-center gap-2">
                <button
                  type="button"
                  phx-click="undo"
                  class="rounded-lg border border-white/15 px-2.5 py-0.5 hover:border-white/40"
                >
                  Undo
                </button>
                <button
                  type="button"
                  phx-click="redo"
                  class="rounded-lg border border-white/15 px-2.5 py-0.5 hover:border-white/40"
                >
                  Redo
                </button>
                <span
                  id="changed-tiles"
                  class={[
                    @changed_tiles > 0 && "text-amber-200",
                    @changed_tiles == 0 && "text-slate-500"
                  ]}
                >
                  {@changed_tiles} {if @changed_tiles == 1, do: "tile", else: "tiles"} changed
                </span>
                <.discard_control changed_tiles={@changed_tiles} armed={@discard_armed} />
                <.form
                  for={@save_form}
                  id="save-form"
                  phx-submit="save_file"
                  phx-change="update_save_path"
                  class="flex items-center gap-2"
                >
                  <.input
                    field={@save_form[:path]}
                    type="text"
                    placeholder="Save as… (new file path)"
                    phx-hook="StableInput"
                    class="w-72 rounded-lg border border-white/10 bg-slate-950/60 py-0.5 text-sm text-slate-200 placeholder:text-slate-500"
                  />
                  <button
                    id="save-button"
                    type="submit"
                    class="rounded-lg bg-emerald-300 px-3 py-0.5 font-semibold text-slate-950 hover:bg-emerald-200"
                  >
                    Save as
                  </button>
                </.form>
              </div>
            </div>

            <div
              id="map-viewport"
              phx-hook="MapViewport"
              phx-update="ignore"
              class="relative touch-none select-none overflow-hidden bg-slate-950"
            >
              <div data-map-stage class="relative w-max">
                <.map_canvas
                  plane={@plane}
                  interaction={if @edit, do: "edit", else: "view"}
                  map_width={@map_width}
                  map_height={@map_height}
                  active_layer={@active_layer}
                  encoded_layer={@encoded_layer}
                  terrain_encoded={@terrain_encoded}
                  terrain_flags_encoded={@terrain_flags_encoded}
                  minerals_encoded={@minerals_encoded}
                  exploration_encoded={@exploration_encoded}
                  landmass_encoded={@landmass_encoded}
                  adj_mask_encoded={@adj_mask_encoded}
                  render_mode={@render_mode}
                  phase_index={@phase_index}
                  snapshot_mode={@snapshot_mode}
                />
                <canvas
                  id="map-overlays"
                  phx-hook="MapOverlays"
                  data-map-width={@map_width}
                  data-map-height={@map_height}
                  data-tile-size="32"
                  class="pointer-events-none absolute left-0 top-0"
                  aria-hidden="true"
                >
                </canvas>
              </div>

              <details
                id="overlay-layers-panel"
                data-overlay-panel
                open
                class="absolute bottom-16 right-4 z-10 rounded-xl border border-white/10 bg-slate-950/85 px-3 py-2 text-sm text-slate-200 shadow-lg"
              >
                <summary class="cursor-pointer select-none font-semibold">Layers</summary>
                <ul class="mt-2 space-y-1">
                  <li :for={{layer, label, story, on} <- Enum.reverse(overlay_layers())}>
                    <label class="flex items-center gap-2" title={"Data arrives with #{story}"}>
                      <input
                        type="checkbox"
                        data-overlay-toggle
                        data-for="map-overlays"
                        value={layer}
                        checked={on}
                        class="rounded border-white/20 bg-slate-900"
                      />
                      <span>{label}</span>
                    </label>
                  </li>
                </ul>
              </details>

              <div class="absolute bottom-4 right-4 flex items-center gap-1 rounded-xl border border-white/10 bg-slate-950/85 p-1 text-sm text-slate-200 shadow-lg">
                <button
                  type="button"
                  data-zoom="out"
                  class="rounded-lg px-2.5 py-1 hover:bg-white/10"
                  aria-label="Zoom out"
                >
                  −
                </button>
                <button
                  type="button"
                  data-zoom="fit"
                  class="rounded-lg px-2 py-1 font-mono text-xs hover:bg-white/10"
                  aria-label="Fit map to window"
                >
                  <span data-zoom-label>100%</span>
                </button>
                <button
                  type="button"
                  data-zoom="in"
                  class="rounded-lg px-2.5 py-1 hover:bg-white/10"
                  aria-label="Zoom in"
                >
                  +
                </button>
              </div>
            </div>
          </div>

          <div
            :if={@hover}
            id="hover-readout"
            class="pointer-events-none fixed bottom-4 left-4 rounded-lg border border-white/10 bg-slate-950/85 px-3 py-1.5 font-mono text-xs text-slate-300 shadow-lg"
          >
            {plane_name(@plane)} ({@hover.x}, {@hover.y}) · tile {@hover.terrain}
            <span class="text-slate-500">({hex_word(@hover.terrain)})</span>
            <span :if={@hover.city} id="hover-city" class="text-amber-200">
              · {@hover.city.name}
              <span class="text-slate-400">
                ({Cities.size_name(@hover.city.size)}{if @hover.city.walled, do: ", walled"})
              </span>
            </span>
            <span :if={@edit && @tool == :cycle} class="text-emerald-300">
              → {Integer.mod(@hover.terrain + 1, TerrainLbx.tiles_per_plane())}
            </span>
          </div>

          <.surveyor_card :if={@hover && @hover.survey && !@edit} survey={@hover.survey} />
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  attr :survey, :any, required: true

  # The game's Surveyor panel for the hovered tile (STORY-034). An overlay,
  # so it never shifts the map under the pointer.
  defp surveyor_card(%{survey: :unexplored} = assigns) do
    ~H"""
    <div id="surveyor" class={surveyor_class()}>
      <p class="font-semibold text-slate-200">Surveyor</p>
      <p class="text-slate-500">Unexplored</p>
    </div>
    """
  end

  defp surveyor_card(assigns) do
    ~H"""
    <div id="surveyor" class={surveyor_class()}>
      <p class="font-semibold text-slate-200">Surveyor</p>
      <p class="text-amber-200">{@survey.terrain}</p>
      <p :for={line <- @survey.lines} class="whitespace-pre">{line}</p>
      <div :if={@survey.feature != []} id="surveyor-feature" class="mt-1 text-amber-200">
        <p :for={line <- @survey.feature}>{line}</p>
      </div>
      <%= case @survey.resources do %>
        <% {:cannot_build, reason} -> %>
          <p id="surveyor-cannot-build" class="mt-2 text-slate-400">
            Cities cannot be built {reason}
          </p>
        <% resources -> %>
          <dl id="surveyor-resources" class="mt-2 grid grid-cols-[1fr_auto] gap-x-3 text-left">
            <dt class="col-span-2 text-center text-amber-200">City Resources</dt>
            <dt>Maximum Pop</dt>
            <dd class="text-right">{resources.max_pop}</dd>
            <dt>Prod Bonus</dt>
            <dd class="text-right">+{resources.production}%</dd>
            <dt>Gold Bonus</dt>
            <dd class="text-right">+{resources.gold}%</dd>
          </dl>
      <% end %>
    </div>
    """
  end

  defp surveyor_class,
    do:
      "pointer-events-none fixed bottom-14 left-4 w-56 rounded-lg border border-white/10 " <>
        "bg-slate-950/85 px-3 py-2 text-center font-mono text-xs text-slate-300 shadow-lg"

  attr :changed_tiles, :integer, required: true
  attr :armed, :boolean, required: true

  defp discard_control(assigns) do
    ~H"""
    <span :if={@changed_tiles > 0} id="discard-control" class="inline-flex items-center gap-2">
      <button
        :if={!@armed}
        id="discard-edits-button"
        type="button"
        phx-click="arm_discard"
        class="rounded-lg border border-rose-300/40 px-2.5 py-0.5 text-rose-100 hover:border-rose-200"
      >
        Discard
      </button>
      <span :if={@armed} class="text-rose-100">Discard {@changed_tiles} changes?</span>
      <button
        :if={@armed}
        id="confirm-discard-button"
        type="button"
        phx-click="discard_edits"
        class="rounded-lg bg-rose-300 px-2.5 py-0.5 font-semibold text-slate-950 hover:bg-rose-200"
      >
        Yes, discard
      </button>
      <button
        :if={@armed}
        id="cancel-discard-button"
        type="button"
        phx-click="cancel_discard"
        class="rounded-lg border border-white/15 px-2.5 py-0.5 hover:border-white/40"
      >
        Cancel
      </button>
    </span>
    """
  end

  attr :plane, :atom, required: true
  attr :interaction, :string, default: "lab"
  attr :map_width, :integer, required: true
  attr :map_height, :integer, required: true
  attr :active_layer, :atom, required: true
  attr :encoded_layer, :string, required: true
  attr :terrain_encoded, :string, required: true
  attr :terrain_flags_encoded, :string, required: true
  attr :minerals_encoded, :string, required: true
  attr :exploration_encoded, :string, required: true
  attr :landmass_encoded, :string, required: true
  attr :adj_mask_encoded, :string, required: true
  attr :render_mode, :atom, required: true
  attr :phase_index, :integer, required: true
  attr :snapshot_mode, :boolean, required: true

  defp map_canvas(assigns) do
    ~H"""
    <canvas
      id="map-canvas"
      phx-hook="MapCanvas"
      phx-update="ignore"
      data-map-width={@map_width}
      data-map-height={@map_height}
      data-plane={Atom.to_string(@plane)}
      data-interaction={@interaction}
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
    """
  end

  defp hex_word(value) when is_integer(value),
    do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 3, "0")

  defp overlay_layers, do: @overlay_layers

  defp plane_name(:arcanus), do: "Arcanus"
  defp plane_name(:myrror), do: "Myrror"

  defp map_path(:arcanus), do: ~p"/arcanus"
  defp map_path(:myrror), do: ~p"/myrror"

  defp other_plane(:arcanus), do: :myrror
  defp other_plane(:myrror), do: :arcanus

  defp set_selection_from_value(socket, value) do
    layer = socket.assigns.state.active_layer
    value = parse_int(value, 0)

    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        selection = Map.put(current.selection, layer, clamp_value(layer, value))
        %{current | selection: selection}
      end)

    socket =
      socket
      |> assign_from_state(state)
      |> assign_forms()

    {:noreply, socket}
  end

  defp handle_pointer_start(
         %{assigns: %{edit: :terrain, tool: :cycle}} = socket,
         x,
         y,
         button,
         mods
       ) do
    direction = if button == 2 or truthy?(mods["shift"]), do: -1, else: 1
    cycle_tile(socket, x, y, direction)
  end

  defp handle_pointer_start(
         %{assigns: %{edit: :terrain, tool: :type}} = socket,
         x,
         y,
         button,
         mods
       ) do
    cond do
      button == 2 or truthy?(mods["ctrl"]) -> pick_paint_kind(socket, x, y)
      socket.assigns.paint_fill -> paint_fill(socket, x, y)
      true -> start_type_stroke(socket, x, y)
    end
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
      %{type_paint: stroke_id} ->
        paint_cells(
          socket,
          TerrainPaint.brush_cells(x, y, socket.assigns.paint_size),
          stroke_id,
          false
        )

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

    {:ok, state} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        next_value = Map.get(current.selection, layer, 0) + direction * step
        selection = Map.put(current.selection, layer, clamp_value(layer, next_value))
        %{current | selection: selection}
      end)

    socket
    |> assign_from_state(state)
    |> assign_forms()
  end

  # --- Paint type tool (STORY-017) ---

  defp start_type_stroke(socket, x, y) do
    stroke_id = System.unique_integer([:positive, :monotonic])

    socket
    |> assign(:active_stroke, %{type_paint: stroke_id, layer: :terrain})
    |> paint_cells(TerrainPaint.brush_cells(x, y, socket.assigns.paint_size), stroke_id, true)
  end

  # Fill is one click, one undo step.
  defp paint_fill(socket, x, y) do
    cells = TerrainPaint.fill_cells(tile_state(socket), x, y)

    paint_cells(socket, cells, System.unique_integer([:positive, :monotonic]), true)
  end

  defp tile_state(socket) do
    get_in(socket.assigns.state, [:planes, socket.assigns.plane, :terrain])
  end

  # Right-click / ctrl-click: take the terrain under the pointer as the brush.
  defp pick_paint_kind(socket, x, y) do
    type =
      case tile_value(socket.assigns.state, socket.assigns.plane, :terrain, x, y) do
        nil -> nil
        tile -> Mirror.TerrainType.terrain_type(tile)
      end

    case PaintTool.kind_of_type(type) do
      nil ->
        assign(socket, :paint_report, %{
          message: {:warn, "That tile can't be painted (river, lake, node or volcano)"}
        })

      kind ->
        assign(socket, :paint_kind, kind)
    end
  end

  # Paints `cells` and pushes every changed layer to the page and engine. Calls that
  # share a stroke id are one undo step; `reset?` starts a fresh report.
  defp paint_cells(socket, cells, stroke_id, reset?) do
    plane = socket.assigns.plane
    kind = socket.assigns.paint_kind

    {:ok, state, {outcome, report}} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        {next, outcome, report} =
          Editor.paint_type(current, plane, cells, kind, stroke: stroke_id)

        {next, {outcome, report}}
      end)

    socket = assign_state(socket, state)

    case outcome do
      {:applied, _entry, parts} ->
        socket
        |> push_layer_parts(plane, parts)
        |> note_paint(
          report,
          layer_changes(parts, :terrain),
          layer_changes(parts, :landmass),
          reset?
        )

      :none ->
        note_paint(socket, report, 0, 0, reset?)

      {:error, :out_of_ids} ->
        assign(socket, :paint_report, %{
          message: {:warn, "Too many separate landmasses for the save to number; nothing changed"}
        })
    end
  end

  defp layer_changes(parts, layer) do
    case Enum.find(parts, &(&1.layer == layer)) do
      nil -> 0
      %{changes: changes} -> length(changes)
    end
  end

  # Keeps a running report over a drag: tiles changed add up, skipped and
  # unresolved cells accumulate, and a stale neighbour drops out once a later step
  # re-tiles it.
  defp note_paint(socket, report, changed, landmass, reset?) do
    previous =
      case {reset?, socket.assigns.paint_report} do
        {false, %{changed: _} = prev} ->
          prev

        _ ->
          %{
            changed: 0,
            landmass: 0,
            skipped: MapSet.new(),
            unresolved: MapSet.new(),
            stale: MapSet.new()
          }
      end

    combined = %{
      changed: previous.changed + changed,
      landmass: previous.landmass + landmass,
      skipped: MapSet.union(previous.skipped, MapSet.new(report.skipped)),
      unresolved: MapSet.union(previous.unresolved, MapSet.new(report.unresolved)),
      stale: MapSet.union(previous.stale, MapSet.new(report.stale))
    }

    assign(
      socket,
      :paint_report,
      Map.put(
        combined,
        :message,
        PaintTool.summary(combined, combined.changed, combined.landmass)
      )
    )
  end

  defp push_layer_parts(socket, plane, parts) do
    Enum.reduce(parts, socket, fn %{layer: layer, updates: updates, changes: changes}, acc ->
      acc
      |> maybe_push_updates(layer, updates, changes)
      |> emit_engine_delta(plane, layer, changes)
    end)
  end

  # Cycle tool: step the tile's number by ±1 (wrapping 0..761). Each click
  # is its own one-tile stroke, so each click is one undo step.
  defp cycle_tile(socket, x, y, direction) do
    tiles = TerrainLbx.tiles_per_plane()

    case tile_value(socket.assigns.state, socket.assigns.plane, :terrain, x, y) do
      nil ->
        socket

      current ->
        value = Integer.mod(current + direction, tiles)

        socket
        |> start_stroke(:terrain, x, y, value)
        |> then(&finalize_stroke(&1, &1.assigns.active_stroke))
        |> assign_hover(x, y)
    end
  end

  defp start_stroke(socket, layer, x, y, value \\ nil) do
    plane = socket.assigns.plane

    {:ok, state, {stroke, change, updates}} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        val = value || Map.get(current.selection, layer, 0)

        {next_state, stroke, change, updates} =
          Editor.start_stroke(current, plane, layer, x, y, val)

        {next_state, {stroke, change, updates}}
      end)

    changes = change && [{x, y, elem(change, 0), elem(change, 1)}]

    socket =
      socket
      |> assign(:active_stroke, stroke)
      |> assign_state(state)
      |> maybe_push_updates(layer, updates, changes)

    if changes do
      emit_engine_delta(socket, plane, layer, changes)
    else
      socket
    end
  end

  defp apply_stroke_change(socket, layer, x, y) do
    plane = socket.assigns.plane
    active_stroke = socket.assigns.active_stroke

    {:ok, state, {stroke, change, updates}} =
      SessionStore.update(socket.assigns.session_id, fn current ->
        val = Map.get(current.selection, layer, 0)

        {next_state, stroke, change, updates} =
          Editor.apply_stroke_change(current, active_stroke, plane, layer, x, y, val)

        {next_state, {stroke, change, updates}}
      end)

    changes = change && [{x, y, elem(change, 0), elem(change, 1)}]

    socket =
      socket
      |> assign(:active_stroke, stroke)
      |> assign_state(state)
      |> maybe_push_updates(layer, updates, changes)

    if changes do
      emit_engine_delta(socket, plane, layer, changes)
    else
      socket
    end
  end

  # The stroke is already in the undo history (Editor records it incrementally),
  # so finishing just closes it.
  defp finalize_stroke(socket, _stroke) do
    socket
    |> assign(:active_stroke, nil)
    |> assign_state(socket.assigns.state)
    |> refresh_hover()
    |> push_map_layers()
  end

  # Cheap state update (no re-encoding of layers) that keeps the
  # unsaved-edits counter honest.
  defp assign_state(socket, state) do
    assign(socket, state: state, changed_tiles: changed_tile_count(state))
  end

  defp sample_tile(socket, layer, x, y) do
    plane = socket.assigns.plane

    case tile_value(socket.assigns.state, plane, layer, x, y) do
      nil ->
        socket

      value ->
        {:ok, state} =
          SessionStore.update(socket.assigns.session_id, fn current ->
            selection = Map.put(current.selection, layer, value)
            %{current | selection: selection}
          end)

        socket
        |> assign_from_state(state)
        |> assign_forms()
    end
  end

  defp apply_undo(socket), do: apply_history_step(socket, &Editor.undo/2)

  defp apply_redo(socket), do: apply_history_step(socket, &Editor.redo/2)

  # An undo or redo step may cover several layers (terrain and landmass for a
  # painted type); each layer's updates go to the client and the engine.
  defp apply_history_step(socket, step) do
    plane = socket.assigns.plane

    case SessionStore.update(socket.assigns.session_id, fn current -> step.(current, plane) end) do
      {:ok, state, {:applied, updates, layer, changes}} ->
        finish_history_step(socket, state, plane, [
          %{layer: layer, updates: updates, changes: changes}
        ])

      {:ok, state, {:applied, updates, layer, changes, extras}} ->
        parts = [%{layer: layer, updates: updates, changes: changes} | extras]
        finish_history_step(socket, state, plane, parts)

      {:ok, _state, :none} ->
        socket
    end
  end

  defp finish_history_step(socket, state, plane, parts) do
    socket
    |> assign_state(state)
    |> push_layer_parts(plane, parts)
    |> refresh_hover()
    |> push_map_layers()
  end

  defp tile_value(state, plane, layer, x, y), do: Editor.tile_value(state, plane, layer, x, y)

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

    layer_visibility = effective_layer_visibility(socket, state)
    layer_opacity = Map.get(state, :layer_opacity, SaveManager.default_layer_opacity())

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
      render_mode: effective_render_mode(socket, state),
      phase_index: effective_phase,
      phase_input: phase_input,
      phase_loop_len: loop_len,
      phase_loop_status: phase_loop_status,
      phase_loop_detecting: Map.get(state, :phase_loop_detecting, false),
      snapshot_mode: Map.get(state, :snapshot_mode, true),
      engine_session_id: Map.get(state, :engine_session_id),
      changed_tiles: changed_tile_count(state),
      brush: Map.get(state.selection, :terrain, 0)
    )
  end

  defp assign_forms(socket) do
    state = socket.assigns.state

    load_form = to_form(%{"path" => socket.assigns.load_path || ""}, as: :load)

    save_input = socket.assigns.save_path_input || state.save_path || ""

    # In edit mode, never offer the loaded file itself: suggest the next free
    # SAVEn.GAM slot beside it (MoM only loads SAVE1..SAVE9.GAM).
    save_input =
      with true <- socket.assigns[:edit] != nil,
           %SaveFile{path: original} when is_binary(original) <- state.save,
           true <- save_input in ["", original] do
        SaveManager.suggested_save_path(original)
      else
        _ -> save_input
      end

    save_form = to_form(%{"path" => save_input}, as: :save)

    selection_form =
      to_form(%{"value" => Map.get(state.selection, state.active_layer, 0)}, as: :selection)

    phase_form = to_form(%{"index" => state.phase_index || 0}, as: :phase)
    brush_form = to_form(%{"tile" => Map.get(state.selection, :terrain, 0)}, as: :brush)

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
      brush_form: brush_form,
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
        # The session's planes are authoritative and updated synchronously;
        # the engine mirrors them via async deltas, so it can lag an edit.
        terrain_value = MirrorMap.get_tile_u16_le(plane_layers.terrain, x, y)
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
          engine_tile: engine_tile,
          city: city_at(state, plane, x, y),
          survey: survey(state, plane, x, y)
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
      {:ok, updated_state} =
        SessionStore.update(socket.assigns.session_id, fn current ->
          snapshot_values = Map.put(current.snapshot_values, {plane, layer}, value)
          %{current | snapshot_values: snapshot_values}
        end)

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
    plane = socket.assigns.plane

    case SessionStore.update(socket.assigns.session_id, fn current ->
           Editor.apply_single_tile(current, plane, layer, x, y, value)
         end) do
      {:ok, _state, :none} ->
        socket

      {:ok, updated_state, {:applied, stroke, updates}} ->
        socket
        |> assign_state(updated_state)
        |> maybe_push_updates(layer, updates, stroke.changes)
        |> emit_engine_delta(plane, layer, stroke.changes)
        |> assign_hover(x, y)
        |> push_map_layers()
    end
  end

  defp push_map_state(socket) do
    state = socket.assigns.state

    layer_visibility = effective_layer_visibility(socket, state)
    layer_opacity = Map.get(state, :layer_opacity, SaveManager.default_layer_opacity())

    push_event(socket, "map_state", %{
      layer: Atom.to_string(state.active_layer),
      layer_type: layer_type(state.active_layer),
      render_mode: Atom.to_string(effective_render_mode(socket, state)),
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

    layer_visibility = effective_layer_visibility(socket, state)
    layer_opacity = Map.get(state, :layer_opacity, SaveManager.default_layer_opacity())

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
      render_mode: Atom.to_string(effective_render_mode(socket, state)),
      phase_index: effective_phase_index(state),
      snapshot_mode: Map.get(state, :snapshot_mode, true),
      layer_visibility: stringify_layer_map(layer_visibility),
      layer_opacity: stringify_layer_map(layer_opacity)
    })
  end

  # Send changed tiles to the canvas. Any layer is fine: the client stores
  # every layer and only redraws what's visible. (This used to drop the
  # `push_event` result, so no live update ever reached the canvas:
  # STORY-023.)
  defp maybe_push_updates(socket, layer, updates, changes) do
    if connected?(socket) and updates != [] do
      payload_changes =
        if is_list(changes) do
          Enum.map(changes, fn {x, y, prev, new} ->
            %{x: x, y: y, value: new, prev: prev, new: new}
          end)
        else
          updates
        end

      socket =
        push_event(socket, "engine_delta", %{
          plane: Atom.to_string(socket.assigns.plane),
          layer: Atom.to_string(layer),
          layer_type: layer_type(layer),
          delta_type: "tile_set",
          changes: payload_changes
        })

      maybe_push_adj_updates(socket, layer, payload_changes)
    else
      socket
    end
  end

  defp maybe_push_adj_updates(socket, :terrain, payload_changes) do
    plane = socket.assigns.plane

    case socket.assigns.state.planes do
      %{^plane => %{computed_adj_mask: computed_mask}} ->
        adj_coords =
          payload_changes
          |> Enum.flat_map(fn %{x: x, y: y} -> MirrorMap.adj_update_coords(x, y) end)
          |> Enum.uniq()

        adj_changes =
          Enum.map(adj_coords, fn {cx, cy} ->
            val = MirrorMap.get_tile_u8(computed_mask, cx, cy)
            %{x: cx, y: cy, value: val, new: val}
          end)

        if adj_changes != [] do
          push_event(socket, "engine_delta", %{
            plane: Atom.to_string(plane),
            layer: "computed_adj_mask",
            layer_type: "u8",
            delta_type: "tile_set",
            changes: adj_changes
          })
        else
          socket
        end

      _ ->
        socket
    end
  end

  defp maybe_push_adj_updates(socket, _layer, _changes), do: socket

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

  defp maybe_push_tile_assets(socket) do
    state = socket.assigns.state

    if connected?(socket) and effective_render_mode(socket, state) == :tiles do
      socket |> push_tile_assets(state) |> push_overlays()
    else
      socket
    end
  end

  defp push_tile_assets(socket, _state) do
    {socket, clear_cache?} =
      case socket.assigns.tile_assets do
        nil -> {assign(socket, :tile_assets, TileAtlas.build()), true}
        _ -> {socket, false}
      end

    case socket.assigns.tile_assets do
      nil ->
        socket

      atlas ->
        push_event(socket, "tile_assets", %{
          backend: Atom.to_string(atlas.backend),
          terrain_lbx: atlas.terrain_lbx,
          clear_cache: clear_cache?
        })
    end
  end

  # Overlay layers on the map pages (STORY-009): the sprites once, then each
  # layer's items for this plane. The Lab has no overlays.
  defp push_overlays(%{assigns: %{lab?: true}} = socket), do: socket

  defp push_overlays(socket) do
    socket =
      case OverlaySprites.load(Paths.mom_path()) do
        {:ok, sprites} -> push_event(socket, "overlay_sprites", sprites)
        {:error, _} -> socket
      end

    socket
    |> push_event("overlay_data", %{
      layer: "sites",
      items: site_items(socket.assigns.state, socket.assigns.plane)
    })
    |> push_event("overlay_data", %{
      layer: "cities",
      items: city_items(socket.assigns.state, socket.assigns.plane)
    })
    |> push_event("overlay_data", %{
      layer: "units",
      items: unit_items(socket.assigns.state, socket.assigns.plane)
    })
    |> push_map_layers()
  end

  # The overlays computed from the map itself, pushed again after every
  # edit: where a city could go (STORY-035), roads, specials and corruption
  # (STORY-013), and the player's fog (STORY-036).
  defp push_map_layers(%{assigns: %{lab?: true}} = socket), do: socket

  defp push_map_layers(socket) do
    %{state: state, plane: plane} = socket.assigns

    socket
    |> push_event("overlay_data", %{layer: "settleable", items: settleable_items(state, plane)})
    |> push_event("overlay_data", %{layer: "roads", items: road_items(state, plane)})
    |> push_event("overlay_data", %{layer: "fog", items: fog_items(state, plane)})
  end

  defp road_items(%{save: %{}, planes: planes}, plane) do
    with {:ok, plane_layers} <- Map.fetch(planes, plane),
         {:ok, flags} <- Map.fetch(plane_layers, :terrain_flags),
         {:ok, minerals} <- Map.fetch(plane_layers, :minerals) do
      Roads.items(flags, minerals)
    else
      _ -> []
    end
  end

  defp road_items(_state, _plane), do: []

  defp settleable_items(%{save: %{raw: raw}, planes: planes}, plane) do
    with {:ok, cities} <- Cities.parse(raw),
         {:ok, sites} <- Sites.parse(raw) do
      Surveyor.settleable(planes, cities, sites, plane)
    else
      _ -> []
    end
  end

  defp settleable_items(_state, _plane), do: []

  # Unexplored (0) and partly explored (1-14) tiles; 15 is fully explored.
  defp fog_items(%{save: %{}, planes: planes}, plane) do
    exploration = planes |> Map.fetch!(plane) |> Map.fetch!(:exploration)

    for {explored, i} <- Enum.with_index(:binary.bin_to_list(exploration)),
        explored < 15,
        do: %{x: rem(i, 60), y: div(i, 60), explored: explored}
  end

  defp fog_items(_state, _plane), do: []

  defp site_items(%{save: %{raw: raw}}, plane) do
    case Sites.parse(raw) do
      {:ok, %{towers: towers, encounters: encounters}} ->
        tower_items =
          for tower <- towers do
            %{
              x: tower.x,
              y: tower.y,
              sprite: if(tower.owner, do: "tower_owned", else: "tower_unowned")
            }
          end

        encounter_items =
          for encounter <- encounters, encounter.plane == plane, encounter.intact do
            sprite =
              case encounter.kind do
                4 -> "mound"
                8 -> "mound"
                5 -> "ruins"
                9 -> "ruins"
                6 -> "ancient_temple"
                7 -> "abandoned_keep"
                10 -> "fallen_temple"
                _ -> nil
              end

            if sprite do
              %{
                x: encounter.x,
                y: encounter.y,
                sprite: sprite
              }
            end
          end
          |> Enum.reject(&is_nil/1)

        tower_items ++ encounter_items

      {:error, _} ->
        []
    end
  end

  defp site_items(_state, _plane), do: []

  defp city_items(%{save: %{raw: raw}}, plane) do
    banners = Wizards.banners(raw)

    case Cities.parse(raw) do
      {:ok, cities} ->
        for %{plane: ^plane} = city <- cities do
          %{
            x: city.x,
            y: city.y,
            frame: min(4, div(max(0, city.population - 1), 4)),
            banner: Map.get(banners, city.owner, :neutral),
            name: city.name,
            walled: city.walled
          }
        end

      {:error, _} ->
        []
    end
  end

  defp city_items(_state, _plane), do: []

  defp unit_items(%{save: %{raw: raw}}, plane) do
    banners = Wizards.banners(raw)

    for unit <- Units.items(raw, plane) do
      %{
        x: unit.x,
        y: unit.y,
        type: unit.type,
        banner: Map.get(banners, unit.owner, :neutral)
      }
    end
  end

  defp unit_items(_state, _plane), do: []

  # The Surveyor panel, from the session's planes so it follows edits.
  defp survey(%{save: %{raw: raw}, planes: planes}, plane, x, y) do
    with {:ok, cities} <- Cities.parse(raw),
         {:ok, sites} <- Sites.parse(raw) do
      Surveyor.panel(planes, cities, sites, x, y, plane)
    else
      _ -> nil
    end
  end

  defp city_at(%{save: %{raw: raw}}, plane, x, y) do
    case Cities.parse(raw) do
      {:ok, cities} -> Enum.find(cities, &match?(%{plane: ^plane, x: ^x, y: ^y}, &1))
      {:error, _} -> nil
    end
  end

  # The map pages always show terrain art with no research overlays; the
  # Lab uses whatever the session has.
  defp effective_render_mode(socket, state) do
    if socket.assigns[:lab?], do: state.render_mode, else: :tiles
  end

  defp effective_layer_visibility(socket, state) do
    if socket.assigns[:lab?] do
      Map.get(state, :layer_visibility, SaveManager.default_layer_visibility(state.active_layer))
    else
      Map.new(@layers, &{&1, &1 == :terrain})
    end
  end

  defp pointer_allowed?(socket, action) do
    cond do
      socket.assigns.lab? -> true
      action == "hover" -> true
      socket.assigns.edit -> action in ["start", "drag", "end"]
      true -> false
    end
  end

  defp push_brush(socket) do
    push_event(socket, "brush", %{tile: Map.get(socket.assigns.state.selection, :terrain, 0)})
  end

  defp changed_tile_count(state), do: Editor.changed_tile_count(state)

  defp edit_path(:arcanus), do: ~p"/arcanus?edit=terrain"
  defp edit_path(:myrror), do: ~p"/myrror?edit=terrain"

  defp parse_plane("myrror"), do: :myrror
  defp parse_plane(_), do: :arcanus

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

  defp original_tile_value(state, plane, layer, x, y),
    do: Editor.original_tile_value(state, plane, layer, x, y)

  defp tool_and_layer(socket, button, mods) do
    layer = if socket.assigns.edit, do: :terrain, else: socket.assigns.state.active_layer

    tool =
      cond do
        button == 2 -> :sample
        truthy?(mods["ctrl"]) -> :sample
        true -> :paint
      end

    {tool, layer}
  end

  defp valid_coord?(x, y), do: Editor.valid_coord?(x, y)

  defp clamp_value(layer, value), do: Editor.clamp_value(layer, value)

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
