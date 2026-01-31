defmodule Mirror.ShoreMaskDiscoveryTest do
  use ExUnit.Case, async: true

  import Bitwise

  @moduletag :discovery

  @resource_map_path Path.expand(
                       "../../resources/momime.client.graphics/overland/resources-map.txt",
                       __DIR__
                     )

  test "generated shore masks exist in momime resources (arcanus)" do
    missing = missing_masks_for_plane("arcanus")

    assert MapSet.size(missing) == 0,
           "missing arcanus shore masks: #{inspect(Enum.sort(MapSet.to_list(missing)))}"
  end

  test "generated shore masks exist in momime resources (myrror)" do
    missing = missing_masks_for_plane("myrror")

    assert MapSet.size(missing) == 0,
           "missing myrror shore masks: #{inspect(Enum.sort(MapSet.to_list(missing)))}"
  end

  test "momime resources do not include unreachable shore masks (arcanus)" do
    unreachable = unreachable_masks_for_plane("arcanus")

    assert MapSet.size(unreachable) == 0,
           "unreachable arcanus shore masks: #{inspect(Enum.sort(MapSet.to_list(unreachable)))}"
  end

  test "momime resources do not include unreachable shore masks (myrror)" do
    unreachable = unreachable_masks_for_plane("myrror")

    assert MapSet.size(unreachable) == 0,
           "unreachable myrror shore masks: #{inspect(Enum.sort(MapSet.to_list(unreachable)))}"
  end

  defp missing_masks_for_plane(plane) do
    generated = generated_shore_masks()
    available = shore_masks_from_resources(plane)
    MapSet.difference(generated, available)
  end

  defp unreachable_masks_for_plane(plane) do
    generated = generated_shore_masks()
    available = shore_masks_from_resources(plane)
    MapSet.difference(available, generated)
  end

  defp shore_masks_from_resources(plane) do
    regex = ~r/^terrain\\#{plane}\\shore\\(?<mask>\d{8})(?:-frame\d+)?\.png$/i

    @resource_map_path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Enum.reduce(MapSet.new(), fn line, acc ->
      case Regex.named_captures(regex, line) do
        %{"mask" => mask} -> MapSet.put(acc, mask)
        _ -> acc
      end
    end)
  end

  defp generated_shore_masks do
    Enum.reduce(0..255, MapSet.new(), fn bitset, acc ->
      MapSet.put(acc, shore_mask_from_bitset(bitset))
    end)
  end

  defp shore_mask_from_bitset(bitset) do
    land = for i <- 0..7, do: (bitset &&& (1 <<< i)) != 0

    digits =
      Enum.with_index(land)
      |> Enum.map(fn {is_land, idx} ->
        if rem(idx, 2) == 0 do
          if is_land, do: "1", else: "0"
        else
          left = Enum.at(land, rem(idx + 7, 8))
          right = Enum.at(land, rem(idx + 1, 8))

          cond do
            left && right -> "1"
            is_land -> "2"
            true -> "0"
          end
        end
      end)

    Enum.join(digits)
  end
end
