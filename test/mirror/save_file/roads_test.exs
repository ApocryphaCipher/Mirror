defmodule Mirror.SaveFile.RoadsTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Roads

  @width 60
  @height 40
  @plane_size @width * @height

  defp blank_plane, do: :binary.copy(<<0>>, @plane_size)

  defp put_tile(plane, x, y, byte) do
    idx = y * @width + x
    <<head::binary-size(^idx), _::8, tail::binary>> = plane
    head <> <<byte>> <> tail
  end

  describe "road piece selection" do
    test "a tile without road has no road pieces" do
      flags = blank_plane()
      assert Roads.road_pieces(flags, 10, 10) == []
    end

    test "a road tile with 0 road neighbours selects only the centre piece" do
      flags = blank_plane() |> put_tile(10, 10, 0x08)
      assert Roads.road_pieces(flags, 10, 10) == [:c]
    end

    test "a road tile with 1 road neighbour selects centre plus that direction piece" do
      # North neighbour at (10, 9)
      flags =
        blank_plane()
        |> put_tile(10, 10, 0x08)
        |> put_tile(10, 9, 0x08)

      assert Roads.road_pieces(flags, 10, 10) == [:c, :n]
      assert Roads.road_pieces(flags, 10, 9) == [:c, :s]

      # East neighbour at (11, 10)
      flags_e =
        blank_plane()
        |> put_tile(10, 10, 0x08)
        |> put_tile(11, 10, 0x08)

      assert Roads.road_pieces(flags_e, 10, 10) == [:c, :e]
      assert Roads.road_pieces(flags_e, 11, 10) == [:c, :w]

      # Diagonal neighbours (NE, SE, SW, NW)
      for {dx, dy, dir_from, dir_to} <- [
            {1, -1, :ne, :sw},
            {1, 1, :se, :nw},
            {-1, 1, :sw, :ne},
            {-1, -1, :nw, :se}
          ] do
        f =
          blank_plane()
          |> put_tile(10, 10, 0x08)
          |> put_tile(10 + dx, 10 + dy, 0x08)

        assert Roads.road_pieces(f, 10, 10) == [:c, dir_from]
        assert Roads.road_pieces(f, 10 + dx, 10 + dy) == [:c, dir_to]
      end
    end

    test "a road tile with multiple road neighbours selects centre plus all connected directions" do
      flags =
        blank_plane()
        |> put_tile(10, 10, 0x08)
        |> put_tile(10, 9, 0x08)
        |> put_tile(11, 10, 0x08)
        |> put_tile(10, 11, 0x08)
        |> put_tile(9, 10, 0x08)

      assert Roads.road_pieces(flags, 10, 10) == [:c, :n, :e, :s, :w]
    end

    test "road piece selection wraps across map boundaries horizontally (x=0 and x=59)" do
      # Straight East/West wrap
      flags =
        blank_plane()
        |> put_tile(0, 15, 0x08)
        |> put_tile(59, 15, 0x08)

      assert Roads.road_pieces(flags, 0, 15) == [:c, :w]
      assert Roads.road_pieces(flags, 59, 15) == [:c, :e]

      # Diagonal wrap: NW from x=0 lands at (59, y-1)
      flags_nw =
        blank_plane()
        |> put_tile(0, 15, 0x08)
        |> put_tile(59, 14, 0x08)

      assert Roads.road_pieces(flags_nw, 0, 15) == [:c, :nw]
      assert Roads.road_pieces(flags_nw, 59, 14) == [:c, :se]

      # Diagonal wrap: SW from x=0 lands at (59, y+1)
      flags_sw =
        blank_plane()
        |> put_tile(0, 15, 0x08)
        |> put_tile(59, 16, 0x08)

      assert Roads.road_pieces(flags_sw, 0, 15) == [:c, :sw]
      assert Roads.road_pieces(flags_sw, 59, 16) == [:c, :ne]
    end

    test "road piece selection does not wrap vertically (y=0 and y=39)" do
      flags =
        blank_plane()
        |> put_tile(10, 0, 0x08)
        |> put_tile(10, 39, 0x08)

      # Clamped vertically per wrap_y: false
      assert Roads.road_pieces(flags, 10, 0) == [:c]
      assert Roads.road_pieces(flags, 10, 39) == [:c]
    end
  end

  describe "enchanted vs normal road choice" do
    test "flag 0x08 produces a normal road (enchanted: false)" do
      flags = blank_plane() |> put_tile(5, 5, 0x08)
      assert [item] = Roads.road_items(flags)
      assert item == %{kind: :road, x: 5, y: 5, pieces: [:c], enchanted: false}
    end

    test "flag 0x10 produces an enchanted road (enchanted: true)" do
      flags = blank_plane() |> put_tile(5, 5, 0x10)
      assert [item] = Roads.road_items(flags)
      assert item == %{kind: :road, x: 5, y: 5, pieces: [:c], enchanted: true}
    end

    test "flag 0x18 (both 0x08 and 0x10) produces an enchanted road (enchanted: true)" do
      flags = blank_plane() |> put_tile(5, 5, 0x18)
      assert [item] = Roads.road_items(flags)
      assert item == %{kind: :road, x: 5, y: 5, pieces: [:c], enchanted: true}
    end

    test "normal and enchanted road neighbours connect to each other" do
      flags =
        blank_plane()
        |> put_tile(10, 10, 0x08)
        |> put_tile(10, 11, 0x10)

      assert Roads.road_pieces(flags, 10, 10) == [:c, :s]
      assert Roads.road_pieces(flags, 10, 11) == [:c, :n]

      items = Roads.road_items(flags)
      assert Enum.find(items, &(&1.x == 10 and &1.y == 10)).enchanted == false
      assert Enum.find(items, &(&1.x == 10 and &1.y == 11)).enchanted == true
    end
  end

  describe "minerals/specials mapping" do
    @expected_specials [
      {1, :iron},
      {2, :coal},
      {3, :silver},
      {4, :gold},
      {5, :gems},
      {6, :mithril},
      {7, :adamantium},
      {8, :quork},
      {9, :crysx},
      {64, :wild_game},
      {128, :nightshade}
    ]

    test "each documented mineral byte value maps to the expected special atom" do
      for {byte_val, special_atom} <- @expected_specials do
        assert Roads.special_for_value(byte_val) == special_atom

        minerals = blank_plane() |> put_tile(12, 18, byte_val)

        assert Roads.special_items(minerals) == [
                 %{kind: :special, x: 12, y: 18, special: special_atom}
               ]
      end
    end

    test "unmapped minerals values produce no special items" do
      for invalid <- [0, 10, 15, 63, 65, 127, 255] do
        assert Roads.special_for_value(invalid) == nil

        minerals = blank_plane() |> put_tile(12, 18, invalid)
        assert Roads.special_items(minerals) == []
      end
    end
  end

  describe "corruption" do
    test "flag bit 0x20 produces a corruption item" do
      flags = blank_plane() |> put_tile(20, 25, 0x20)
      assert Roads.corruption_items(flags) == [%{kind: :corruption, x: 20, y: 25}]
    end

    test "a tile with both road and corruption produces both items" do
      flags = blank_plane() |> put_tile(20, 25, 0x28)
      assert [%{kind: :road, x: 20, y: 25}] = Roads.road_items(flags)
      assert [%{kind: :corruption, x: 20, y: 25}] = Roads.corruption_items(flags)
    end

    test "tiles without bit 0x20 produce no corruption item" do
      flags = blank_plane() |> put_tile(20, 25, 0x18)
      assert Roads.corruption_items(flags) == []
    end
  end

  describe "combined items/3" do
    test "returns roads, specials, and corruption items tagged with kind" do
      flags =
        blank_plane()
        |> put_tile(10, 10, 0x08)
        |> put_tile(20, 20, 0x20)

      minerals =
        blank_plane()
        |> put_tile(30, 30, 4)

      items = Roads.items(flags, minerals)

      assert Enum.find(items, &(&1.kind == :road and &1.x == 10 and &1.y == 10))

      assert Enum.find(
               items,
               &(&1.kind == :special and &1.x == 30 and &1.y == 30 and &1.special == :gold)
             )

      assert Enum.find(items, &(&1.kind == :corruption and &1.x == 20 and &1.y == 20))
    end
  end
end
