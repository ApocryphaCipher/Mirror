defmodule Mirror.SaveBlockDiff do
  @moduledoc """
  Given two raw save binaries of equal size, return which named blocks differ
  and exactly which byte offsets within each.
  """

  alias Mirror.SaveFile.Blocks
  alias Mirror.SaveFile.Cities
  alias Mirror.SaveFile.Units
  alias Mirror.SaveFile.Wizards
  alias Mirror.SaveFile.Sites

  @doc """
  Diffs two binaries of equal size and returns a map of changed blocks to byte offsets.
  Keys are only present for blocks with at least one differing byte.
  """
  @spec diff(binary(), binary()) :: %{term() => [non_neg_integer()]}
  def diff(before_binary, after_binary)
      when byte_size(before_binary) == byte_size(after_binary) do
    diff_offsets =
      for i <- 0..(byte_size(before_binary) - 1)//1,
          :binary.at(before_binary, i) != :binary.at(after_binary, i),
          do: i

    if diff_offsets == [] do
      %{}
    else
      ranges = named_ranges()

      diff_offsets
      |> Enum.group_by(fn offset ->
        case Enum.find(ranges, fn {_name, start, size} ->
               offset >= start and offset < start + size
             end) do
          {name, _start, _size} -> name
          nil -> :other
        end
      end)
    end
  end

  defp named_ranges do
    plane_layers =
      for layer <- Blocks.layers(), plane <- [:arcanus, :myrror] do
        plane_index = if plane == :arcanus, do: 0, else: 1
        {:ok, offset} = Blocks.plane_slice_offset(layer, plane_index)
        {{layer, plane}, offset, Blocks.layer_size(layer)}
      end

    other_ranges = [
      {:cities_count, Cities.count_offset(), 2},
      {:cities_records, elem(Cities.block_range(), 0), elem(Cities.block_range(), 1)},
      {:units_count, Units.count_offset(), 2},
      {:units_records, elem(Units.block_range(), 0), elem(Units.block_range(), 1)},
      {:wizards, elem(Wizards.block_range(), 0), elem(Wizards.block_range(), 1)},
      {:sites_nodes, elem(Sites.nodes_range(), 0), elem(Sites.nodes_range(), 1)},
      {:sites_towers, elem(Sites.towers_range(), 0), elem(Sites.towers_range(), 1)},
      {:sites_encounters, elem(Sites.encounters_range(), 0), elem(Sites.encounters_range(), 1)}
    ]

    plane_layers ++ other_ranges
  end
end
