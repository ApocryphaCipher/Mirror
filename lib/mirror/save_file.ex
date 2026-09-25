defmodule Mirror.SaveFile do
  @moduledoc """
  Load, decode, and serialize Classic save files.
  """

  alias Mirror.SaveFile.Blocks

  defstruct [
    :path,
    :raw,
    :planes,
    :dataset_id,
    :loaded_at
  ]

  @type plane_key :: :arcanus | :myrror

  @type t :: %__MODULE__{
          path: String.t(),
          raw: binary(),
          planes: %{plane_key() => map()},
          dataset_id: term(),
          loaded_at: DateTime.t()
        }

  # The game only loads these (STORY-038).
  @slot_names for(n <- 1..9, do: "SAVE#{n}.GAM")

  @doc """
  Returns `{:ok, path}` where `path` is `dir`/`SAVEn.GAM` for the
  lowest `n` in 1..9 whose file does not already exist in `dir`
  (comparison is case-insensitive).

  Returns `:none` when all nine slots are occupied.
  A missing or unreadable directory is treated as empty.
  This function never raises.
  """
  def next_free_slot(dir) do
    taken =
      dir
      |> File.ls()
      |> then(fn
        {:ok, files} -> files
        _ -> []
      end)
      |> MapSet.new(&String.upcase/1)

    case Enum.find(1..9, &(not MapSet.member?(taken, "SAVE#{&1}.GAM"))) do
      nil -> :none
      n -> {:ok, Path.join(dir, "SAVE#{n}.GAM")}
    end
  end

  @doc """
  Returns `true` only when the basename of `path`, compared case-insensitively,
  is exactly one of `SAVE1.GAM` through `SAVE9.GAM`.

  Returns `false` for anything else (e.g. `"SAVE10.GAM"`, `"SAVE0.GAM"`,
  `"foo-edited.GAM"`, `"SAVE1.GAM.bak"`).
  """
  def game_loadable_name?(path) do
    String.upcase(Path.basename(path)) in @slot_names
  end

  def load(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, planes} <- decode_planes(raw),
         {:ok, dataset_id} <- Mirror.Stats.dataset_id_from_path(path) do
      {:ok,
       %__MODULE__{
         path: path,
         raw: raw,
         planes: planes,
         dataset_id: dataset_id,
         loaded_at: DateTime.utc_now()
       }}
    end
  end

  def serialize(%__MODULE__{} = save) do
    Enum.reduce_while(save.planes, {:ok, save.raw}, fn {plane_key, layers}, {:ok, acc} ->
      plane_index = plane_index(plane_key)

      result =
        Blocks.layers()
        |> Enum.reduce_while({:ok, acc}, fn layer, {:ok, binary} ->
          case Blocks.put_plane_slice(binary, layer, plane_index, Map.fetch!(layers, layer)) do
            {:ok, updated} -> {:cont, {:ok, updated}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case result do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Writes `save` to `target`, never to the file it was loaded from
  (AGENTS.md §9): that file is refused by path and by inode, so a symlink
  or different letter case can't get round it. An existing `target` is
  backed up to `target.bak` first (unless one exists, or `backup: false`),
  and the write is atomic: a temporary file in the same folder, renamed
  over `target`.
  """
  def write(%__MODULE__{} = save, target, opts \\ []) do
    with :ok <- validate_target(target),
         :ok <- check_not_original(save, target),
         :ok <- maybe_backup(target, opts),
         {:ok, binary} <- serialize(save),
         :ok <- atomic_write(target, binary) do
      {:ok, target}
    end
  end

  defp validate_target(nil), do: {:error, :no_destination}
  defp validate_target(""), do: {:error, :no_destination}
  defp validate_target(_target), do: :ok

  defp check_not_original(save, target) do
    source = save.path

    if is_nil(source) do
      :ok
    else
      expanded_source = Path.expand(source)
      expanded_target = Path.expand(target)

      cond do
        expanded_source == expanded_target ->
          {:error, :would_overwrite_original}

        true ->
          with {:ok, s_stat} <- File.stat(source),
               {:ok, t_stat} <- File.stat(target) do
            if s_stat.inode == t_stat.inode and s_stat.major_device == t_stat.major_device do
              {:error, :would_overwrite_original}
            else
              :ok
            end
          else
            _ -> :ok
          end
      end
    end
  end

  defp maybe_backup(target, opts) do
    if Keyword.get(opts, :backup, true) and File.exists?(target) do
      backup_path = target <> ".bak"

      if File.exists?(backup_path) do
        :ok
      else
        File.cp(target, backup_path)
      end
    else
      :ok
    end
  end

  defp atomic_write(target, binary) do
    tmp = target <> ".tmp-" <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- File.write(tmp, binary),
         :ok <- File.rename(tmp, target) do
      :ok
    else
      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  defp decode_planes(raw) do
    with {:ok, arcanus} <- decode_plane(raw, 0),
         {:ok, myrror} <- decode_plane(raw, 1) do
      {:ok, %{arcanus: arcanus, myrror: myrror}}
    end
  end

  defp decode_plane(raw, plane_index) do
    Blocks.layers()
    |> Enum.reduce_while({:ok, %{}}, fn layer, {:ok, acc} ->
      case Blocks.slice_plane(raw, layer, plane_index) do
        {:ok, slice} -> {:cont, {:ok, Map.put(acc, layer, slice)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp plane_index(:arcanus), do: 0
  defp plane_index(:myrror), do: 1
end
