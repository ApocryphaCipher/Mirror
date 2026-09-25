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
    node = <<42, 10, 0, 0, 5>> <> :binary.copy(<<0>>, 40) <> <<0, 2, 0>>
    unowned = <<11, 12, 1, 0xFF, 5>> <> :binary.copy(<<0>>, 40) <> <<2, 1, 0>>
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
               guardian: true
             },
             %{
               x: 11,
               y: 12,
               plane: :myrror,
               type: :chaos,
               owner: nil,
               warped: true,
               guardian: false
             }
           ]

    assert sites.towers == [%{x: 48, y: 28, owner: nil}]

    assert sites.encounters == [
             %{x: 26, y: 25, plane: :myrror, intact: true, kind: 7, looked_at: false},
             %{x: 28, y: 21, plane: :myrror, intact: false, kind: 6, looked_at: true}
           ]
  end

  test "a file too short for the blocks is an error" do
    assert {:error, :no_sites_block} = Sites.parse(<<0, 1, 2>>)
  end
end
