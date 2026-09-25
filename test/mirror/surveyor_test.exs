defmodule Mirror.SurveyorTest do
  use ExUnit.Case, async: true

  alias Mirror.{SaveFile, Surveyor}
  alias Mirror.SaveFile.{Blocks, Cities, Sites}

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
      name: Keyword.get(opts, :name, "Testburg"),
      size: Keyword.get(opts, :size, 1),
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

  describe "the panel" do
    @no_sites %{nodes: [], towers: [], encounters: []}

    test "names the terrain in the game's words, lines fixed per class" do
      world = forest_world(tiles: %{{1, 1} => 0xA6, {2, 2} => 0x113, {3, 3} => 0xA2})
      panel = &Surveyor.panel(world, [], @no_sites, &1, &2, :arcanus)

      assert %{terrain: "Forest", lines: ["1/2 food", "+3% production"]} = panel.(10, 20)
      # The panel's 1/2 food for swamp, which cities count as nothing.
      assert %{terrain: "Swamp", lines: ["1/2 food"]} = panel.(1, 1)
      assert %{terrain: "Hills"} = panel.(2, 2)
      assert %{terrain: "Grasslands", lines: ["1   1/2 food"]} = panel.(3, 3)
    end

    test "a river beside open water is a River Mouth" do
      river = 0xEE
      world = forest_world(tiles: %{{5, 5} => river, {6, 5} => @ocean, {9, 9} => river})

      assert %{terrain: "River Mouth", lines: ["1/2 food", "+30% gold"]} =
               Surveyor.panel(world, [], @no_sites, 5, 5, :arcanus)

      assert %{terrain: "River"} = Surveyor.panel(world, [], @no_sites, 9, 9, :arcanus)
    end

    test "shows the tile's special, or the city on it" do
      world = forest_world(specials: %{{20, 20} => 4, {21, 5} => 64})
      city = city(0, 30, 30, name: "Konstanz", size: 2)

      assert %{feature: ["Gold Ore", "+3 gold"]} =
               Surveyor.panel(world, [], @no_sites, 20, 20, :arcanus)

      assert %{feature: ["Wild Game", "+2 food"]} =
               Surveyor.panel(world, [], @no_sites, 21, 5, :arcanus)

      assert %{feature: ["Village of", "Konstanz"], resources: %{max_pop: _}} =
               Surveyor.panel(world, [city], @no_sites, 30, 30, :arcanus)
    end

    test "why a city can't go there, in the game's order" do
      world = %{arcanus: layers(@forest, tiles: %{{0, 0} => @ocean}), myrror: layers(@forest)}

      sites = %{
        towers: [%{x: 5, y: 5, owner: nil}],
        nodes: [
          %{
            x: 8,
            y: 8,
            plane: :arcanus,
            type: :nature,
            owner: nil,
            warped: false,
            guardian: false
          }
        ],
        encounters: [%{x: 12, y: 12, plane: :arcanus, intact: true, kind: 7, looked_at: false}]
      }

      reason = fn x, y, plane ->
        case Surveyor.panel(world, [city(0, 40, 20)], sites, x, y, plane).resources do
          {:cannot_build, text} -> text
          %{} -> :ok
        end
      end

      assert reason.(0, 0, :arcanus) == "on water."
      # A tower stands on both planes.
      assert reason.(5, 5, :myrror) == "on towers."
      assert reason.(8, 8, :arcanus) == "on magic nodes."
      assert reason.(12, 12, :arcanus) == "on lairs."
      assert reason.(12, 12, :myrror) == :ok
      # "Less than 3 squares": 3 apart on either axis is still too close.
      assert reason.(43, 23, :arcanus) == "less than 3 squares from any other city."
      assert reason.(44, 20, :arcanus) == :ok
      assert reason.(40, 20, :arcanus) == :ok
    end

    test "the too-close distance wraps around the world" do
      world = forest_world()
      far_west = city(0, 1, 20)

      assert Surveyor.panel(world, [far_west], @no_sites, 58, 20, :arcanus).resources ==
               {:cannot_build, "less than 3 squares from any other city."}
    end

    test "the game shows nothing for an unexplored tile" do
      world = %{arcanus: layers(@forest, explored: false), myrror: layers(@forest)}
      assert Surveyor.panel(world, [], @no_sites, 10, 10, :arcanus) == :unexplored
    end
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

    # The panel's top half, from the screenshots and the fork's hover log.
    @panels [
      {{38, 21, :arcanus}, "Hills", ["Village of", "Konstanz"]},
      {{47, 16, :arcanus}, "River", ["Village of", "Steyr"]},
      {{55, 29, :arcanus}, "Grasslands", ["Hamlet of", "Sidon"]},
      {{39, 6, :myrror}, "Tundra", ["Hamlet of", "Straatus"]},
      {{40, 10, :myrror}, "Mountain", ["Hamlet of", "Blade Stone"]},
      {{48, 11, :myrror}, "Swamp", ["Hamlet of", "Ebonsway"]},
      {{31, 24, :arcanus}, "Forest", ["Hamlet of", "Posen"]},
      {{31, 20, :arcanus}, "Hills", ["Village of", "Ozenwall"]},
      {{34, 16, :arcanus}, "Forest", ["Hamlet of", "Speger"]}
    ]

    @tag skip:
           (!File.exists?(@save) && "needs the frozen Dior save (MIRROR_SURVEYOR_SAVE)") ||
             (!Blocks.layer_offset(:terrain) && "needs the save offsets: scripts/test_game.sh")
    test "names each hovered tile and what's on it, and why a city can't go there" do
      {:ok, save} = SaveFile.load(@save)
      {:ok, cities} = Cities.parse(save.raw)
      {:ok, sites} = Sites.parse(save.raw)
      panel = fn {x, y, plane} -> Surveyor.panel(save.planes, cities, sites, x, y, plane) end

      for {tile, terrain, feature} <- @panels do
        assert %{terrain: ^terrain, feature: ^feature} = panel.(tile)
      end

      assert %{feature: ["Tower", "Unexplored"], resources: {:cannot_build, "on towers."}} =
               panel.({48, 28, :arcanus})

      assert %{feature: ["Dungeon", "Unexplored"], resources: {:cannot_build, "on lairs."}} =
               panel.({39, 31, :arcanus})

      assert %{feature: ["Chaos Node" | _], resources: {:cannot_build, "on magic nodes."}} =
               panel.({41, 29, :arcanus})

      assert %{
               terrain: "Swamp",
               feature: ["Nightshade", "Protects city from spells"],
               resources: {:cannot_build, "less than 3 squares from any other city."}
             } = panel.({46, 16, :arcanus})
    end
  end
end
