defmodule Mirror.SaveManager do
  @moduledoc """
  Coordinates save file loading, writing, overwrite protection, engine session lifecycle,
  and initial editor state normalization.
  """

  alias Mirror.Editor
  alias Mirror.Engine.{Session, SessionSupervisor}
  alias Mirror.{Paths, SaveFile, SessionStore, Stats}

  @doc "Normalizes a user-entered save path by trimming whitespace and surrounding quotes."
  def normalize_path(nil), do: ""

  def normalize_path(path) when is_binary(path) do
    trimmed =
      path
      |> String.trim()
      |> String.trim("\"")
      |> String.trim("'")

    case trimmed do
      "" -> ""
      _ -> Path.expand(trimmed)
    end
  end

  def normalize_path(_), do: ""

  @doc "Default path to propose when loading, using MIRROR_MOM_PATH/SAVE1.GAM if set."
  def default_load_path do
    case Paths.mom_path() do
      nil -> ""
      "" -> ""
      path -> Path.join(path, "SAVE1.GAM")
    end
  end

  @doc "Suggests the next free SAVEn.GAM slot beside the loaded file."
  def suggested_save_path(original) when is_binary(original) do
    case SaveFile.next_free_slot(Path.dirname(original)) do
      {:ok, path} -> path
      :none -> ""
    end
  end

  def suggested_save_path(_), do: ""

  @doc "User-facing message after a successful save."
  def saved_message(path) do
    if SaveFile.game_loadable_name?(path) do
      "Saved to #{path}."
    else
      "Saved to #{path}. The game only loads SAVE1.GAM to SAVE9.GAM, so rename it to play it."
    end
  end

  @doc "User-facing message for load errors."
  def load_error_message({:missing_offset, layer}, _path) do
    "Missing block offset for #{layer}. Set config before loading."
  end

  def load_error_message(:enoent, path) when path in [nil, ""] do
    "Provide a save path before loading."
  end

  def load_error_message(:enoent, path) do
    "Save file not found at #{path}. Check the path."
  end

  def load_error_message(reason, _path) do
    "Unable to load save: #{inspect(reason)}"
  end

  @doc "User-facing message for save errors."
  def save_error_message(:no_save) do
    "Load a save before saving."
  end

  def save_error_message(:would_overwrite_original) do
    "Choose a new file name: Save as won't overwrite the file you loaded."
  end

  def save_error_message(reason) do
    "Save failed: #{inspect(reason)}"
  end

  @doc """
  Loads a save file from `path`, terminates any previous engine session in `current_state`,
  builds normalized planes with computed layers, starts a new engine session, and initializes
  research statistics.

  Returns `{:ok, state, normalized_path}` or `{:error, reason}`.
  """
  def load(path, current_state \\ nil) do
    normalized = normalize_path(path)

    case SaveFile.load(normalized) do
      {:ok, save} ->
        if current_state, do: stop_engine_session(Map.get(current_state, :engine_session_id))
        planes = Editor.with_computed_layers(save.planes)

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
          render_mode: (current_state && Map.get(current_state, :render_mode)) || :tiles,
          phase_index: (current_state && Map.get(current_state, :phase_index)) || 0,
          snapshot_mode: Map.get(current_state || %{}, :snapshot_mode, true),
          snapshot_values: %{},
          phase_loop_len: Map.get(current_state || %{}, :phase_loop_len),
          phase_loop_status:
            normalize_phase_loop_status(
              Map.get(current_state || %{}, :phase_loop_status, :unknown)
            ),
          phase_loop_detecting: false,
          engine_session_id: nil,
          engine_player_id: Map.get(current_state || %{}, :engine_player_id, :observer)
        }

        state =
          case start_engine_session(normalized) do
            {:ok, engine_session_id} -> %{state | engine_session_id: engine_session_id}
            {:error, _reason} -> state
          end

        state = normalize_state(state)
        observe_stats(state)

        {:ok, state, normalized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Saves the current editor state to `target_path` (or `state.save_path`).
  Universal overwrite protection prevents overwriting the loaded file.

  Returns `{:ok, updated_state, saved_path}` or `{:error, reason}`.
  """
  def save(state, requested_path \\ nil) do
    path = normalize_path(requested_path)
    target_path = if path == "", do: nil, else: path

    case state.save do
      %SaveFile{} = save ->
        saved_planes = Editor.strip_computed(state.planes)

        case SaveFile.write(%{save | planes: saved_planes}, target_path || state.save_path) do
          {:ok, save_path} ->
            save = %{save | path: save_path, planes: saved_planes}

            updated_state = %{
              state
              | save: save,
                save_path: save_path,
                original_planes: saved_planes
            }

            {:ok, updated_state, save_path}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :no_save}
    end
  end

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

        case start_engine_session(state.save.path) do
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

  @doc "Starts a new engine session for a save struct or file path."
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

  def start_engine_session(path) when is_binary(path) and path != "" do
    case SessionSupervisor.start_session(seed: System.unique_integer([:positive])) do
      {:ok, pid} ->
        case Session.load_save(pid, path) do
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

  def start_engine_session(_path), do: {:error, :missing_path}

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
