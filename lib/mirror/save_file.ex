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

  @doc """
  Reads and decodes a save file from disk. (Mirror itself gets saves as bytes from the browser,
  `from_binary/2`; this is for tests, scripts and the engine's own loader.)
  """
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

  @doc """
  Decodes a save that arrived as bytes (EPIC-012: the browser reads the file from the
  user's game folder). `name` is only a label (`"SAVE3.GAM"`): nothing is read from or
  written to the server's disk. Bad bytes give `{:error, reason}`, never a raise.
  """
  def from_binary(raw, name) when is_binary(raw) and is_binary(name) do
    with {:ok, planes} <- decode_planes(raw) do
      {:ok,
       %__MODULE__{
         path: name,
         raw: raw,
         planes: planes,
         dataset_id: {:mom_classic, "#{byte_size(raw)}-#{:erlang.phash2(raw)}"},
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
