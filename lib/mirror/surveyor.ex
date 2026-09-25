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
