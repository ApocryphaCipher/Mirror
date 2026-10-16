defmodule Mirror.SaveManager do
  @moduledoc """
  Coordinates opening a save (from the bytes the browser sends, `load_bytes/3`), the bytes to write
  back (`slot_bytes/1`, `mark_saved/3`), the engine session lifecycle, and initial editor state
  normalization. Where a save is read from and written to is the browser's business
  (`MirrorWeb.SaveSlots`); nothing here touches the server's disk for a save.
  """

  alias Mirror.Editor
  alias Mirror.Engine.{Session, SessionSupervisor}
  alias Mirror.{SaveFile, SessionStore, Stats}

  @doc """
  Opens a save that arrived as bytes from a slot button (EPIC-012), ending any engine session of
  `current_state` and starting a new one. `name` is the label shown for it (`"SAVE3.GAM"`).
  Returns `{:ok, state, name}` or `{:error, reason}`: bad bytes are an error, never a raise.
  """
  def load_bytes(raw, name, current_state \\ nil) do
    case SaveFile.from_binary(raw, name) do
      {:ok, save} -> {:ok, build_state(save, current_state), name}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_state(%SaveFile{} = save, current_state) do
    if current_state, do: stop_engine_session(Map.get(current_state, :engine_session_id))
    planes = Editor.with_computed_layers(save.planes)

    state = %{
      save: save,
      planes: planes,
      original_planes: save.planes,
      original_raw: save.raw,
      active_layer: :terrain,
      selection: default_selection(),
      history: %{arcanus: [], myrror: []},
      redo: %{arcanus: [], myrror: []},
      save_path: save.path,
      dataset_id: save.dataset_id,
      render_mode: (current_state && Map.get(current_state, :render_mode)) || :tiles,
      phase_index: (current_state && Map.get(current_state, :phase_index)) || 0,
      snapshot_mode: Map.get(current_state || %{}, :snapshot_mode, true),
      snapshot_values: %{},
      phase_loop_len: Map.get(current_state || %{}, :phase_loop_len),
      phase_loop_status:
        normalize_phase_loop_status(Map.get(current_state || %{}, :phase_loop_status, :unknown)),
      phase_loop_detecting: false,
      engine_session_id: nil,
      engine_player_id: Map.get(current_state || %{}, :engine_player_id, :observer)
    }

    state =
      case start_engine_session(save) do
        {:ok, engine_session_id} -> %{state | engine_session_id: engine_session_id}
        {:error, _reason} -> state
      end

    state = normalize_state(state)
    observe_stats(state)
    state
  end

  @doc """
  The bytes of the save as it is now, with the edits in it, for the browser to write into
  a slot. `{:error, :no_save}` when nothing is loaded.
  """
  def slot_bytes(%{save: %SaveFile{} = save, planes: planes}) do
    SaveFile.serialize(%{save | planes: Editor.strip_computed(planes)})
  end

  def slot_bytes(_state), do: {:error, :no_save}

  @doc """
  Marks the edits as saved after the browser wrote `bytes` into `name` (`"SAVE3.GAM"`):
  the unsaved count goes back to zero. If the state changed since `bytes` were made, it
  is returned unchanged, so an edit made in between still counts as unsaved.
  """
  def mark_saved(%{save: %SaveFile{} = save} = state, name, bytes) do
    case slot_bytes(state) do
      {:ok, ^bytes} ->
        saved_planes = Editor.strip_computed(state.planes)
        save = %{save | path: name, raw: bytes, planes: saved_planes}

        Map.merge(state, %{
          save: save,
          save_path: name,
          original_planes: saved_planes,
          original_raw: bytes,
          record_mark: System.unique_integer([:positive, :monotonic])
        })

      _ ->
        state
    end
  end

  def mark_saved(state, _name, _bytes), do: state

  @doc "How many edits are not in the save yet (terrain tiles and records)."
  def unsaved_count(state),
    do: Editor.changed_tile_count(state) + Editor.changed_record_count(state)

  @doc "Restarts the engine session using the restored save file after a discard."
  def restore_engine_session(state, %SaveFile{} = restored_save) do
    stop_engine_session(Map.get(state, :engine_session_id))

    case start_engine_session(restored_save) do
      {:ok, engine_session_id} -> %{state | engine_session_id: engine_session_id}
      {:error, _reason} -> %{state | engine_session_id: nil}
    end
  end

  def restore_engine_session(state, _other), do: state

  @doc "Ensures an engine session process is running for the loaded save when connected."
  def ensure_engine_session(state, session_id, connected?) do
    cond do
      not connected? ->
        state

      is_nil(state.save) ->
        state

      engine_session_alive?(Map.get(state, :engine_session_id)) ->
        state

      true ->
        stop_engine_session(Map.get(state, :engine_session_id))

        case start_engine_session(state.save) do
          {:ok, engine_session_id} ->
            {:ok, state} =
              SessionStore.update(session_id, fn current ->
                %{current | engine_session_id: engine_session_id}
              end)

            state

          {:error, _reason} ->
            state
        end
    end
  end

  @doc "Terminates an engine session process."
  def stop_engine_session(nil), do: :ok
  def stop_engine_session(session_id), do: Session.stop(session_id)

  @doc "Checks if an engine session process is alive."
  def engine_session_alive?(nil), do: false

  def engine_session_alive?(session_id) do
    case Session.whereis(session_id) do
      nil -> false
      _pid -> true
    end
  end

  @doc "Starts a new engine session for a save."
  def start_engine_session(%SaveFile{} = save) do
    case SessionSupervisor.start_session(seed: System.unique_integer([:positive])) do
      {:ok, pid} ->
        case Session.load_save(pid, save) do
          {:ok, session_id} ->
            {:ok, session_id}

          {:error, reason} ->
            SessionSupervisor.stop_session(pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Default selection mapping each layer to 0."
  def default_selection do
    Enum.into(Editor.layers(), %{}, fn layer -> {layer, 0} end)
  end

  @doc "Default layer visibility map."
  def default_layer_visibility(active_layer) do
    Enum.into(Editor.layers(), %{}, fn layer ->
      visible = layer == :terrain || layer == active_layer
      {layer, visible}
    end)
  end

  @doc "Default layer opacity map."
  def default_layer_opacity do
    Enum.into(Editor.layers(), %{}, fn layer ->
      {layer, if(layer == :terrain, do: 100, else: 70)}
    end)
  end

  @doc "Normalizes a layer visibility map, filling in defaults."
  def normalize_layer_visibility(active_layer, visibility) when is_map(visibility) do
    Enum.into(Editor.layers(), %{}, fn layer ->
      default_visible = layer == :terrain || layer == active_layer
      value = Map.get(visibility, layer, default_visible)
      {layer, if(layer == :terrain, do: true, else: value)}
    end)
  end

  def normalize_layer_visibility(active_layer, _visibility) do
    default_layer_visibility(active_layer)
  end

  @doc "Normalizes a layer opacity map, filling in defaults."
  def normalize_layer_opacity(opacity) when is_map(opacity) do
    defaults = default_layer_opacity()

    Enum.into(Editor.layers(), %{}, fn layer ->
      {layer, Map.get(opacity, layer, Map.fetch!(defaults, layer))}
    end)
  end

  def normalize_layer_opacity(_opacity), do: default_layer_opacity()

  @doc "Ensures the given layer and terrain are marked visible."
  def ensure_layer_visible(state, layer) do
    visibility =
      Map.get(state, :layer_visibility, default_layer_visibility(state.active_layer))

    visibility = visibility |> Map.put(:terrain, true) |> Map.put(layer, true)
    Map.put(state, :layer_visibility, visibility)
  end

  @doc "Normalizes phase loop detection status."
  def normalize_phase_loop_status(status) do
    case status do
      :detected -> :detected
      "detected" -> :detected
      :assumed -> :assumed
      "assumed" -> :assumed
      _ -> :unknown
    end
  end

  @doc "Initializes or normalizes an editor state map."
  def normalize_state(nil) do
    %{
      save: nil,
      planes: %{},
      original_planes: nil,
      original_raw: nil,
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
      debug_terrain_kinds: false,
      debug_coast_audit: false,
      debug_shore_semantics: false,
      layer_visibility: default_layer_visibility(:terrain),
      layer_opacity: default_layer_opacity(),
      engine_session_id: nil,
      engine_player_id: :observer
    }
  end

  def normalize_state(state) do
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
      |> Map.put_new(:original_raw, Map.get(state, :save) && Map.get(state.save, :raw))
      |> Map.put_new(:phase_loop_len, nil)
      |> Map.put_new(:phase_loop_status, :unknown)
      |> Map.update(:phase_loop_status, :unknown, &normalize_phase_loop_status/1)
      |> Map.put_new(:phase_loop_detecting, false)
      |> Map.put_new(:debug_terrain_kinds, false)
      |> Map.put_new(:debug_coast_audit, false)
      |> Map.put_new(:debug_shore_semantics, false)
      |> Map.put_new(:engine_session_id, nil)
      |> Map.put_new(:engine_player_id, :observer)

    visibility =
      normalize_layer_visibility(state.active_layer, Map.get(state, :layer_visibility))

    opacity = normalize_layer_opacity(Map.get(state, :layer_opacity))

    state
    |> Map.put(:layer_visibility, visibility)
    |> Map.put(:layer_opacity, opacity)
  end

  @doc "Registers initial histograms and ray observations for research datasets."
  def observe_stats(%{dataset_id: nil}), do: :ok

  def observe_stats(state) do
    Stats.ensure_dataset(state.dataset_id)

    u8_layers = Editor.u8_layers()
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

  defp histogram_from_binary(binary) when is_binary(binary) do
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
end
