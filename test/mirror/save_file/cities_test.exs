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

    assert Map.drop(deventor, [:buildings, :enchantments, :road_links]) == %{
             index: 0,
             name: "Deventor",
             race: 5,
             x: 38,
             y: 21,
             plane: :arcanus,
             owner: 0,
             size: 1,
             population: 4,
             walled: false
           }

    assert %{name: "Bloodrock", plane: :myrror, owner: 2, size: 2} = bloodrock
  end

  test "City Walls is building byte +66: 1 built; 0xFF (not built) and 0 (replaced) are not" do
    buildings = fn walls -> :binary.copy(<<0xFF>>, 32) <> <<walls>> end
    walled = city("Norport", 38, 21, 0, 0, 1, 4) <> :binary.copy(<<0>>, 13) <> buildings.(1)
    open = city("Posen", 31, 24, 0, 5, 1, 4) <> :binary.copy(<<0>>, 13) <> buildings.(0xFF)
    replaced = city("Odd", 1, 1, 0, 5, 1, 4) <> :binary.copy(<<0>>, 13) <> buildings.(0)

    assert {:ok, [%{walled: true}, %{walled: false}, %{walled: false}]} =
             Cities.parse(save([walled, open, replaced]))
  end

  test "buildings by id (built or replaced), enchantments with their caster, road links" do
    buildings = <<0>> <> :binary.copy(<<0xFF>>, 35)
    buildings = put(put(put(buildings, 26, <<1>>), 29, <<0>>), 30, <<1>>)
    enchantments = put(put(:binary.copy(<<0>>, 26), 14, <<1>>), 7, <<3>>)
    roads = put(:binary.copy(<<0>>, 13), 1, <<0b0000_0101>>)

    bytes =
      city("Konstanz", 38, 21, 0, 0, 2, 8) <>
        :binary.copy(<<0>>, 10) <> buildings <> enchantments <> :binary.copy(<<0>>, 8) <> roads

    assert {:ok, [konstanz]} = Cities.parse(save([bytes]))
    assert konstanz.buildings == %{26 => :built, 29 => :replaced, 30 => :built}
    assert konstanz.enchantments == %{natures_eye: 0, famine: 2}
    assert konstanz.road_links == [8, 10]
    refute konstanz.walled
  end

  test "a name with a high byte is still valid UTF-8 (STORY-040)" do
    assert Cities.city_name(<<"Bad", 0xFF, 0, 0>>) == "Badÿ"
    assert Cities.city_name(<<"Konstanz", 0, 1, 2>>) == "Konstanz"
  end

  test "size classes the game names; unseen ones are numbered" do
    assert Enum.map(0..3, &Cities.size_name/1) == ["Outpost", "Hamlet", "Village", "size 3"]
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
