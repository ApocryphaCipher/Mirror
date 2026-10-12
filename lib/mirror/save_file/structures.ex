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
    * **City road links** (`+101`) are left as they are: the game rebuilds them
      from the roads and the city positions when it loads a save (checked
      2026-10-11: a save with stale links came out of the load with none, while
      the untouched save kept its real ones; STORY-019).
    * **Units' status and go-to target** are cleared only by `move_units/3` (a go-to order);
      `docs/reference/unit-movement.md` has the bytes, and what status 1 means is a guess.

  Each kind of move was loaded in the real game (STORY-019 has the results);
  `docs/reference/real-game-acceptance.md` says how to check one.
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
        |> relocate_units(garrison, to)

      {raw, followed} = follow_wizard(raw, from, to, city.owner)

      {:ok, raw,
       %{
         moved: :city,
         from: from,
         to: to,
         garrison: length(garrison),
         followed: followed
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
         warnings: water_planes(raw, to)
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
         to: to
       }}
    end
  end

  # A tower stands on both planes, so its tile should be land on both. The game
  # loads a tower on ocean (checked 2026-10-10: Myrror ocean, slot 6 of STORY-019),
  # which only land-bound units cannot then reach, so this is a warning.
  # Land is a non-zero landmass id (Mirror.Landmass, classic-terrain-format.md).
  @landmass 0x4D98
  @plane_tiles @width * @height

  defp water_planes(raw, {x, y}) do
    for plane <- [0, 1],
        byte_size(raw) >= @landmass + 2 * @plane_tiles,
        :binary.at(raw, @landmass + plane * @plane_tiles + y * @width + x) == 0,
        do: {:water, if(plane == 0, do: :arcanus, else: :myrror)}
  end

  @name_bytes 13
  @max_population 25

  @doc """
  Changes a city's `name`, `population`, `buildings` and/or `enchantments` (STORY-020), as a keyword list:
  `edit_city(raw, index, name: "Hialanth", population: 6, buildings: [16, 23])`.

  * `name`: trimmed, 1 to #{@name_bytes} printable ASCII characters (the field is 14 bytes with a
    NUL), and it fills the whole field, so no tail of the old name is left behind. Nothing beyond
    ASCII: the game's font has no "ü", and a name saved with one showed as "Zrich" (checked in
    the game, 2026-10-11).
  * `population`: the byte at `+20`, in thousands, 1 to #{@max_population} (*guess* for the upper
    end: the largest city seen is 25). The size class (`+19`) is left alone: the game does not
    recompute it from the population, on load or after a turn (checked 2026-10-11: pop 12 and 20
    stayed Village), and across the saves here the classes overlap in population, so it is not a
    function of it.
  * `buildings`: a list of building ids (3 to 35, see `Mirror.SaveFile.Cities.building_name/1`);
    the city ends up with exactly those, built or replaced. The game's own rule is followed, from
    `BUILDDAT.LBX`: buildings that are no longer wanted go first, and one that had replaced another
    (a Temple over a Shrine) brings it back as built; then each added building marks the one it
    replaces as replaced (`0`), when that one is there. A building whose predecessor is absent is
    just built. Needs (a Shrine wants a Builders' Hall) are **not** enforced: neutral cities in
    saves break them. Ids outside 3..35 give `{:error, :bad_buildings}`.
  * `race`: the byte at `+14`, 0 to 13 (`Mirror.SaveFile.Cities.races/0`). Anything else the game
    derives from it (what the city can build, how its screen looks) is not touched.
  * `owner`: the byte at `+18`, a wizard record 0 to 4 or 5 for neutral. The units standing on
    the city's tile that belong to the old owner change hands with it, so a garrison is never
    left inside a city that is not theirs (the result's `units_handed_over` counts them). **The
    city's enchantments are cleared** (`enchantments_cleared` counts them): which would survive a
    change of owner is not worked out, and wiping them is the simple rule. An `enchantments:`
    change in the same call is applied after the wipe. Giving a city to its current owner changes
    nothing. A city
    that is a wizard's fortress or summoning circle is refused with `{:error, :capital}`: the
    wizard record would still point at a city he no longer owns.
  * `enchantments`: a map `%{name => caster | nil}` over the city enchantment names of
    `Mirror.SaveFile.Cities.enchantment_names/0`; `nil` clears one, a caster `0..5` (the wizard
    record, 5 being the neutral one) sets it. The byte (`+67 + slot`) is the caster's index plus
    one, 0 for none, and only the named slots are written. An unknown name or a caster outside
    `0..5` gives `{:error, :bad_enchantments}`.

  Returns `{:ok, raw, %{changed: [...]}}` or `{:error, reason}` (`:bad_name`, `:bad_population`,
  `:bad_buildings`, `:bad_enchantments`, `:bad_race`, `:bad_owner`, `:capital`,
  `:no_such_city` or `{:unknown_field, field}`); nothing is written if any
  value is refused.
  """
  @spec edit_city(binary(), non_neg_integer(), keyword()) :: result()
  def edit_city(raw, index, changes) when is_list(changes) do
    with {:ok, cities} <- Cities.parse(raw),
         {:ok, city} <- fetch(cities, index, :no_such_city),
         {:ok, edits} <- city_edits(changes),
         edits = edits |> drop_same_owner(city) |> owner_first(),
         :ok <- check_owner_change(raw, city, edits) do
      base = elem(Cities.block_range(), 0) + index * @city_record
      original = raw

      raw =
        Enum.reduce(edits, raw, fn
          {:name, bytes}, acc ->
            put(acc, base, bytes)

          {:population, n}, acc ->
            put(acc, base + 20, <<n>>)

          {:race, race}, acc ->
            put(acc, base + 14, <<race>>)

          {:owner, owner}, acc ->
            acc
            |> put(base + 18, <<owner>>)
            |> put(base + 67, :binary.copy(<<0>>, 26))
            |> hand_over_units(city, owner)

          {:buildings, ids}, acc ->
            put(acc, base + 31, set_buildings(binary_part(acc, base + 31, 36), ids))

          {:enchantments, wanted}, acc ->
            Enum.reduce(wanted, acc, fn {name, caster}, inner ->
              slot = Enum.find_index(Cities.enchantment_names(), &(&1 == name))
              put(inner, base + 67 + slot, <<if(caster, do: caster + 1, else: 0)>>)
            end)
        end)

      handed =
        if Keyword.has_key?(edits, :owner), do: garrison_indexes(units(original), city), else: []

      cleared =
        if Keyword.has_key?(edits, :owner),
          do: Enum.count(:binary.bin_to_list(binary_part(original, base + 67, 26)), &(&1 != 0)),
          else: 0

      {:ok, raw,
       %{
         changed: Keyword.keys(edits),
         units_handed_over: length(handed),
         enchantments_cleared: cleared
       }}
    end
  end

  # Giving a city to its owner is no edit; and the owner edit goes first, so the enchantments
  # it clears are not the ones the same call sets.
  defp drop_same_owner(edits, city),
    do: Enum.reject(edits, &(&1 == {:owner, city.owner}))

  defp owner_first(edits), do: Enum.sort_by(edits, fn {field, _} -> field != :owner end)

  defp units(raw) do
    case Units.parse(raw) do
      {:ok, units} -> units
      _ -> []
    end
  end

  # The units standing on the city's tile that belong to its current owner.
  defp garrison_indexes(units, city) do
    for u <- units,
        {u.x, u.y, plane_index(u.plane)} == {city.x, city.y, plane_index(city.plane)},
        u.owner == city.owner,
        do: u.index
  end

  defp hand_over_units(raw, city, owner) do
    {base, _} = Units.block_range()

    raw
    |> units()
    |> garrison_indexes(city)
    |> Enum.reduce(raw, &put(&2, base + &1 * @unit_record + 3, <<owner>>))
  end

  # A wizard's fortress and summoning circle name the city they are in; changing hands would
  # leave the wizard record pointing at a city that is not his. Only an active fortress record and
  # a named wizard count: zeroed records for unused slots are not a capital at (0, 0).
  defp check_owner_change(raw, city, edits) do
    cond do
      not Keyword.has_key?(edits, :owner) -> :ok
      capital?(raw, city) -> {:error, :capital}
      true -> :ok
    end
  end

  defp capital?(raw, city) do
    here = {city.x, city.y, plane_index(city.plane)}
    {wizards, _} = Wizards.block_range()

    fortress? =
      Enum.any?(0..(@fortress_records - 1), fn i ->
        <<x, y, plane, active>> = binary_part(raw, @fortress_offset + i * 4, 4)
        active != 0 and {x, y, plane} == here
      end)

    circle? =
      Enum.any?(0..(@wizards - 2), fn owner ->
        at = wizards + owner * @wizard_record

        # an unused wizard record (no name) has a zeroed circle, which is not a city at (0, 0)
        :binary.at(raw, at + 1) != 0 and
          {i16(raw, at + @circle_x), i16(raw, at + @circle_y), i16(raw, at + @circle_plane)} ==
            here
      end)

    fortress? or circle?
  end

  defp city_edits(changes) do
    Enum.reduce_while(changes, {:ok, []}, fn
      {:name, name}, {:ok, acc} ->
        case city_name_bytes(name) do
          {:ok, bytes} -> {:cont, {:ok, [{:name, bytes} | acc]}}
          error -> {:halt, error}
        end

      {:population, n}, {:ok, acc} when is_integer(n) and n in 1..@max_population//1 ->
        {:cont, {:ok, [{:population, n} | acc]}}

      {:population, _}, _acc ->
        {:halt, {:error, :bad_population}}

      {:race, race}, {:ok, acc} ->
        if race in 0..13//1,
          do: {:cont, {:ok, [{:race, race} | acc]}},
          else: {:halt, {:error, :bad_race}}

      {:owner, owner}, {:ok, acc} ->
        if owner in 0..5//1,
          do: {:cont, {:ok, [{:owner, owner} | acc]}},
          else: {:halt, {:error, :bad_owner}}

      {:enchantments, wanted}, {:ok, acc} ->
        if is_map(wanted) and
             Enum.all?(wanted, fn {name, caster} ->
               name in Cities.enchantment_names() and (is_nil(caster) or caster in 0..5//1)
             end),
           do: {:cont, {:ok, [{:enchantments, wanted} | acc]}},
           else: {:halt, {:error, :bad_enchantments}}

      {:buildings, ids}, {:ok, acc} ->
        if is_list(ids) and Enum.all?(ids, &(&1 in 3..35//1)),
          do: {:cont, {:ok, [{:buildings, Enum.uniq(ids)} | acc]}},
          else: {:halt, {:error, :bad_buildings}}

      {other, _}, _acc ->
        {:halt, {:error, {:unknown_field, other}}}
    end)
    |> then(fn
      {:ok, edits} -> {:ok, Enum.reverse(edits)}
      error -> error
    end)
  end

  # The city's 36 building bytes (`+31..+66`: 1 built, 0 replaced, 0xFF none) after making
  # exactly `wanted` present.
  defp set_buildings(bytes, wanted) do
    state = for {b, id} <- Enum.with_index(:binary.bin_to_list(bytes)), into: %{}, do: {id, b}
    present? = fn st, id -> id > 0 and Map.fetch!(st, id) in [0, 1] end

    current = for id <- 3..35, present?.(state, id), do: id
    wanted = MapSet.new(wanted)

    state =
      current
      |> Enum.reject(&MapSet.member?(wanted, &1))
      |> Enum.reduce(state, fn id, st ->
        st = Map.put(st, id, 0xFF)

        case Cities.building_replaces(id) do
          nil -> st
          replaced -> restore_replaced(st, replaced, wanted)
        end
      end)

    state =
      wanted
      |> Enum.sort()
      |> Enum.reduce(state, fn id, st ->
        if present?.(st, id) do
          st
        else
          st = Map.put(st, id, 1)

          case Cities.building_replaces(id) do
            replaced when is_integer(replaced) ->
              if present?.(st, replaced), do: Map.put(st, replaced, 0), else: st

            nil ->
              st
          end
        end
      end)

    for id <- 0..35, into: <<>>, do: <<Map.fetch!(state, id)>>
  end

  # A replaced building comes back as built when nothing present still replaces it, and the
  # caller asked for it: one that is not in `wanted` stays gone, whatever order they are handled in.
  defp restore_replaced(state, replaced, wanted) do
    still_replaced? =
      Enum.any?(3..35, fn id ->
        Cities.building_replaces(id) == replaced and Map.fetch!(state, id) in [0, 1]
      end)

    if MapSet.member?(wanted, replaced) and Map.fetch!(state, replaced) == 0 and
         not still_replaced?,
       do: Map.put(state, replaced, 1),
       else: state
  end

  defp city_name_bytes(name) when is_binary(name) do
    trimmed = String.trim(name)

    if byte_size(trimmed) in 1..@name_bytes//1 and trimmed =~ ~r/\A[\x20-\x7e]+\z/ do
      {:ok, trimmed <> :binary.copy(<<0>>, @name_bytes + 1 - byte_size(trimmed))}
    else
      {:error, :bad_name}
    end
  end

  defp city_name_bytes(_name), do: {:error, :bad_name}

  @max_stack 9
  @goto_status 3

  @doc """
  Moves the units `indexes` (record indexes in the units block, as in `Units.stack/2`) to
  `{x, y, plane}` (STORY-019, units).

  They must be live units of one owner. Refused: a destination off the map; a city of another
  owner there; units of another owner there; a stack that would hold more than #{@max_stack} units
  (the game's limit, and the most seen in any save). Only x, y and plane are written, plus the
  go-to order: a unit with a go-to target (status #{@goto_status}, always with a target in the saves, or a
  target on a status 0 unit) gets status 0 and no target, so it does not walk off again. Other
  statuses (1 sentry, 4 idle after a turn) are left alone. Checked in the game: a spirit with such
  an order stayed where it was put after an End Turn.

  The result's `warnings` lists units that cannot stand there by themselves
  (`{:cannot_be_on_water, types}` for a land unit on a water tile, `{:boat_on_land, types}` for
  a boat on land outside a city), judged from `Mirror.SaveFile.UnitMovement`. A land unit riding
  a boat in the destination stack is fine and is not warned about. Water is a landmass id of 0
  outside the polar rows; it is a warning, not a refusal, since the game loads such saves.
  """
  @spec move_units(binary(), [non_neg_integer()], position()) :: result()
  def move_units(raw, indexes, {x, y, plane} = to) when is_list(indexes) do
    with :ok <- check_position(to),
         {:ok, all} <- Units.parse(raw),
         {:ok, moving} <- pick_units(all, indexes),
         {:ok, owner} <- single_owner(moving),
         {:ok, cities} <- Cities.parse(raw),
         :ok <- check_no_foreign_city(cities, owner, to),
         :ok <- check_no_foreign_units(all, indexes, owner, to),
         :ok <- check_stack_room(all, indexes, to) do
      {base, _} = Units.block_range()

      raw =
        Enum.reduce(indexes, raw, fn index, acc ->
          at = base + index * @unit_record
          <<_::binary-size(9), dx, dy, status, _::binary>> = binary_part(acc, at, 12)
          acc = put(acc, at, <<x, y, plane>>)

          if status == @goto_status or ((dx != 0 or dy != 0) and status == 0),
            do: put(acc, at + 9, <<0, 0, 0>>),
            else: acc
        end)

      {:ok, raw,
       %{
         moved: :units,
         count: length(indexes),
         from: moving |> Enum.map(&{&1.x, &1.y, plane_index(&1.plane)}) |> Enum.uniq(),
         to: to,
         warnings: unit_warnings(raw, all, moving, to, cities)
       }}
    end
  end

  defp pick_units(_all, []), do: {:error, :no_units}

  defp pick_units(all, indexes) do
    by_index = Map.new(all, &{&1.index, &1})

    if Enum.all?(indexes, &Map.has_key?(by_index, &1)) and indexes == Enum.uniq(indexes),
      do: {:ok, Enum.map(indexes, &Map.fetch!(by_index, &1))},
      else: {:error, :no_such_unit}
  end

  defp single_owner(moving) do
    case moving |> Enum.map(& &1.owner) |> Enum.uniq() do
      [owner] -> {:ok, owner}
      _ -> {:error, :mixed_owners}
    end
  end

  defp check_no_foreign_city(cities, owner, {x, y, plane}) do
    if Enum.any?(
         cities,
         &({&1.x, &1.y, plane_index(&1.plane)} == {x, y, plane} and &1.owner != owner)
       ),
       do: {:error, :foreign_city_at_destination},
       else: :ok
  end

  defp check_no_foreign_units(all, indexes, owner, {x, y, plane}) do
    if Enum.any?(
         all,
         &(&1.index not in indexes and {&1.x, &1.y, plane_index(&1.plane)} == {x, y, plane} and
             &1.owner != owner)
       ),
       do: {:error, :foreign_units_at_destination},
       else: :ok
  end

  defp check_stack_room(all, indexes, {x, y, plane}) do
    staying =
      Enum.count(
        all,
        &(&1.index not in indexes and {&1.x, &1.y, plane_index(&1.plane)} == {x, y, plane})
      )

    if staying + length(indexes) > @max_stack, do: {:error, :stack_full}, else: :ok
  end

  @polar_rows [0, 1, 38, 39]

  defp unit_warnings(raw, all, moving, {x, y, plane}, cities) do
    land? = fn ->
      byte_size(raw) < @landmass + 2 * @plane_tiles or
        y in @polar_rows or
        :binary.at(raw, @landmass + plane * @plane_tiles + y * @width + x) != 0
    end

    city_here? = Enum.any?(cities, &({&1.x, &1.y, plane_index(&1.plane)} == {x, y, plane}))
    ids = Enum.map(moving, & &1.index)

    boat_in_stack? =
      Enum.any?(all, fn u ->
        {u.x, u.y, plane_index(u.plane)} == {x, y, plane} and u.index not in ids and
          Mirror.SaveFile.UnitMovement.sails?(u.type)
      end) or Enum.any?(moving, &Mirror.SaveFile.UnitMovement.sails?(&1.type))

    stuck =
      for u <- moving,
          not Mirror.SaveFile.UnitMovement.can_be_on_water?(
            u.type,
            enchantments(raw, u.index),
            mutations(raw, u.index)
          ),
          do: u.type

    boats = for u <- moving, Mirror.SaveFile.UnitMovement.sails?(u.type), do: u.type

    cond do
      land?.() and not city_here? and boats != [] ->
        [{:boat_on_land, Enum.uniq(boats)}]

      not land?.() and not boat_in_stack? and stuck != [] ->
        [{:cannot_be_on_water, Enum.uniq(stuck)}]

      true ->
        []
    end
  end

  defp mutations(raw, index) do
    {base, _} = Units.block_range()
    :binary.at(raw, base + index * @unit_record + 23)
  end

  defp enchantments(raw, index) do
    {base, _} = Units.block_range()
    <<value::little-32>> = binary_part(raw, base + index * @unit_record + 24, 4)
    value
  end

  @doc """
  The tower standing on `{x, y}` (towers stand on both planes), as
  `%{index, x, y}`, or `nil`.
  """
  @spec tower_at(binary(), integer(), integer()) :: map() | nil
  def tower_at(raw, x, y), do: Enum.find(tower_records(raw), &({&1.x, &1.y} == {x, y}))

  @doc """
  The movable encounter (a lair, cave, temple, ruin or keep: not a tower side or a
  node guardian) on `{x, y}` of `plane` (0 or 1), as `%{index, x, y, plane, kind}`,
  or `nil`.
  """
  @spec encounter_at(binary(), integer(), integer(), 0 | 1) :: map() | nil
  def encounter_at(raw, x, y, plane) do
    Enum.find(encounter_records(raw), fn e ->
      {e.x, e.y, e.plane} == {x, y, plane} and e.kind != @tower_kind and
        e.kind not in @node_guardian_kinds
    end)
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

  defp relocate_units(raw, indexes, {x, y, plane}) do
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
