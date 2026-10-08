defmodule Mirror.SaveFile.SitesTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Sites

  defp put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  # A save-sized binary with every node, tower and encounter off the map
  # (x 0xFF), then the given records written in.
  defp save(records) do
    blank = :binary.copy(<<0xFF>>, 0x6628 + 102 * 24)
    Enum.reduce(records, blank, fn {at, bytes}, raw -> put(raw, at, bytes) end)
  end

  test "nodes, towers and encounters: position, kind, owner, intact" do
    # The Sorcery node at (42, 10) as the game wrote it after a meld: power 5, and
    # the five tiles that sparkled (the node's own tile first).
    aura_x = <<42, 43, 41, 42, 41>> <> :binary.copy(<<0>>, 15)
    aura_y = <<10, 10, 9, 11, 10>> <> :binary.copy(<<0>>, 15)
    node = <<42, 10, 0, 0, 5>> <> aura_x <> aura_y <> <<0, 2, 0>>
    unowned = <<11, 12, 1, 0xFF, 0>> <> :binary.copy(<<0>>, 40) <> <<2, 1, 0>>
    tower = <<48, 28, 0xFF, 0>>
    keep = <<26, 25, 1, 1, 7>> <> :binary.copy(<<0>>, 10) <> <<0>> <> :binary.copy(<<0>>, 8)
    cleared = <<28, 21, 1, 0, 6>> <> :binary.copy(<<0>>, 10) <> <<2>> <> :binary.copy(<<0>>, 8)

    raw =
      save([
        {0x6058, node},
        {0x6058 + 48, unowned},
        {0x6610 + 2 * 4, tower},
        {0x6628, keep},
        {0x6628 + 24, cleared}
      ])

    assert {:ok, sites} = Sites.parse(raw)

    assert sites.nodes == [
             %{
               x: 42,
               y: 10,
               plane: :arcanus,
               type: :sorcery,
               owner: 0,
               warped: false,
               guardian: true,
               power: 5,
               aura_tiles: [{42, 10}, {43, 10}, {41, 9}, {42, 11}, {41, 10}]
             },
             %{
               x: 11,
               y: 12,
               plane: :myrror,
               type: :chaos,
               owner: nil,
               warped: true,
               guardian: false,
               power: 0,
               aura_tiles: []
             }
           ]

    assert sites.towers == [%{x: 48, y: 28, owner: nil}]

    assert sites.encounters == [
             %{x: 26, y: 25, plane: :myrror, intact: true, kind: 7, looked_at: false},
             %{x: 28, y: 21, plane: :myrror, intact: false, kind: 6, looked_at: true}
           ]
  end

  test "a node's aura tiles are its first `power` pairs; a pair off the map is dropped" do
    # power 3: (5, 6), (99, 7) is off the map, (8, 9); the pair after power is ignored
    aura_x = <<5, 99, 8, 20>> <> :binary.copy(<<0>>, 16)
    aura_y = <<6, 7, 9, 21>> <> :binary.copy(<<0>>, 16)
    node = <<5, 6, 0, 1, 3>> <> aura_x <> aura_y <> <<1, 0, 0>>

    assert {:ok, %{nodes: [%{power: 3, aura_tiles: [{5, 6}, {8, 9}]}]}} =
             Sites.parse(save([{0x6058, node}]))
  end

  test "a power above the 20 stored pairs is capped at 20" do
    aura_x = :binary.list_to_bin(Enum.to_list(1..20))
    aura_y = :binary.copy(<<3>>, 20)
    node = <<1, 3, 0, 0, 200>> <> aura_x <> aura_y <> <<0, 0, 0>>

    assert {:ok, %{nodes: [%{aura_tiles: tiles}]}} = Sites.parse(save([{0x6058, node}]))
    assert length(tiles) == 20
    assert List.first(tiles) == {1, 3}
  end

  test "a file too short for the blocks is an error" do
    assert {:error, :no_sites_block} = Sites.parse(<<0, 1, 2>>)
  end
end
