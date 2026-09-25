defmodule Mirror.SaveFile.Sites do
  @moduledoc """
  Where the map's magic nodes, Towers of Wizardry and encounter sites
  (lairs, keeps, temples…) are, as much as the Surveyor needs: position,
  kind, and whether a site is still intact. The rest of these records is
  STORY-011's.

  Offsets are the save's own writes (docs/reference/save-to-ram-map.md):

    * nodes, 30 × 48 bytes at `0x6058`: `+0` x, `+1` y, `+2` plane,
      `+3` owner (−1 none; checked: 0 after Kevin melded one), `+0x2d`
      type (0 Sorcery, 1 Nature, 2 Chaos), `+0x2e` flags (1 warped,
      2 guardian spirit). Type and flags from ReMoM.
    * towers, 6 × 4 bytes at `0x6610`: `+0` x, `+1` y (a tower stands on
      both planes), `+2` owner. From ReMoM.
    * encounters, 102 × 24 bytes at `0x6628`: `+0` x, `+1` y, `+2` plane,
      `+3` intact, `+4` kind, `+15` flags. Position, intact and kinds 3, 4,
      6, 7 checked against the Surveyor (live-ram-map.md). *guess:* flag
      `0x02` = the site has been looked at, so its guards are named
      (ReMoM's Surveyor); every site checked so far had 0 and said
      "Unexplored".
  """

  @nodes {0x6058, 30, 48}
  @towers {0x6610, 6, 4}
  @encounters {0x6628, 102, 24}

  @node_types %{0 => :sorcery, 1 => :nature, 2 => :chaos}

  @type t :: %{nodes: [map()], towers: [map()], encounters: [map()]}

  @doc "The sites in a save's raw bytes."
  @spec parse(binary()) :: {:ok, t()} | {:error, :no_sites_block}
  def parse(raw) do
    {offset, count, size} = @encounters

    if byte_size(raw) >= offset + count * size do
      {:ok,
       %{
         nodes: records(raw, @nodes, &magic_node/1),
         towers: records(raw, @towers, &tower/1),
         encounters: records(raw, @encounters, &encounter/1)
       }}
    else
      {:error, :no_sites_block}
    end
  end

  defp records(raw, {offset, count, size}, decode) do
    for i <- 0..(count - 1),
        site = decode.(binary_part(raw, offset + i * size, size)),
        do: site
  end

  defp magic_node(<<x, y, plane, owner::signed, _::binary-size(41), type, flags, _pad>>)
       when x < 60 and y < 40 and plane in [0, 1] do
    %{
      x: x,
      y: y,
      plane: plane(plane),
      type: Map.get(@node_types, type, :unknown),
      owner: if(owner < 0, do: nil, else: owner),
      warped: Bitwise.band(flags, 1) != 0,
      guardian: Bitwise.band(flags, 2) != 0
    }
  end

  defp magic_node(_bytes), do: nil

  defp tower(<<x, y, owner::signed, _pad>>) when x < 60 and y < 40,
    do: %{x: x, y: y, owner: if(owner < 0, do: nil, else: owner)}

  defp tower(_bytes), do: nil

  defp encounter(<<x, y, plane, intact, kind, _::binary-size(10), flags, _::binary>>)
       when x < 60 and y < 40 and plane in [0, 1] do
    %{
      x: x,
      y: y,
      plane: plane(plane),
      intact: intact == 1,
      kind: kind,
      looked_at: Bitwise.band(flags, 0x02) != 0
    }
  end

  defp encounter(_bytes), do: nil

  defp plane(0), do: :arcanus
  defp plane(1), do: :myrror
end
