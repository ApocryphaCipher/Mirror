defmodule Mirror.SurveyorTest do
  use ExUnit.Case, async: true

  alias Mirror.{SaveFile, Surveyor}
  alias Mirror.SaveFile.{Blocks, Cities}

  @forest 0xA3
  @ocean 0x00

  # One plane's layers, every tile `terrain`, explored, with `specials`
  # (%{{x, y} => mineral}) and `tiles` (%{{x, y} => terrain}).
  defp layers(terrain, opts \\ []) do
    tiles = Keyword.get(opts, :tiles, %{})
    specials = Keyword.get(opts, :specials, %{})
    explored = if Keyword.get(opts, :explored, true), do: 1, else: 0

    %{
      terrain: for(i <- 0..2399, into: <<>>, do: <<Map.get(tiles, tile(i), terrain)::little-16>>),
      minerals: for(i <- 0..2399, into: <<>>, do: <<Map.get(specials, tile(i), 0)>>),
      exploration: :binary.copy(<<explored>>, 2400),
      terrain_flags: :binary.copy(<<0>>, 2400)
    }
  end

  defp tile(i), do: {rem(i, 60), div(i, 60)}

  defp city(index, x, y, opts \\ []) do
    %{
      index: index,
      x: x,
      y: y,
      plane: Keyword.get(opts, :plane, :arcanus),
      race: Keyword.get(opts, :race, 0),
      population: Keyword.get(opts, :population, 4),
      buildings: Keyword.get(opts, :buildings, %{}),
      enchantments: Keyword.get(opts, :enchantments, %{}),
      road_links: Keyword.get(opts, :road_links, [])
    }
  end

  defp forest_world(opts \\ []),
    do: %{arcanus: layers(@forest, opts), myrror: layers(@ocean, explored: false)}

  test "tile yields: half-food and production %, animation frames alike" do
    assert Surveyor.tile_yield(@forest) == {1, 3}
    assert Surveyor.tile_yield(@forest + 762) == {1, 3}
    assert Surveyor.tile_yield(0xA2) == {3, 0}
    assert Surveyor.tile_yield(0x10A) == {0, 5}
    # The panel says swamp gives 1/2 food; cities count it as nothing.
    assert Surveyor.tile_yield(0xA6) == {0, 0}
    assert Surveyor.tile_yield(@ocean) == {0, 0}
  end

  test "the catchment is 5 x 5 less the corners, wrapping in x only" do
    assert length(Surveyor.catchment(10, 20)) == 21
    assert {59, 20} in Surveyor.catchment(0, 20)
    assert length(Surveyor.catchment(10, 0)) == 13
  end

  test "a city: its tiles' food, wild game +2, Granary +2; production from its tiles" do
    world = forest_world(specials: %{{10, 19} => 64})
    konstanz = city(0, 10, 20, buildings: %{29 => :replaced})

    # 21 forests = 10½ food -> 10, wild game 2, Granary 2 (replaced still counts).
    assert Surveyor.city_resources(world, [konstanz], 10, 20, :arcanus) ==
             %{max_pop: 14, production: 63, gold: 0}
  end

  test "an empty site counts wild game as only a quarter food" do
    world = forest_world(specials: %{{31, 20} => 64})

    assert %{max_pop: 10, production: 63} =
             Surveyor.city_resources(world, [], 30, 20, :arcanus)
  end

  test "a tile another city also works gives half: production per tile, food after summing" do
    cities = [city(0, 10, 20), city(1, 13, 20)]

    # 6 shared forests: 3 // 2 = 1% each; food 15 + 6 / 2 = 18 half-food -> 9.
    assert %{max_pop: 9, production: 51} =
             Surveyor.city_resources(forest_world(), cities, 10, 20, :arcanus)
  end

  test "Gaia's Blessing gives x1.5 food; Famine halves" do
    gaia = city(0, 10, 20, enchantments: %{gaias_blessing: 0})
    famine = city(0, 10, 20, enchantments: %{famine: 1})

    assert %{max_pop: 15} = Surveyor.city_resources(forest_world(), [gaia], 10, 20, :arcanus)
    assert %{max_pop: 5} = Surveyor.city_resources(forest_world(), [famine], 10, 20, :arcanus)
  end

  test "gold: coast +10, Nomad +50, capped at 3% per thousand, then buildings" do
    world = %{arcanus: layers(@ocean, tiles: %{{30, 20} => @forest}), myrror: layers(@ocean)}
    nomads = city(0, 30, 20, race: 11, population: 3, buildings: %{26 => :built})

    assert %{gold: 10} = Surveyor.city_resources(world, [], 30, 20, :arcanus)
    assert Surveyor.city_resources(world, [nomads], 30, 20, :arcanus).gold == 9 + 50
  end

  test "road trade: another race's population in full, the same race's halved" do
    home = city(0, 10, 20, race: 4, population: 4, road_links: [1, 2])
    other_race = city(1, 40, 20, race: 3, population: 4)
    same_race = city(2, 50, 10, race: 4, population: 3)

    cities = [home, other_race, same_race]
    assert Surveyor.city_resources(forest_world(), cities, 10, 20, :arcanus).gold == 4 + 1
  end

  test "Inspirations +100% production, Prosperity +100% gold, maximum population at most 25" do
    world = %{arcanus: layers(0xA9), myrror: layers(@ocean)}
    blessed = city(0, 10, 20, enchantments: %{inspirations: 0, prosperity: 0})

    assert Surveyor.city_resources(world, [blessed], 10, 20, :arcanus) ==
             %{max_pop: 25, production: 63 + 100, gold: 100}
  end

  describe "Freya - Dior (the game's own readouts, 2026-09-24)" do
    @save System.get_env(
            "MIRROR_SURVEYOR_SAVE",
            Path.expand("~/.mirror/dev/surveyor-fixtures/SAVE9-dior-2026-09-24.GAM")
          )

    # City, tile, and what the game's Surveyor showed (screenshots in
    # docs/reference/surveyor-formula.md).
    @readouts [
      {"Konstanz", {38, 21, :arcanus}, {22, 160, 150}},
      {"Steyr", {47, 16, :arcanus}, {8, 37, 21}},
      {"Sidon", {55, 29, :arcanus}, {21, 6, 12}},
      {"Straatus", {39, 6, :myrror}, {14, 11, 12}},
      {"Blade Stone", {40, 10, :myrror}, {19, 50, 5}},
      {"Ebonsway", {48, 11, :myrror}, {9, 13, 9}},
      {"Posen", {31, 24, :arcanus}, {7, 35, 12}},
      {"Ozenwall", {31, 20, :arcanus}, {13, 29, 13}},
      {"Speger", {34, 16, :arcanus}, {10, 29, 9}}
    ]

    @tag skip:
           (!File.exists?(@save) && "needs the frozen Dior save (MIRROR_SURVEYOR_SAVE)") ||
             (!Blocks.layer_offset(:terrain) && "needs the save offsets: scripts/test_game.sh")
    test "matches every City Resources readout" do
      {:ok, save} = SaveFile.load(@save)
      {:ok, cities} = Cities.parse(save.raw)

      for {name, {x, y, plane}, {max_pop, production, gold}} <- @readouts do
        assert Enum.find(cities, &(&1.x == x and &1.y == y)).name == name

        assert {name, Surveyor.city_resources(save.planes, cities, x, y, plane)} ==
                 {name, %{max_pop: max_pop, production: production, gold: gold}}
      end
    end
  end
end
