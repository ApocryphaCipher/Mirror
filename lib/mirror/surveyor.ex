defmodule Mirror.Surveyor do
  @moduledoc """
  The game's Surveyor "City Resources": the maximum population, production
  bonus and gold bonus of a city on a tile (an existing city, or one that
  could be built there).

  The rules are restated from ReMoM (read only; it has no licence) and
  were checked against every full readout we have from the game: 15
  hovered tiles, including cities with enchantments written into a save to
  test them. docs/reference/surveyor-formula.md has each rule with its
  evidence; gama's `resources.py` is the Python original.

  Food is counted in half-food units: grassland is 3, i.e. 1½ food.
  Production and gold are percentages.
  """

  alias Mirror.SaveFile.Cities

  @width 60
  @height 40

  @wild_game 64
  @corrupted 0x20

  @nomad 11
  @granary 29
  @farmers_market 30
  @production_buildings %{15 => 25, 31 => 25, 33 => 50, 34 => 50}
  @gold_buildings %{26 => 50, 27 => 50, 28 => 100}

  # Single tiles 0xA2..0xB8: {half-food, production %}. Swamp (A6, B1, B2),
  # tundra (A7, B5, B6), volcano (B3) and the first desert (A5) give nothing.
  @base_tiles %{
    0xA2 => {3, 0},
    0xAC => {3, 0},
    0xAD => {3, 0},
    0xB4 => {3, 0},
    0xA3 => {1, 3},
    0xB7 => {1, 3},
    0xB8 => {1, 3},
    0xA4 => {0, 5},
    0xAE => {0, 3},
    0xAF => {0, 3},
    0xB0 => {0, 3},
    0xA8 => {4, 0},
    0xA9 => {5, 3},
    0xAA => {0, 5},
    0xAB => {1, 3}
  }

  # Families of joined tiles by kind range.
  @ranges [
    {0xB9..0x102, {4, 0}},
    {0x103..0x112, {0, 5}},
    {0x113..0x123, {1, 3}},
    {0x124..0x1C3, {0, 3}},
    {0x1C4..0x1D3, {1, 0}},
    {0x1D4..0x1D8, {4, 0}},
    {0x1D9..0x258, {1, 0}}
  ]

  @type plane :: :arcanus | :myrror
  @type resources :: %{max_pop: non_neg_integer(), production: integer(), gold: integer()}

  @doc "A terrain value's kind: values above 761 are animation frames of the same tile."
  def kind(terrain), do: rem(terrain, 762)

  @doc "What a worked tile gives a city: `{half_food, production_percent}`."
  @spec tile_yield(non_neg_integer()) :: {non_neg_integer(), non_neg_integer()}
  def tile_yield(terrain) do
    case kind(terrain) do
      0 -> {0, 0}
      1 -> {3, 0}
      k when k <= 0xA1 -> {1, 0}
      k when k >= 0x259 -> {0, 0}
      k -> Map.get_lazy(@base_tiles, k, fn -> range_yield(k) end)
    end
  end

  defp range_yield(kind) do
    Enum.find_value(@ranges, {0, 0}, fn {range, yield} -> kind in range && yield end)
  end

  @doc "A river tile: +20% gold for a city on it."
  def river?(terrain) do
    kind(terrain) in 0xB9..0xC4 or kind(terrain) in 0xE9..0x102 or kind(terrain) in 0x1D4..0x1D8
  end

  @doc "Ocean, shore or lake: next to one, a city gets +10% gold."
  def water?(terrain) do
    k = kind(terrain)
    (k <= 0xA1 and k != 1) or k in 0xC5..0xE8 or k in 0x1C4..0x1D3 or k in 0x1D9..0x25A
  end

  @doc "The 21 tiles a city works: 5 × 5 less the corners; x wraps, y doesn't."
  def catchment(x, y) do
    for dy <- -2..2,
        dx <- -2..2,
        not (abs(dx) == 2 and abs(dy) == 2),
        (y + dy) in 0..(@height - 1)//1,
        do: {Integer.mod(x + dx, @width), y + dy}
  end

  @doc """
  City Resources for the tile `{x, y}` on `plane`, as the Surveyor shows
  them. `planes` are a save's decoded map layers (`Mirror.SaveFile`'s
  `planes`), `cities` its cities (`Mirror.SaveFile.Cities.parse/1`).
  """
  @spec city_resources(map(), [map()], non_neg_integer(), non_neg_integer(), plane()) ::
          resources()
  def city_resources(planes, cities, x, y, plane) do
    layers = Map.fetch!(planes, plane)
    city = Enum.find(cities, &match?(%{x: ^x, y: ^y, plane: ^plane}, &1))
    claimed = claimed_tiles(cities, city, plane)

    # Unexplored tiles don't count for the bonuses (or an empty site's food).
    worked =
      for {tx, ty} = tile <- catchment(x, y),
          explored?(layers, tx, ty),
          do: {tile, MapSet.member?(claimed, tile)}

    production =
      Enum.sum(
        for {{tx, ty}, shared?} <- worked do
          {_food, percent} = tile_yield(terrain(layers, tx, ty))
          if shared?, do: div(percent, 2), else: percent
        end
      )

    site = %{production: production, gold: site_gold(layers, x, y)}

    result =
      if city,
        do: with_city(site, city, layers, cities, claimed),
        else: Map.put(site, :max_pop, site_max_pop(layers, worked))

    Map.update!(result, :max_pop, &min(&1, 25))
  end

  defp claimed_tiles(cities, city, plane) do
    for %{plane: ^plane} = other <- cities,
        other != city,
        tile <- catchment(other.x, other.y),
        into: MapSet.new(),
        do: tile
  end

  defp site_gold(layers, x, y) do
    coast? =
      Enum.any?(
        for dy <- -1..1,
            dx <- -1..1,
            {dx, dy} != {0, 0},
            (y + dy) in 0..(@height - 1)//1,
            do: water?(terrain(layers, Integer.mod(x + dx, @width), y + dy))
      )

    if(coast?, do: 10, else: 0) + if(river?(terrain(layers, x, y)), do: 20, else: 0)
  end

  # An empty site counts in quarter food, a shared tile at half, and wild
  # game as only a quarter food (the game's own under-count: a city built
  # there gets 2 food from it). With weights ×2 so halves stay integers.
  defp site_max_pop(layers, worked) do
    total =
      Enum.sum(
        for {{tx, ty}, shared?} <- worked do
          {food, _percent} = tile_yield(terrain(layers, tx, ty))
          weight = if shared?, do: 1, else: 2
          (2 * food + wild_game(layers, tx, ty)) * weight
        end
      )

    div(total, 8)
  end

  defp with_city(site, city, layers, cities, claimed) do
    gold =
      (site.gold + if(city.race == @nomad, do: 50, else: 0) + road_trade(city, cities))
      |> min(3 * city.population)

    %{
      max_pop: city_max_pop(city, layers, claimed),
      production:
        site.production + bonus(city, @production_buildings) +
          if(enchanted?(city, :inspirations), do: 100, else: 0),
      gold:
        gold + bonus(city, @gold_buildings) + if(enchanted?(city, :prosperity), do: 100, else: 0)
    }
  end

  defp bonus(city, buildings) do
    Enum.sum(for {id, percent} <- buildings, built?(city, id), do: percent)
  end

  # A replaced building (a Granary after a Farmers' Market) still counts.
  defp built?(city, id), do: Map.has_key?(city.buildings, id)
  defp enchanted?(city, name), do: Map.has_key?(city.enchantments, name)

  # A city's own rule: its uncorrupted tiles, explored or not; a shared
  # tile gives half its food, rounded only after summing (×2 weights again).
  defp city_max_pop(city, layers, claimed) do
    tiles = for {tx, ty} = t <- catchment(city.x, city.y), not corrupted?(layers, tx, ty), do: t

    food2 =
      Enum.sum(
        for {tx, ty} = tile <- tiles do
          {food, _percent} = tile_yield(terrain(layers, tx, ty))
          if MapSet.member?(claimed, tile), do: food, else: 2 * food
        end
      )

    base = div(food2 * if(enchanted?(city, :gaias_blessing), do: 3, else: 2), 8)
    base = if enchanted?(city, :famine), do: div(base, 2), else: base

    wild_game =
      Enum.sum(
        for {tx, ty} = tile <- tiles, wild_game(layers, tx, ty) == 1 do
          if MapSet.member?(claimed, tile), do: 1, else: 2
        end
      )

    base + if(built?(city, @granary), do: 2, else: 0) +
      if(built?(city, @farmers_market), do: 3, else: 0) + wild_game
  end

  # Each city joined by road adds its population in % (half, rounded down,
  # for the same race), up to 3% per thousand of this city's people.
  defp road_trade(city, cities) do
    by_index = Map.new(cities, &{&1.index, &1})

    city.road_links
    |> Enum.map(&by_index[&1])
    |> Enum.reject(&(is_nil(&1) or &1 == city))
    |> Enum.map(fn other ->
      if other.race == city.race, do: div(other.population, 2), else: other.population
    end)
    |> Enum.sum()
    |> min(3 * city.population)
  end

  @minerals %{
    1 => ["Iron Ore", "Reduces normal unit cost by 5%"],
    2 => ["Coal", "Reduces normal unit cost by 10%"],
    3 => ["Silver Ore", "+2 gold"],
    4 => ["Gold Ore", "+3 gold"],
    5 => ["Gems", "+5 gold"],
    6 => ["Mithril Ore", "+1 power"],
    7 => ["Adamantium Ore", "+2 power"],
    8 => ["Quork Crystals", "+3 power"],
    9 => ["Crysx Crystals", "+5 power"]
  }

  # Encounter kinds the panel names; 1–3 are node guardians, named by the node.
  @site_names %{
    0 => "Tower",
    4 => "Cave",
    5 => "Dungeon",
    6 => "Temple",
    7 => "Keep",
    8 => "Lair",
    9 => "Ruins",
    10 => "Temple"
  }

  @terrain_lines %{
    "Grasslands" => ["1   1/2 food"],
    "Forest" => ["1/2 food", "+3% production"],
    "Mountain" => ["+5% production"],
    "Hills" => ["1/2 food", "+3% production"],
    "Desert" => ["+3% production"],
    "Swamp" => ["1/2 food"],
    "Tundra" => [],
    "Volcano" => [],
    "River" => ["2 food", "+20% gold"],
    "River Mouth" => ["1/2 food", "+30% gold"],
    "Shore" => ["1/2 food", "+10% gold"],
    "Ocean" => []
  }

  @type panel ::
          :unexplored
          | %{
              terrain: String.t(),
              lines: [String.t()],
              feature: [String.t()],
              resources: resources() | {:cannot_build, String.t()}
            }

  @doc """
  The Surveyor panel for the tile `{x, y}` on `plane`, in the game's words:
  the terrain's name and lines ("Forest", "1/2 food", "+3% production"),
  what's on the tile (a special, a city, a site or node), and City
  Resources or why a city can't be built there. The game shows nothing for
  an unexplored tile. `sites` come from `Mirror.SaveFile.Sites.parse/1`.

  The text is fixed per terrain class, so it can disagree with the
  numbers: swamp says "1/2 food" but a city counts it as 0.
  """
  @spec panel(map(), [map()], map(), non_neg_integer(), non_neg_integer(), plane()) :: panel()
  def panel(planes, cities, sites, x, y, plane) do
    layers = Map.fetch!(planes, plane)

    if explored?(layers, x, y) do
      name = terrain_name(layers, x, y)
      city = Enum.find(cities, &match?(%{x: ^x, y: ^y, plane: ^plane}, &1))
      corrupted? = corrupted?(layers, x, y)

      %{
        terrain: name,
        lines: if(corrupted?, do: ["Corruption"], else: @terrain_lines[name]),
        feature: feature(layers, sites, city, corrupted?, x, y, plane),
        resources:
          case settle_check(layers, cities, sites, city, x, y, plane) do
            :ok -> city_resources(planes, cities, x, y, plane)
            {:cannot_build, _reason} = cannot -> cannot
          end
      }
    else
      :unexplored
    end
  end

  # The game's order: a tile is named by the first class it fits. A Sorcery
  # node reads as Grasslands, a Chaos node as Volcano, a Nature node as
  # Forest. Checked against 21 Surveyor screenshots.
  defp terrain_name(layers, x, y) do
    terrain = terrain(layers, x, y)

    case kind(terrain) do
      k when k in [0xA3, 0xB7, 0xB8, 0xA9] -> "Forest"
      k when k in [0xAA, 0xB3] -> "Volcano"
      k when k == 0xA4 or k in 0x103..0x112 -> "Mountain"
      k when k == 0xAB or k in 0x113..0x123 -> "Hills"
      k when k in [0xA5, 0xAE, 0xAF, 0xB0] or k in 0x124..0x1C3 -> "Desert"
      k when k in [0xA6, 0xB1, 0xB2] -> "Swamp"
      k when k in [0xA2, 0xAC, 0xAD, 0xB4, 0xA8] -> "Grasslands"
      k when k in [0xA7, 0xB5, 0xB6] or k > 0x25A -> "Tundra"
      _ -> water_name(layers, terrain, x, y)
    end
  end

  defp water_name(layers, terrain, x, y) do
    cond do
      river?(terrain) and river_mouth?(layers, x, y) -> "River Mouth"
      river?(terrain) -> "River"
      kind(terrain) in [0, 0x259] -> "Ocean"
      true -> "Shore"
    end
  end

  # *guess* beyond one case: a river tile with open water on a side. The
  # one River Mouth we have, Myrror (26, 25), has it to the east; ReMoM's
  # reading of this test looks garbled.
  defp river_mouth?(layers, x, y) do
    Enum.any?([{0, -1}, {0, 1}, {-1, 0}, {1, 0}], fn {dx, dy} ->
      (y + dy) in 0..(@height - 1)//1 and
        ocean_like?(terrain(layers, Integer.mod(x + dx, @width), y + dy))
    end)
  end

  defp ocean_like?(terrain), do: water?(terrain) and kind(terrain) != 0x12

  defp feature(layers, sites, city, corrupted?, x, y, plane) do
    special = byte(layers.minerals, x, y)

    cond do
      city ->
        ["#{Cities.size_name(city.size)} of", city.name]

      corrupted? ->
        []

      Map.has_key?(@minerals, Bitwise.band(special, 0x0F)) ->
        @minerals[Bitwise.band(special, 0x0F)]

      Bitwise.band(special, @wild_game) != 0 ->
        ["Wild Game", "+2 food"]

      Bitwise.band(special, 0x80) != 0 ->
        ["Nightshade", "Protects city from spells"]

      site = site_at(sites, x, y, plane) ->
        site

      true ->
        []
    end
  end

  # An intact site shows "Unexplored" until its guards have been seen; then
  # the game names them, which needs the unit names (STORY-011), so Mirror
  # shows just the site for now.
  defp site_at(sites, x, y, plane) do
    encounter =
      Enum.find(sites.encounters, &match?(%{x: ^x, y: ^y, plane: ^plane, intact: true}, &1))

    node = Enum.find(sites.nodes, &match?(%{x: ^x, y: ^y, plane: ^plane}, &1))

    cond do
      node ->
        [node_name(node.type) | node_guard(node, encounter)]

      encounter && Map.has_key?(@site_names, encounter.kind) ->
        [@site_names[encounter.kind] | guards(encounter)]

      true ->
        nil
    end
  end

  defp node_name(:sorcery), do: "Sorcery Node"
  defp node_name(:nature), do: "Nature Node"
  defp node_name(:chaos), do: "Chaos Node"
  defp node_name(_), do: "Node"

  defp node_guard(%{owner: nil}, nil), do: []
  defp node_guard(%{owner: nil}, encounter), do: guards(encounter)
  defp node_guard(%{warped: true}, _), do: ["Warped"]
  defp node_guard(%{guardian: true}, _), do: ["Guardian Spirit"]
  defp node_guard(_node, _), do: ["Magic Spirit"]

  defp guards(%{looked_at: false}), do: ["Unexplored"]
  defp guards(_encounter), do: []

  # Where a city can't go, in the game's order and words. A city's own tile
  # passes: the Surveyor shows its City Resources.
  defp settle_check(layers, cities, sites, city, x, y, plane) do
    cond do
      water?(terrain(layers, x, y)) ->
        {:cannot_build, "on water."}

      Enum.any?(sites.towers, &match?(%{x: ^x, y: ^y}, &1)) ->
        {:cannot_build, "on towers."}

      Enum.any?(sites.nodes, &match?(%{x: ^x, y: ^y, plane: ^plane}, &1)) ->
        {:cannot_build, "on magic nodes."}

      Enum.any?(sites.encounters, &match?(%{x: ^x, y: ^y, plane: ^plane, intact: true}, &1)) ->
        {:cannot_build, "on lairs."}

      city ->
        :ok

      Enum.any?(cities, &(&1.plane == plane and distance(&1, x, y) <= 3)) ->
        {:cannot_build, "less than 3 squares from any other city."}

      true ->
        :ok
    end
  end

  # Tiles apart, the larger of the two axes, x wrapping around the world.
  defp distance(city, x, y) do
    dx = abs(city.x - x)
    max(min(dx, @width - dx), abs(city.y - y))
  end

  defp terrain(layers, x, y) do
    offset = (y * @width + x) * 2
    <<_::binary-size(^offset), value::little-16, _::binary>> = layers.terrain
    value
  end

  defp explored?(layers, x, y), do: byte(layers.exploration, x, y) != 0

  defp corrupted?(layers, x, y),
    do: Bitwise.band(byte(layers.terrain_flags, x, y), @corrupted) != 0

  defp wild_game(layers, x, y),
    do: if(Bitwise.band(byte(layers.minerals, x, y), @wild_game) != 0, do: 1, else: 0)

  defp byte(layer, x, y), do: :binary.at(layer, y * @width + x)
end
