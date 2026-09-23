defmodule Mirror.SaveFile.CitiesTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.{Cities, Wizards}

  @cities 0x8AAC
  @record 114

  # A save-sized binary with `count` at 0x9e0 and the given city records.
  defp save(cities, opts \\ []) do
    count = Keyword.get(opts, :count, length(cities))
    raw = :binary.copy(<<0>>, @cities + 100 * @record)
    raw = put(raw, 0x9E0, <<count::little-16>>)

    cities
    |> Enum.with_index()
    |> Enum.reduce(raw, fn {bytes, i}, acc -> put(acc, @cities + i * @record, bytes) end)
  end

  defp put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  defp city(name, x, y, plane, owner, size, pop) do
    String.pad_trailing(name, 14, <<0>>) <> <<5, x, y, plane, owner, size, pop>>
  end

  test "parses the live records: name, position, plane, owner, size, population" do
    raw = save([city("Deventor", 38, 21, 0, 0, 1, 4), city("Bloodrock", 54, 23, 1, 2, 2, 8)])

    assert {:ok, [deventor, bloodrock]} = Cities.parse(raw)

    assert deventor == %{
             index: 0,
             name: "Deventor",
             race: 5,
             x: 38,
             y: 21,
             plane: :arcanus,
             owner: 0,
             size: 1,
             population: 4
           }

    assert %{name: "Bloodrock", plane: :myrror, owner: 2, size: 2} = bloodrock
  end

  test "only the first `count` records are live" do
    raw = save([city("A", 1, 1, 0, 0, 0, 1), city("B", 2, 2, 0, 0, 0, 1)], count: 1)
    assert {:ok, [%{name: "A"}]} = Cities.parse(raw)
  end

  test "records off the map are skipped rather than drawn in the wrong place" do
    raw = save([city("Ok", 59, 39, 1, 0, 0, 1), city("Bad", 60, 5, 0, 0, 0, 1)])
    assert {:ok, [%{name: "Ok"}]} = Cities.parse(raw)
  end

  test "a file too short for the block is an error" do
    assert {:error, :no_cities_block} = Cities.parse(<<0, 1, 2>>)
  end

  test "wizard banners by owner index, unknown colours are neutral" do
    raw = :binary.copy(<<0>>, 0x9E8 + 6 * 0x4C8)

    raw =
      Enum.reduce(Enum.zip(0..5, [4, 3, 2, 0, 1, 5]), raw, fn {owner, banner}, acc ->
        put(acc, 0x9E8 + owner * 0x4C8 + 0x16, <<banner>>)
      end)

    assert Wizards.banners(raw) ==
             %{0 => :yellow, 1 => :red, 2 => :purple, 3 => :blue, 4 => :green, 5 => :neutral}
  end

  describe "SAVE1.GAM" do
    @mom_path System.get_env("MIRROR_MOM_PATH", "")
    @save Path.join(@mom_path, "SAVE1.GAM")

    @tag skip: !File.exists?(@save) && "needs MIRROR_MOM_PATH/SAVE1.GAM"
    test "has 27 cities, all on the map, with known owners" do
      raw = File.read!(@save)
      {:ok, cities} = Cities.parse(raw)

      assert length(cities) == 27
      assert %{name: "Deventor", x: 38, y: 21, plane: :arcanus, owner: 0} = hd(cities)
      assert Enum.count(cities, &(&1.plane == :myrror)) == 11
      assert Wizards.banners(raw)[0] == :yellow
    end
  end
end
