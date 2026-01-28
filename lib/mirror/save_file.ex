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

  def write(%__MODULE__{} = save, path \\ nil, opts \\ []) do
    target = path || save.path
    backup? = Keyword.get(opts, :backup, true)

    with :ok <- maybe_backup(save.path, target, backup?),
         {:ok, binary} <- serialize(save),
         :ok <- File.write(target, binary) do
      {:ok, target}
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

  defp maybe_backup(source_path, target_path, true) do
    backup_path = target_path <> ".bak"

    cond do
      File.exists?(backup_path) ->
        :ok

      source_path != target_path and File.exists?(source_path) ->
        File.cp(source_path, backup_path)

      File.exists?(target_path) ->
        File.cp(target_path, backup_path)

      true ->
        :ok
    end
  end

  defp maybe_backup(_source_path, _target_path, false), do: :ok
end
