defmodule Mirror.SaveFile.Structures do
  @moduledoc """
  Moves structures on the map by patching a save's raw bytes (STORY-019).
  Pure: `raw` in, `raw` out, nothing is read from or written to disk.

  A structure's position is not stored once. Moving it means writing every
  place the save repeats it, or the game loads a save that disagrees with
  itself. What each kind carries (all decoded for reading in
  `Mirror.SaveFile.Cities`, `Sites` and `Units`; the wizard fields are in
  docs/reference/wizard-record-and-exploration.md and kazzmir-save-layouts.md):

    * **City**: its own x, y, plane (`+15`, `+16`, `+17`); every unit standing
      on the old tile (the garrison); the owner's summoning circle (wizard
      record `+0x2E/+0x30/+0x32`, i16) and fortress (`0x65F8`, 6 × 4:
      x, y, plane, active), each only when it sits on the old tile, which is
      how a capital takes both with it.
    * **Tower of Wizardry**: x, y in the tower block; the same x, y on both
      its encounter records (one per plane); units standing on the tile on
      either plane. A tower has no plane byte.
    * **Lair, cave, temple, ruin, keep…** (an encounter that is not a tower
      or a node guardian): x, y, plane in its own record, and nothing else.

  Not done yet, on purpose:

    * **Nodes.** A node is its terrain tile, so moving one means moving
      terrain too, and its aura tiles and guardian record. That is a map
      edit, not a record edit.
    * **City road links** (`+101`) are left as they are. They name *which*
      cities are joined, and the roads themselves are terrain flags; whether
      the game recomputes them was not checked. Each result carries
      `stale: [...]` naming what was left alone.
    * **Units' own go-to targets**, if the record has any, are not known.

  Nothing here has been seen in the real game yet. `docs/reference/real-game-acceptance.md`
  says how to check one kind at a time, and STORY-019 records the outcome.
  """

  alias Mirror.SaveFile.{Cities, Sites, Units, Wizards}

  @width 60
  @height 40

  @city_record 114
  @unit_record 32
  @encounter_record 24
  @tower_record 4

  @fortress_offset 0x65F8
  @fortress_records 6
  @wizard_record 0x4C8
  @wizards 6
  @circle_x 0x2E
  @circle_y 0x30
  @circle_plane 0x32

  @tower_kind 0
  @node_guardian_kinds [1, 2, 3]

  @type position :: {x :: non_neg_integer(), y :: non_neg_integer(), plane :: 0 | 1}
  @type result :: {:ok, binary(), map()} | {:error, term()}

  @doc """
  Moves city `index` (its position in `Cities.parse/1`'s list) to `{x, y, plane}`.

  Its garrison and, if the city is where its owner's summoning circle or
  fortress is, those too. Refuses a destination off the map, one that holds
  another city, or one holding units of any other owner (they would be
  standing in a city that is not theirs).
  """
  @spec move_city(binary(), non_neg_integer(), position()) :: result()
  def move_city(raw, index, {x, y, plane} = to) do
    with :ok <- check_position(to),
         {:ok, cities} <- Cities.parse(raw),
         {:ok, city} <- fetch(cities, index, :no_such_city),
         from = {city.x, city.y, plane_index(city.plane)},
         {:ok, units} <- Units.parse(raw),
         :ok <- check_city_free(cities, city, to),
         :ok <- check_foreign_units(units, city.owner, to) do
      garrison = for u <- units, {u.x, u.y, plane_index(u.plane)} == from, do: u.index
      base = Cities.block_range() |> elem(0)

      raw =
        raw
        |> put(base + index * @city_record + 15, <<x, y, plane>>)
        |> move_units(garrison, to)

      {raw, followed} = follow_wizard(raw, from, to, city.owner)

      {:ok, raw,
       %{
         moved: :city,
         from: from,
         to: to,
         garrison: length(garrison),
         followed: followed,
         stale: [:city_road_links]
       }}
    end
  end

  @doc """
  Moves tower `index` (its position in `Sites.parse/1`'s `:towers`) to `{x, y}`:
  the tower record, both encounter records, and units standing on the tile on
  either plane. Refuses a destination off the map or on another tower.
  """
  @spec move_tower(binary(), non_neg_integer(), {non_neg_integer(), non_neg_integer()}) ::
          result()
  def move_tower(raw, index, {x, y} = to) do
    with :ok <- check_position({x, y, 0}),
         {:ok, tower} <- fetch_tower(raw, index),
         towers = tower_records(raw),
         :ok <- check_tower_free(towers, tower, to),
         {:ok, units} <- Units.parse(raw) do
      from = {tower.x, tower.y}
      {tower_base, _} = Sites.towers_range()

      sides =
        for e <- encounter_records(raw), e.kind == @tower_kind, {e.x, e.y} == from, do: e.index

      garrison = for u <- units, {u.x, u.y} == from, do: u.index

      raw =
        raw
        |> put(tower_base + index * @tower_record, <<x, y>>)
        |> then(fn r -> Enum.reduce(sides, r, &put_encounter_xy(&2, &1, x, y)) end)
        |> then(fn r -> Enum.reduce(garrison, r, &put_unit_xy(&2, &1, x, y)) end)

      {:ok, raw,
       %{
         moved: :tower,
         from: from,
         to: to,
         encounter_sides: length(sides),
         garrison: length(garrison),
         stale: []
       }}
    end
  end

  @doc """
  Moves encounter `index` (a lair, cave, temple, ruin, keep…) to `{x, y, plane}`.
  Towers and node guardians are refused: they move with their tower or node.
  """
  @spec move_encounter(binary(), non_neg_integer(), position()) :: result()
  def move_encounter(raw, index, {x, y, plane} = to) do
    with :ok <- check_position(to),
         {:ok, encounter} <- fetch_encounter(raw, index),
         :ok <- check_movable_encounter(encounter),
         :ok <- check_encounter_free(raw, encounter, to) do
      {base, _} = Sites.encounters_range()

      {:ok, put(raw, base + index * @encounter_record, <<x, y, plane>>),
       %{
         moved: :encounter,
         from: {encounter.x, encounter.y, encounter.plane},
         to: to,
         stale: []
       }}
    end
  end

  # -- checks -------------------------------------------------------------

  defp check_position({x, y, plane})
       when is_integer(x) and is_integer(y) and x in 0..(@width - 1)//1 and
              y in 0..(@height - 1)//1 and plane in [0, 1],
       do: :ok

  defp check_position(_), do: {:error, :off_map}

  defp check_city_free(cities, city, {x, y, plane}) do
    if Enum.any?(
         cities,
         &(&1.index != city.index and {&1.x, &1.y, plane_index(&1.plane)} == {x, y, plane})
       ),
       do: {:error, :city_at_destination},
       else: :ok
  end

  defp check_foreign_units(units, owner, {x, y, plane}) do
    if Enum.any?(
         units,
         &({&1.x, &1.y, plane_index(&1.plane)} == {x, y, plane} and &1.owner != owner)
       ),
       do: {:error, :foreign_units_at_destination},
       else: :ok
  end

  defp check_tower_free(towers, tower, {x, y}) do
    if Enum.any?(towers, &(&1.index != tower.index and {&1.x, &1.y} == {x, y})),
      do: {:error, :tower_at_destination},
      else: :ok
  end

  defp check_movable_encounter(%{kind: @tower_kind}), do: {:error, :move_the_tower}

  defp check_movable_encounter(%{kind: kind}) when kind in @node_guardian_kinds,
    do: {:error, :move_the_node}

  defp check_movable_encounter(_), do: :ok

  defp check_encounter_free(raw, encounter, {x, y, plane}) do
    taken =
      Enum.any?(encounter_records(raw), fn e ->
        e.index != encounter.index and {e.x, e.y, e.plane} == {x, y, plane}
      end)

    if taken, do: {:error, :encounter_at_destination}, else: :ok
  end

  # -- records ------------------------------------------------------------
  #
  # `Sites.parse/1` drops records it cannot read, so a position in its lists
  # is not a record index. These read the records with their real index.

  defp tower_records(raw) do
    {base, _} = Sites.towers_range()

    for i <- 0..5,
        <<x, y, _::binary>> = record = binary_part(raw, base + i * @tower_record, @tower_record),
        record != <<0, 0, 0, 0>>,
        x < @width and y < @height,
        do: %{index: i, x: x, y: y}
  end

  defp fetch_tower(raw, index) do
    case Enum.find(tower_records(raw), &(&1.index == index)) do
      nil -> {:error, :no_such_tower}
      tower -> {:ok, tower}
    end
  end

  # Live encounter slots. Empty slots are all zero bytes, which read as a kind-0
  # record at (0, 0); `intact` or any guard byte tells a real record apart.
  defp encounter_records(raw) do
    {base, _} = Sites.encounters_range()

    for i <- 0..101,
        <<x, y, plane, _intact, kind, _::binary>> =
          record =
          binary_part(raw, base + i * @encounter_record, @encounter_record),
        record != <<0::size(@encounter_record * 8)>>,
        x < @width and y < @height and plane in [0, 1],
        do: %{index: i, x: x, y: y, plane: plane, kind: kind}
  end

  defp fetch_encounter(raw, index) do
    case Enum.find(encounter_records(raw), &(&1.index == index)) do
      nil -> {:error, :no_such_encounter}
      encounter -> {:ok, encounter}
    end
  end

  defp fetch(list, index, error) do
    case Enum.find(list, &(&1.index == index)) do
      nil -> {:error, error}
      found -> {:ok, found}
    end
  end

  # -- writes -------------------------------------------------------------

  defp move_units(raw, indexes, {x, y, plane}) do
    {base, _} = Units.block_range()
    Enum.reduce(indexes, raw, &put(&2, base + &1 * @unit_record, <<x, y, plane>>))
  end

  defp put_unit_xy(raw, index, x, y) do
    {base, _} = Units.block_range()
    put(raw, base + index * @unit_record, <<x, y>>)
  end

  defp put_encounter_xy(raw, index, x, y) do
    {base, _} = Sites.encounters_range()
    put(raw, base + index * @encounter_record, <<x, y>>)
  end

  # The owner's summoning circle and fortress follow the city when they sit on it.
  defp follow_wizard(raw, {fx, fy, fplane}, {x, y, plane}, owner) when owner in 0..5 do
    {wizards, _} = Wizards.block_range()
    at = wizards + owner * @wizard_record

    circle? =
      owner < @wizards and
        {i16(raw, at + @circle_x), i16(raw, at + @circle_y), i16(raw, at + @circle_plane)} ==
          {fx, fy, fplane}

    raw =
      if circle? do
        raw
        |> put(at + @circle_x, <<x::little-signed-16>>)
        |> put(at + @circle_y, <<y::little-signed-16>>)
        |> put(at + @circle_plane, <<plane::little-signed-16>>)
      else
        raw
      end

    fortress = @fortress_offset + owner * 4

    fortress? =
      owner < @fortress_records and
        match?(<<^fx, ^fy, ^fplane, _>>, binary_part(raw, fortress, 4))

    raw =
      if fortress? do
        <<_, _, _, active>> = binary_part(raw, fortress, 4)
        put(raw, fortress, <<x, y, plane, active>>)
      else
        raw
      end

    {raw, Enum.filter([circle? && :summoning_circle, fortress? && :fortress], & &1)}
  end

  defp follow_wizard(raw, _from, _to, _owner), do: {raw, []}

  defp i16(raw, at) do
    <<value::little-signed-16>> = binary_part(raw, at, 2)
    value
  end

  defp put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  defp plane_index(:arcanus), do: 0
  defp plane_index(:myrror), do: 1
end
