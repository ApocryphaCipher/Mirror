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

    * **A node's terrain.** `move_node/4` writes the node's records (position, aura squares,
      guardians, the units on it) and says which tile the new spot becomes; the map edits are
      `Mirror.NodeTerrain`'s, made where the editor's planes are. Nodes move on their own plane only.
    * **City road links** (`+101`) are left as they are: the game rebuilds them
      from the roads and the city positions when it loads a save (checked
      2026-10-11: a save with stale links came out of the load with none, while
      the untouched save kept its real ones; STORY-019).
    * **Units' status and go-to target** are cleared only by `move_units/3` (a go-to order);
      `docs/reference/unit-movement.md` has the bytes, and what status 1 means is a guess.

  Each kind of move was loaded in the real game (STORY-019 has the results);
  `docs/reference/real-game-acceptance.md` says how to check one.
  """

  alias Mirror.SaveFile.{Cities, Encounters, Sites, Units, Wizards}

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

  @max_guards 8
  @max_reward 30_000

  @doc """
  Changes an encounter zone (a lair, cave, temple, ruin, keep, node's guardians or a Tower of
  Wizardry; STORY-020) by its record index, as a keyword list:

      edit_encounter(raw, index, intact: false, gold: 100, guards: %{1 => {189, 3}, 2 => nil})

  * `intact`: `true` (not yet cleared) or `false` (the byte at `+3`).
  * `guards`: a map from slot (1 or 2) to `{unit_type, count}` or `nil` to empty the slot. The
    type is 0..197 and the count 1..#{@max_guards} (the most seen). The count byte is written with both
    nibbles equal, as every full slot in the saves is (low nibble = left, high = starting count).
    An empty slot is type 0, count 0.
  * `gold` and `mana`: 0..#{@max_reward}, the i16 values at `+10` and `+12` (the largest seen are
    620 and 330).
  * `item_count`: 0..3, the byte at `+16`: **how many items the game makes when the site is cleared**
    (checked in the game, 2026-10-15: a count of 1 gave one item, 2 gave two). The three numbers after it
    (`+18`) do not gate the reward, an item came with the value at 0, 100, 9000 and 30000, so they are left alone.

  A Tower of Wizardry is two records (an Arcanus and a Myrror side) with the same guards, and
  the game clears both together, so a tower is edited on **both**. The spell code (`+14`), flags,
  items and the unknown bytes are left alone.

  Returns `{:ok, raw, %{changed: [...], records: [indexes written]}}` or `{:error, reason}`
  (`:no_such_encounter`, `:bad_intact`, `:bad_guards`, `:bad_gold`, `:bad_mana`, `:bad_item_count` or
  `{:unknown_field, field}`); nothing is written if any value is refused.
  """
  @spec edit_encounter(binary(), non_neg_integer(), keyword()) :: result()
  def edit_encounter(raw, index, changes) when is_list(changes) do
    with %{} = record <- Encounters.get(raw, index) || {:error, :no_such_encounter},
         {:ok, edits} <- encounter_edits(changes) do
      targets =
        if record.kind == @tower_kind,
          do:
            for(
              e <- Encounters.all(raw),
              e.kind == @tower_kind,
              {e.x, e.y} == {record.x, record.y},
              do: e.index
            ),
          else: [index]

      {base, _} = Sites.encounters_range()

      raw =
        Enum.reduce(targets, raw, fn target, acc ->
          Enum.reduce(
            edits,
            acc,
            &write_encounter_edit(&1, &2, base + target * @encounter_record)
          )
        end)

      {:ok, raw, %{changed: Keyword.keys(edits), records: targets}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_encounter_edit({:intact, intact?}, raw, at),
    do: put(raw, at + 3, <<if(intact?, do: 1, else: 0)>>)

  defp write_encounter_edit({:gold, n}, raw, at), do: put(raw, at + 10, <<n::little-signed-16>>)
  defp write_encounter_edit({:mana, n}, raw, at), do: put(raw, at + 12, <<n::little-signed-16>>)
  defp write_encounter_edit({:item_count, n}, raw, at), do: put(raw, at + 16, <<n>>)

  defp write_encounter_edit({:guards, slots}, raw, at) do
    Enum.reduce(slots, raw, fn {slot, guard}, acc ->
      offset = at + if(slot == 1, do: 5, else: 7)

      case guard do
        nil -> put(acc, offset, <<0, 0>>)
        {type, count} -> put(acc, offset, <<type, count * 16 + count>>)
      end
    end)
  end

  defp encounter_edits(changes) do
    changes
    |> Enum.reduce_while({:ok, []}, fn
      {:intact, v}, {:ok, acc} when is_boolean(v) ->
        {:cont, {:ok, [{:intact, v} | acc]}}

      {:intact, _}, _ ->
        {:halt, {:error, :bad_intact}}

      {:gold, n}, {:ok, acc} when is_integer(n) and n in 0..@max_reward//1 ->
        {:cont, {:ok, [{:gold, n} | acc]}}

      {:gold, _}, _ ->
        {:halt, {:error, :bad_gold}}

      {:mana, n}, {:ok, acc} when is_integer(n) and n in 0..@max_reward//1 ->
        {:cont, {:ok, [{:mana, n} | acc]}}

      {:mana, _}, _ ->
        {:halt, {:error, :bad_mana}}

      {:item_count, n}, {:ok, acc} when is_integer(n) and n in 0..3//1 ->
        {:cont, {:ok, [{:item_count, n} | acc]}}

      {:item_count, _}, _ ->
        {:halt, {:error, :bad_item_count}}

      {:guards, slots}, {:ok, acc} ->
        if valid_guards?(slots),
          do: {:cont, {:ok, [{:guards, slots} | acc]}},
          else: {:halt, {:error, :bad_guards}}

      {other, _}, _ ->
        {:halt, {:error, {:unknown_field, other}}}
    end)
    |> then(fn
      {:ok, edits} -> {:ok, Enum.reverse(edits)}
      error -> error
    end)
  end

  defp valid_guards?(slots) when is_map(slots) and map_size(slots) > 0 do
    Enum.all?(slots, fn
      {slot, nil} ->
        slot in [1, 2]

      {slot, {type, count}} ->
        slot in [1, 2] and is_integer(type) and type in 0..197//1 and is_integer(count) and
          count in 1..@max_guards//1

      _ ->
        false
    end)
  end

  defp valid_guards?(_slots), do: false

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

  @max_level 9
  @max_experience 30_000
  @hero_types 0..34

  @doc """
  Edits live units' own fields, the same change for each of `indexes`: `level:` (`+12`, 0 to
  #{@max_level}), `experience:` (`+14`, i16, 0 to #{@max_experience}), `damage:` (`+17`, 0 to 255)
  and `owner:` (`+3`, 0 to 5, 5 being neutral). Only those bytes change, except that a new owner
  also **clears a go-to order**, as moving a unit does. Refused: a bad value (`:bad_level`,
  `:bad_experience`, `:bad_damage`, `:bad_owner`), an empty list (`:no_units`), a unit that is not
  live (`:no_such_unit`), and a new owner for **a hero** (`:hero_owner`: a hero is also an entry in
  his wizard's hero list, which this does not edit), for units on a tile where **another owner's
  city** (`:foreign_city_here`) or **other units that stay behind** (`:foreign_units_here`) are, since
  the game keeps one owner to a tile.

  Level and experience are written as given. The game shows the level byte as it is on load, but
  works it out from the experience again at End Turn (and caps a normal unit's experience at 120),
  so a lasting level is made with experience.
  """
  @spec edit_units(binary(), [non_neg_integer()], keyword()) :: result()
  def edit_units(_raw, [], _changes), do: {:error, :no_units}

  def edit_units(raw, indexes, changes) when is_list(indexes) and is_list(changes) do
    with {:ok, all} <- Units.parse(raw),
         {:ok, picked} <- pick_units(all, indexes),
         {:ok, edits} <- unit_edits(changes),
         :ok <- check_unit_owner(raw, all, picked, edits[:owner]) do
      {base, _} = Units.block_range()

      raw =
        Enum.reduce(indexes, raw, fn index, acc ->
          at = base + index * @unit_record

          Enum.reduce(edits, acc, fn
            {:level, v}, acc ->
              put(acc, at + 12, <<v>>)

            {:experience, v}, acc ->
              put(acc, at + 14, <<v::little-signed-16>>)

            {:damage, v}, acc ->
              put(acc, at + 17, <<v>>)

            {:owner, v}, acc ->
              if :binary.at(acc, at + 3) == v,
                do: acc,
                else: acc |> put(at + 3, <<v>>) |> clear_goto(at)
          end)
        end)

      {:ok, raw, %{changed: Keyword.keys(edits), units: length(indexes)}}
    end
  end

  # the wizard records (see `edit_wizard/3`, which defines its own copies further down)
  @hero_wizards 0x9E8
  @hero_wizard_size 0x4C8
  @hero_list_at 0x76
  @hero_entry 28
  @hero_name_max 13

  @doc """
  Edits the hero in `slot` (0 to 5) of wizard `record`'s hero list (STORY-053): `name:` (1 to #{@hero_name_max} printable
  ASCII characters, written NUL-padded to the entry's 14 bytes) and the hero's unit fields `level:`, `experience:` and
  `damage:` (as `edit_units/3`; the game works the level out from experience again at End Turn). The owner is not
  changed here: moving a hero between two wizards' lists is not built.

  Refused: a record that is not a wizard or has no name (`:no_such_wizard`), an empty slot (`:no_such_hero`), a bad name
  (`:bad_hero_name`), a bad unit value (see `edit_units/3`) and an unknown field.
  """
  @spec edit_hero(binary(), non_neg_integer(), non_neg_integer(), keyword()) :: result()
  def edit_hero(raw, record, slot, changes) when is_list(changes) do
    at = @hero_wizards + record * @hero_wizard_size + @hero_list_at + slot * @hero_entry

    with true <-
           record in 0..4//1 and slot in 0..5//1 and
             byte_size(raw) >= @hero_wizards + 5 * @hero_wizard_size,
         true <- :binary.at(raw, @hero_wizards + record * @hero_wizard_size + 1) != 0,
         <<unit::little-signed-16, _::binary>> <- binary_part(raw, at, 2),
         true <- unit >= 0 || {:error, :no_such_hero},
         {name, unit_changes} = Keyword.pop(changes, :name),
         :ok <- hero_name(name),
         {:ok, raw, _} <- edit_hero_unit(raw, unit, unit_changes) do
      raw = if name, do: put(raw, at + 2, String.pad_trailing(name, 14, <<0>>)), else: raw
      {:ok, raw, %{changed: Keyword.keys(changes)}}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_such_wizard}
    end
  end

  defp hero_name(nil), do: :ok

  defp hero_name(name) when is_binary(name) and byte_size(name) in 1..@hero_name_max//1 do
    if String.match?(name, ~r/\A[\x20-\x7E]+\z/) and String.trim(name) != "",
      do: :ok,
      else: {:error, :bad_hero_name}
  end

  defp hero_name(_), do: {:error, :bad_hero_name}

  defp edit_hero_unit(raw, _unit, []), do: {:ok, raw, %{}}
  defp edit_hero_unit(raw, unit, changes), do: edit_unit(raw, unit, changes)

  @item_block 0x6FB8
  @item_record 50
  @item_count 138
  @item_name_max 26
  # What the Create Artifact screen allows for each stat (the premade table's own maxima; the save keeps movement in
  # half points, so its +4 is 8), and what the item record holds: cost u16, abilities u32.
  @item_stat_max %{
    attack: 6,
    to_hit: 3,
    defense: 6,
    movement: 8,
    resistance: 6,
    spell_skill: 20,
    spell_save: 4
  }
  # offsets in the 50-byte item record: stat bytes `+36..+42` in this order
  @item_stat_at %{
    attack: 36,
    to_hit: 37,
    defense: 38,
    movement: 39,
    resistance: 40,
    spell_skill: 41,
    spell_save: 42
  }

  @doc """
  Edits the item at `index` (0 to #{@item_count - 1}) in place (STORY-056), wherever it is carried:

    * `:name` (1 to #{@item_name_max} printable ASCII characters, the longest premade name is #{@item_name_max}; written NUL-padded to the record's 30 bytes)
    * `:cost` (0 to 65535)
    * `:attack` 0 to 6, `:to_hit` 0 to 3, `:defense` 0 to 6, `:movement` 0 to 8 (**half points**, so 8 is the screen's +4),
      `:resistance` 0 to 6, `:spell_skill` 0 to 20, `:spell_save` 0 to 4: the Create Artifact screen's own limits
    * `:abilities` (the u32 power mask, see `Mirror.ItemPowers`)

  The charged spell, its charges, the icon, slot and type are not touched. The editor builds any combination the limits
  allow: whether the game accepts powers that do not fit the item's type is not known (STORY-056).

  Refused: an index with no item (`:no_such_item`: outside the block or a free slot), a bad value (`:bad_item_name`,
  `:bad_item_cost`, `:bad_item_stat`, `:bad_item_abilities`) or an unknown field.
  """
  @spec edit_item(binary(), integer(), keyword()) :: result()
  def edit_item(raw, index, changes) when is_list(changes) do
    with true <-
           (is_integer(index) and index in 0..(@item_count - 1)//1 and
              byte_size(raw) >= @item_block + @item_count * @item_record) ||
             {:error, :no_such_item},
         at = @item_block + index * @item_record,
         true <- :binary.at(raw, at) != 0 || {:error, :no_such_item},
         {:ok, edits} <- item_edits(changes) do
      raw =
        Enum.reduce(edits, raw, fn
          {:name, v}, acc -> put(acc, at, String.pad_trailing(v, 30, <<0>>))
          {:cost, v}, acc -> put(acc, at + 34, <<v::little-16>>)
          {:abilities, v}, acc -> put(acc, at + 46, <<v::little-32>>)
          {stat, v}, acc -> put(acc, at + Map.fetch!(@item_stat_at, stat), <<v>>)
        end)

      {:ok, raw, %{changed: Keyword.keys(edits)}}
    end
  end

  @vault_at 0x120
  @vault_places 4

  @typedoc "Where an item is kept: a hero's item place (the list entry `slot` 0 to 5, `place` 0 to 2) or a vault place 0 to 3."
  @type item_place :: {:hero, 0..5, 0..2} | {:vault, 0..3}

  @doc """
  Moves the item at `from` to the empty place `to` in wizard `record`'s own hero list and vault (STORY-056): an item
  index is written into the target and `-1` into the source. Nothing else changes; the item record is untouched.

  A hero's place has a **slot type** (`+22` of his list entry: 1 melee weapon, 2 bow, 4 staff or wand, 5 armor, 6 misc),
  and the item's slot code (`+32` of its record) has to equal it. *Guess:* the game relies on that match
  (the Items screen puts an item in a slot of its own kind); not seen what it does with a mismatch, so it is refused.

  Refused: a wizard that does not exist (`:no_such_wizard`), nothing at `from` (`:no_item_there`), a hero that is
  not in the list (`:no_such_hero`), an occupied target (`:place_taken`), a hero place of another kind
  (`:wrong_slot`) and the same place twice (`:same_place`). A swap is two moves through a free place.
  """
  @spec move_item(binary(), non_neg_integer(), item_place(), item_place()) :: result()
  def move_item(raw, record, from, to) do
    with :ok <- check_wizard(raw, record),
         {:ok, from_at} <- place_at(raw, record, from),
         {:ok, to_at} <- place_at(raw, record, to),
         :ok <- if(from_at == to_at, do: {:error, :same_place}, else: :ok),
         <<item::little-signed-16>> = binary_part(raw, from_at, 2),
         :ok <- if(item >= 0, do: :ok, else: {:error, :no_item_there}),
         :ok <- item_in_use(raw, item),
         <<target::little-signed-16>> = binary_part(raw, to_at, 2),
         :ok <- if(target < 0, do: :ok, else: {:error, :place_taken}),
         :ok <- slot_fits(raw, record, to, item) do
      raw =
        raw
        |> put(to_at, <<item::little-signed-16>>)
        |> put(from_at, <<-1::little-signed-16>>)

      {:ok, raw, %{moved: item, from: from, to: to}}
    end
  end

  defp check_wizard(raw, record) do
    if record in 0..4//1 and byte_size(raw) >= @hero_wizards + 5 * @hero_wizard_size and
         :binary.at(raw, @hero_wizards + record * @hero_wizard_size + 1) != 0,
       do: :ok,
       else: {:error, :no_such_wizard}
  end

  # The byte offset of the i16 that holds the item index for a place; a hero place needs a hero in that entry.
  defp place_at(raw, record, {:hero, slot, place})
       when slot in 0..5//1 and place in 0..2//1 do
    entry = @hero_wizards + record * @hero_wizard_size + @hero_list_at + slot * @hero_entry

    case binary_part(raw, entry, 2) do
      <<unit::little-signed-16>> when unit >= 0 -> {:ok, entry + 16 + place * 2}
      _ -> {:error, :no_such_hero}
    end
  end

  defp place_at(_raw, record, {:vault, place}) when place in 0..(@vault_places - 1)//1,
    do: {:ok, @hero_wizards + record * @hero_wizard_size + @vault_at + place * 2}

  defp place_at(_raw, _record, _place), do: {:error, :no_item_there}

  defp item_in_use(raw, item) when item < @item_count do
    if :binary.at(raw, @item_block + item * @item_record) != 0,
      do: :ok,
      else: {:error, :no_item_there}
  end

  defp item_in_use(_raw, _item), do: {:error, :no_item_there}

  defp slot_fits(_raw, _record, {:vault, _}, _item), do: :ok

  defp slot_fits(raw, record, place, item),
    do:
      slot_code_fits(raw, record, place, :binary.at(raw, @item_block + item * @item_record + 32))

  defp slot_code_fits(_raw, _record, {:vault, _}, _code), do: :ok

  defp slot_code_fits(raw, record, {:hero, slot, place}, code) do
    entry = @hero_wizards + record * @hero_wizard_size + @hero_list_at + slot * @hero_entry
    <<type::little-signed-16>> = binary_part(raw, entry + 22 + place * 2, 2)
    if type == code, do: :ok, else: {:error, :wrong_slot}
  end

  # The game's own table of which premade items (`ITEMDATA.LBX`, numbered from 1) are already in play: 250 bytes, 1 once
  # the game has made the item, 0 while it can still be handed out. It sits in the last 810 bytes of the save, just
  # before the 35 hero names (kazzmir's loader; SAVE2: ones at 73, 97, 209 and 213, the four premade items in play;
  # the game set 191, 95, 138, 226 and 129 as it made five more in a lair test, 2026-10-15).
  @premade_flags 250
  @save_tail 810
  # Records 136 and 137 are not handed out: the game builds each new item in 136 as well as in its own record
  # (seen three times), so it is treated as the game's working copy. A save keeps 138 records.
  @item_pool 136

  defp set_premade_flag(raw, number, value)
       when is_integer(number) and number in 1..@premade_flags//1 and
              byte_size(raw) >= @item_block + @item_count * @item_record + @save_tail do
    put(raw, byte_size(raw) - @save_tail + number - 1, <<value>>)
  end

  defp set_premade_flag(raw, _number, _value), do: raw

  # Gives the premade number back to the game when the record holding that item (matched by name) is overwritten or
  # blanked: `names` is a map of premade name to number.
  defp release_premade(raw, index, names) do
    case Map.fetch(names, item_name_at(raw, index)) do
      {:ok, number} -> set_premade_flag(raw, number, 0)
      :error -> raw
    end
  end

  defp item_name_at(raw, index),
    do: raw |> binary_part(@item_block + index * @item_record, 30) |> :binary.split(<<0>>) |> hd()

  @doc """
  Fills the place `place` of wizard `record` with the 50-byte item record `item_record` (STORY-056; the premade items
  of `Mirror.ItemData.save_record/1`): a hero's item place or a vault place. The record's slot code must equal a hero
  place's slot type (the editor's rule, as in `move_item/4`).

  If the place already holds an item that nothing else points at, **that item's record is overwritten in place**;
  otherwise the record goes into the first free one (a record with an empty name that no place points at, among the
  first #{@item_pool}) and its index is written into the place. A place holding an item shared with another place
  keeps it there untouched.

  Options: `number:` the premade number of the item, whose **"in play" flag is set** as the game does when it makes
  one; `premade_names:` a map of premade name to number, so that an overwritten item gives its number back.

  Refused: `:no_such_wizard`, `:no_such_hero`, `:no_item_there` (a place that does not exist), `:bad_item_record` (not 50
  bytes, or no name), `:wrong_slot`, and `:no_free_item` when all #{@item_pool} records are in use.
  """
  @spec put_item(binary(), non_neg_integer(), item_place(), binary(), keyword()) :: result()
  def put_item(raw, record, place, item_record, opts \\ [])

  def put_item(raw, record, place, item_record, opts)
      when is_binary(item_record) and byte_size(item_record) == @item_record do
    with :ok <- check_wizard(raw, record),
         {:ok, at} <- place_at(raw, record, place),
         :ok <-
           if(:binary.at(item_record, 0) != 0, do: :ok, else: {:error, :bad_item_record}),
         :ok <- slot_code_fits(raw, record, place, :binary.at(item_record, 32)),
         {:ok, index, overwriting?} <- record_for(raw, at) do
      raw =
        if overwriting?,
          do: release_premade(raw, index, Keyword.get(opts, :premade_names, %{})),
          else: raw

      raw =
        raw
        |> put(@item_block + index * @item_record, item_record)
        |> put(at, <<index::little-signed-16>>)
        |> set_premade_flag(Keyword.get(opts, :number), 1)

      {:ok, raw, %{set: index, place: place}}
    end
  end

  def put_item(_raw, _record, _place, _item_record, _opts), do: {:error, :bad_item_record}

  # The record a place's new item is written to: the one it holds when nothing else shares it, else a free one.
  defp record_for(raw, at) do
    <<current::little-signed-16>> = binary_part(raw, at, 2)

    if current >= 0 and current < @item_pool and item_record_used?(raw, current) and
         item_refs(raw, current) == 1,
       do: {:ok, current, true},
       else: with({:ok, index} <- free_item(raw), do: {:ok, index, false})
  end

  defp item_record_used?(raw, index), do: :binary.at(raw, @item_block + index * @item_record) != 0

  defp free_item(raw) do
    case Enum.find(
           0..(@item_pool - 1),
           &(not item_record_used?(raw, &1) and item_refs(raw, &1) == 0)
         ) do
      nil -> {:error, :no_free_item}
      index -> {:ok, index}
    end
  end

  # How many places (the hero lists' item places, the vaults) of all five wizards point at the item. **An empty hero
  # slot (unit -1) is not counted:** in a real save its three item places read 0, not -1 (SAVE2), which would make
  # item 0 look shared by every empty slot.
  defp item_refs(raw, item) do
    heroes =
      for wizard <- 0..4,
          slot <- 0..5,
          entry = @hero_wizards + wizard * @hero_wizard_size + @hero_list_at + slot * @hero_entry,
          <<unit::little-signed-16>> <- [binary_part(raw, entry, 2)],
          unit >= 0,
          place <- 0..2,
          <<^item::little-signed-16>> <- [binary_part(raw, entry + 16 + place * 2, 2)],
          do: :ref

    vaults =
      for wizard <- 0..4,
          place <- 0..(@vault_places - 1),
          at = @hero_wizards + wizard * @hero_wizard_size + @vault_at + place * 2,
          <<^item::little-signed-16>> <- [binary_part(raw, at, 2)],
          do: :ref

    length(heroes) + length(vaults)
  end

  @doc """
  Empties the place `place` of wizard `record` (`-1`), and **blanks the item's record** (50 zero bytes) when no other
  place points at it, which is how Mirror reads a free record (an empty name; checked only that the game loads and
  reuses such a record, see STORY-056). Option `premade_names:` (premade name to number) gives the item's premade
  number back to the game when its record is blanked.

  Refused: `:no_such_wizard`, `:no_such_hero`, `:no_item_there` (the place is already empty or does not exist).
  """
  @spec clear_item(binary(), non_neg_integer(), item_place(), keyword()) :: result()
  def clear_item(raw, record, place, opts \\ []) do
    with :ok <- check_wizard(raw, record),
         {:ok, at} <- place_at(raw, record, place),
         <<item::little-signed-16>> = binary_part(raw, at, 2),
         :ok <- if(item >= 0, do: :ok, else: {:error, :no_item_there}) do
      raw = put(raw, at, <<-1::little-signed-16>>)

      raw =
        if item < @item_count and item_refs(raw, item) == 0 do
          raw
          |> release_premade(item, Keyword.get(opts, :premade_names, %{}))
          |> put(@item_block + item * @item_record, :binary.copy(<<0>>, @item_record))
        else
          raw
        end

      {:ok, raw, %{cleared: item, place: place}}
    end
  end

  defp item_edits(changes) do
    Enum.reduce_while(changes, {:ok, []}, fn {field, value}, {:ok, acc} ->
      case item_value(field, value) do
        :ok -> {:cont, {:ok, acc ++ [{field, value}]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp item_value(:name, v) when is_binary(v) and byte_size(v) in 1..@item_name_max//1 do
    if String.match?(v, ~r/\A[\x20-\x7E]+\z/) and String.trim(v) != "",
      do: :ok,
      else: {:error, :bad_item_name}
  end

  defp item_value(:name, _), do: {:error, :bad_item_name}
  defp item_value(:cost, v) when is_integer(v) and v in 0..65_535//1, do: :ok
  defp item_value(:cost, _), do: {:error, :bad_item_cost}
  defp item_value(:abilities, v) when is_integer(v) and v in 0..0xFFFFFFFF//1, do: :ok
  defp item_value(:abilities, _), do: {:error, :bad_item_abilities}

  defp item_value(stat, v) when is_map_key(@item_stat_max, stat) do
    if is_integer(v) and v in 0..Map.fetch!(@item_stat_max, stat)//1,
      do: :ok,
      else: {:error, :bad_item_stat}
  end

  defp item_value(other, _), do: {:error, {:unknown_field, other}}

  @doc "One unit's fields; see `edit_units/3`."
  @spec edit_unit(binary(), non_neg_integer(), keyword()) :: result()
  def edit_unit(raw, index, changes), do: edit_units(raw, [index], changes)

  defp clear_goto(raw, at) do
    <<_::binary-size(9), dx, dy, status, _::binary>> = binary_part(raw, at, 12)

    if status == @goto_status or ((dx != 0 or dy != 0) and status == 0),
      do: put(raw, at + 9, <<0, 0, 0>>),
      else: raw
  end

  defp unit_edits(changes) do
    changes
    |> Enum.reduce_while({:ok, []}, fn {field, value}, {:ok, acc} ->
      case unit_value(field, value) do
        :ok -> {:cont, {:ok, [{field, value} | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, edits} -> {:ok, Enum.reverse(edits)}
      error -> error
    end)
  end

  defp unit_value(:level, v) when is_integer(v) and v in 0..@max_level//1, do: :ok
  defp unit_value(:level, _), do: {:error, :bad_level}
  defp unit_value(:experience, v) when is_integer(v) and v in 0..@max_experience//1, do: :ok
  defp unit_value(:experience, _), do: {:error, :bad_experience}
  defp unit_value(:damage, v) when is_integer(v) and v in 0..255//1, do: :ok
  defp unit_value(:damage, _), do: {:error, :bad_damage}
  defp unit_value(:owner, v) when is_integer(v) and v in 0..5//1, do: :ok
  defp unit_value(:owner, _), do: {:error, :bad_owner}
  defp unit_value(other, _), do: {:error, {:unknown_field, other}}

  defp check_unit_owner(_raw, _all, _picked, nil), do: :ok

  defp check_unit_owner(raw, all, picked, owner) do
    changing = Enum.reject(picked, &(&1.owner == owner))
    batch = MapSet.new(picked, & &1.index)
    tiles = changing |> Enum.map(&{&1.x, &1.y, plane_index(&1.plane)}) |> Enum.uniq()

    cond do
      Enum.any?(changing, &(&1.type in @hero_types)) ->
        {:error, :hero_owner}

      Enum.any?(all, fn u ->
        u.owner != owner and not MapSet.member?(batch, u.index) and
            {u.x, u.y, plane_index(u.plane)} in tiles
      end) ->
        {:error, :foreign_units_here}

      foreign_city_on?(raw, tiles, owner) ->
        {:error, :foreign_city_here}

      true ->
        :ok
    end
  end

  defp foreign_city_on?(raw, tiles, owner) do
    case Cities.parse(raw) do
      {:ok, cities} ->
        Enum.any?(cities, &({&1.x, &1.y, plane_index(&1.plane)} in tiles and &1.owner != owner))

      _ ->
        false
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

  @node_record 48
  @node_tiles %{0 => 168, 1 => 169, 2 => 170}

  @doc """
  Moves magic node `index` (its record in the nodes block, 0..29) to `{x, y}` on its own plane
  (STORY-019). `terrain_at` is a function from `{x, y}` to the node plane's terrain tile there
  (the caller has the editor's planes; the raw bytes may be behind them).

  A node is its terrain tile, so the move is a record edit *and* a terrain edit. Written to
  the raw bytes: the node's x and y; its aura squares (the first `power` of them, all shifted by the
  same step); its guardians' encounter record (kinds 1 to 3 at the old tile); and the units
  standing on the node (a melded node holds a spirit), which go with it. The terrain is the
  caller's, since it has the editor's planes: the result's `node_tile` is the tile value the new
  spot becomes (168 Sorcery, 169 Nature, 170 Chaos, on both planes), and
  `Mirror.NodeTerrain.edits/4` makes the map edits, including turning the old tile back into land.

  The destination must be land a node can sit on: grassland, forest, swamp, desert, tundra, hills or
  mountains, outside the polar rows (`Mirror.NodeTerrain.can_land?/2`). Water, a river, a lake, a
  volcano and another node are refused. Also refused: off the map (the aura squares included), the
  node's own tile, a tile holding a city, a tower (on either plane), an encounter, another node,
  units of another owner **joining the node's own units** (a node with no units to bring does not
  care who stands at the destination), or more than #{@max_stack} units in all. A node record counts only
  with a position on the map, a type 0 to 2 and a power of 1 to 20 (every node in every save here has
  5 to 20), so a zeroed slot or a truncated save is `:no_such_node`, not a node at (0, 0).

  Returns `{:ok, raw, report}` or `{:error, reason}` (`:no_such_node`, `:off_map`, `:same_tile`,
  `:aura_off_map`, `:bad_terrain`, `:city_at_destination`, `:tower_at_destination`,
  `:encounter_at_destination`, `:node_at_destination`, `:foreign_units_at_destination`,
  `:stack_full`).
  """
  @spec move_node(binary(), non_neg_integer(), {integer(), integer()}, ({integer(), integer()} ->
                                                                          integer())) ::
          result()
  def move_node(raw, index, {x, y} = to, terrain_at) when is_function(terrain_at, 1) do
    with {:ok, node} <- fetch_node(raw, index),
         :ok <- check_position({x, y, node.plane}),
         :ok <- if(to == {node.x, node.y}, do: {:error, :same_tile}, else: :ok),
         {dx, dy} = {x - node.x, y - node.y},
         {:ok, aura} <- shifted_aura(node, dx, dy),
         :ok <- check_node_land(terrain_at.(to), y),
         {:ok, cities} <- Cities.parse(raw),
         {:ok, units} <- Units.parse(raw),
         :ok <- check_node_destination(raw, cities, units, node, to) do
      here = {node.x, node.y, node.plane}
      moving = for u <- units, {u.x, u.y, plane_index(u.plane)} == here, do: u
      base = elem(Sites.nodes_range(), 0) + index * @node_record

      guardians =
        for e <- Encounters.all(raw),
            e.kind in @node_guardian_kinds,
            {e.x, e.y, e.plane} == here,
            do: e.index

      raw =
        raw
        |> put(base, <<x, y>>)
        |> put(base + 5, aura.x)
        |> put(base + 25, aura.y)
        |> then(fn r -> Enum.reduce(guardians, r, &put_encounter_xy(&2, &1, x, y)) end)
        |> relocate_units(Enum.map(moving, & &1.index), {x, y, node.plane})

      {:ok, raw,
       %{
         moved: :node,
         from: {node.x, node.y},
         to: to,
         guardians: length(guardians),
         units: length(moving),
         node_tile: Map.fetch!(@node_tiles, node.type)
       }}
    end
  end

  defp fetch_node(raw, index) do
    {base, _} = Sites.nodes_range()

    with true <- index in 0..29//1 and byte_size(raw) >= base + 30 * @node_record,
         <<x, y, plane, owner::signed, power, aura_x::binary-size(20), aura_y::binary-size(20),
           type, flags, _::binary>> <-
           binary_part(raw, base + index * @node_record, @node_record),
         true <-
           x < @width and y < @height and plane in [0, 1] and type in 0..2 and power in 1..20 do
      {:ok,
       %{
         index: index,
         x: x,
         y: y,
         plane: plane,
         owner: if(owner < 0, do: nil, else: owner),
         flags: flags,
         power: min(power, 20),
         aura_x: aura_x,
         aura_y: aura_y,
         type: type
       }}
    else
      _ -> {:error, :no_such_node}
    end
  end

  # The first `power` aura squares move by the same step; the rest of the 20 slots are left alone.
  defp shifted_aura(node, dx, dy) do
    pairs = Enum.zip(:binary.bin_to_list(node.aura_x), :binary.bin_to_list(node.aura_y))

    shifted =
      pairs
      |> Enum.with_index()
      |> Enum.map(fn {{ax, ay}, i} ->
        if i < node.power, do: {ax + dx, ay + dy}, else: {ax, ay}
      end)

    if Enum.all?(Enum.take(shifted, node.power), fn {ax, ay} ->
         ax in 0..(@width - 1)//1 and ay in 0..(@height - 1)//1
       end) do
      {:ok,
       %{
         x: for({ax, _} <- shifted, into: <<>>, do: <<ax>>),
         y: for({_, ay} <- shifted, into: <<>>, do: <<ay>>)
       }}
    else
      {:error, :aura_off_map}
    end
  end

  defp check_node_land(tile, y) do
    if Mirror.NodeTerrain.can_land?(tile, y), do: :ok, else: {:error, :bad_terrain}
  end

  defp check_node_destination(raw, cities, units, node, {x, y}) do
    plane = node.plane
    nodes = for i <- 0..29, i != node.index, {:ok, n} <- [fetch_node(raw, i)], do: n
    here = {node.x, node.y, plane}
    moving = for u <- units, {u.x, u.y, plane_index(u.plane)} == here, do: u
    there = for u <- units, {u.x, u.y, plane_index(u.plane)} == {x, y, plane}, do: u
    owners = moving |> Enum.map(& &1.owner) |> Enum.uniq()

    cond do
      Enum.any?(cities, &({&1.x, &1.y, plane_index(&1.plane)} == {x, y, plane})) ->
        {:error, :city_at_destination}

      tower_at(raw, x, y) != nil ->
        {:error, :tower_at_destination}

      Enum.any?(
        Encounters.all(raw),
        &({&1.x, &1.y, &1.plane} == {x, y, plane} and &1.kind not in @node_guardian_kinds)
      ) ->
        {:error, :encounter_at_destination}

      Enum.any?(nodes, &({&1.x, &1.y, &1.plane} == {x, y, plane})) ->
        {:error, :node_at_destination}

      moving != [] and Enum.any?(there, &(&1.owner not in owners)) ->
        {:error, :foreign_units_at_destination}

      length(there) + length(moving) > @max_stack ->
        {:error, :stack_full}

      true ->
        :ok
    end
  end

  @warped 0x01
  @spirit_meld 0x02

  @doc """
  Changes a magic node's melder and flags (STORY-020), as a keyword list:
  `edit_node(raw, index, owner: 1, warped: false, spirit_meld: true)`.

  * `owner`: `nil` (no one: byte `0xFF`) or a wizard record 0 to 4 (the byte at `+3`; it picks the
    colour of the node's aura squares).
  * `warped` and `spirit_meld`: flag bits of the byte at `+0x2E` (1 warped, 2 melded by a
    Guardian Spirit); the other bits are kept.

  The node's guardians are a separate record (see `edit_encounter/3`): in every save here all 42 owned
  nodes have theirs cleared and all 120 unowned ones still have them, but this does not touch them.

  Returns `{:ok, raw, %{changed: [...]}}` or `{:error, reason}` (`:no_such_node`, `:bad_owner`,
  `:bad_flag` or `{:unknown_field, field}`).
  """
  @spec edit_node(binary(), non_neg_integer(), keyword()) :: result()
  def edit_node(raw, index, changes) when is_list(changes) do
    with {:ok, node} <- fetch_node(raw, index),
         {:ok, edits} <- node_edits(changes) do
      base = elem(Sites.nodes_range(), 0) + index * @node_record

      {raw, _flags} =
        Enum.reduce(edits, {raw, node.flags}, fn
          {:owner, owner}, {acc, flags} ->
            {put(acc, base + 3, <<if(owner, do: owner, else: 0xFF)>>), flags}

          {:warped, on}, {acc, flags} ->
            flags = set_bit(flags, @warped, on)
            {put(acc, base + 0x2E, <<flags>>), flags}

          {:spirit_meld, on}, {acc, flags} ->
            flags = set_bit(flags, @spirit_meld, on)
            {put(acc, base + 0x2E, <<flags>>), flags}
        end)

      {:ok, raw, %{changed: Keyword.keys(edits)}}
    end
  end

  @wizard_offset 0x9E8
  @wizard_record 0x4C8
  @max_wizard_value 30_000
  @max_books 13
  @retort_count 18
  @spell_count 214
  @global_count 24
  # Time Stop is byte 6 of the globals: the flag alone only draws the icon and charges the upkeep (the real
  # spell keeps its state elsewhere, not found), so it can be neither added nor removed here.
  @time_stop 6

  @doc """
  Edits wizard `record` (0 is the player, 0 to 4 the wizards) with `changes`, a keyword list:

    * `:gold`, `:mana`, `:fame` (0 to #{@max_wizard_value}: the game's own cap on gold and mana, and the same
      limit for fame, *guess* until tried in the game)
    * `:name` (printable ASCII, 1 to 19 characters, written NUL-padded to 20 bytes)
    * `:books` (five numbers 0 to #{@max_books}, in the order Nature, Sorcery, Chaos, Life, Death; *guess* on the top)
    * `:retorts` (#{@retort_count} booleans, in the save's byte order)
    * `:spells` (a list of `{spell number 1..#{@spell_count}, state}`; state 0 unknown, 1 knowable, 2 known, 3 on the research list;
      only the listed spells are written)
    * `:relations` (a list of `{other wizard 0..4, relation, status}`; `relation` -100..100 or `nil` to leave it, `status` 0..4 or `nil`):
      the figure the Diplomacy screen shows (`+0x128 + 42`) and the treaty code (`+0x128 + 48`), written on **both**
      wizards' records, since the game keeps each pair in both. Status 0 none, 1 wizard pact are checked in the game; 2 alliance, 3 war
      and 4 final war are *guesses* (2026-10-12). The AI's interest values are left alone.
    * `:globals` (#{@global_count} booleans, the global enchantments in the save's byte order, `+0x482`; the flag is all
      the game needs, as set by hand it shows in the Magic screen and is charged upkeep. Time Stop (byte #{@time_stop}) cannot be
      changed: the list must keep it as it is)
    * `:researching` (the spell being researched, 0 for none, or a spell number 1..#{@spell_count}) and `:research_left` (research
      points left, 0 to 65535)

  Refused: a record with no name (`:no_such_wizard`), a bad value (`:bad_gold`, `:bad_mana`, `:bad_fame`,
  `:bad_name`, `:bad_books`, `:bad_retorts`, `:bad_globals`, `:bad_spells`, `:bad_researching`, `:bad_research_left`, `:bad_relations`) or an unknown field. The power base, casting skill and the
  research candidates are worked out again by the game, so they are not touched.
  """
  @spec edit_wizard(binary(), non_neg_integer(), keyword()) :: result()
  def edit_wizard(raw, record, changes) when is_list(changes) do
    at = @wizard_offset + record * @wizard_record

    with true <- record in 0..4//1 and byte_size(raw) >= @wizard_offset + 5 * @wizard_record,
         true <- :binary.at(raw, at + 1) != 0,
         {:ok, edits} <- wizard_edits(changes),
         :ok <- check_globals(raw, at, edits[:globals]),
         :ok <- check_relation_targets(raw, record, edits[:relations]) do
      raw =
        Enum.reduce(edits, raw, fn
          {:gold, v}, acc ->
            put(acc, at + 0x356, <<v::little-16>>)

          {:mana, v}, acc ->
            put(acc, at + 0x25C, <<v::little-16>>)

          {:fame, v}, acc ->
            put(acc, at + 0x24, <<v::little-16>>)

          {:name, v}, acc ->
            put(acc, at + 1, String.pad_trailing(v, 20, <<0>>))

          {:books, v}, acc ->
            put(acc, at + 0x5A, for(n <- v, into: <<>>, do: <<n::little-16>>))

          {:spells, v}, acc ->
            Enum.reduce(v, acc, fn {n, state}, acc -> put(acc, at + 0x264 + n - 1, <<state>>) end)

          {:relations, v}, acc ->
            Enum.reduce(v, acc, fn {other, relation, status}, acc ->
              acc
              |> put_relation(record, other, relation, status)
              |> put_relation(other, record, relation, status)
            end)

          {:researching, v}, acc ->
            put(acc, at + 0x262, <<v::little-16>>)

          {:research_left, v}, acc ->
            put(acc, at + 0x25A, <<v::little-16>>)

          {:retorts, v}, acc ->
            put(acc, at + 0x64, for(on <- v, into: <<>>, do: <<bool_byte(on)>>))

          {:globals, v}, acc ->
            Enum.reduce(Enum.with_index(v), acc, fn {on, i}, acc ->
              put(acc, at + 0x482 + i, <<bool_byte(on)>>)
            end)
        end)

      {:ok, raw, %{changed: Keyword.keys(edits)}}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_such_wizard}
    end
  end

  # Wizard `owner`'s view of `other`: the relation at `+42` and the status at `+48` of its diplomacy block.
  defp put_relation(raw, owner, other, relation, status) do
    block = @wizard_offset + owner * @wizard_record + 0x128

    raw
    |> then(&if(relation, do: put(&1, block + 42 + other, <<relation::signed>>), else: &1))
    |> then(&if(status, do: put(&1, block + 48 + other, <<status>>), else: &1))
  end

  defp valid_relation?({other, relation, status}),
    do:
      is_integer(other) and other in 0..4//1 and
        (is_nil(relation) or (is_integer(relation) and relation in -100..100//1)) and
        (is_nil(status) or (is_integer(status) and status in 0..4//1)) and
        not (is_nil(relation) and is_nil(status))

  defp valid_relation?(_), do: false

  # A pair needs two wizards: not the wizard itself, and the other one must have a name.
  defp check_relation_targets(_raw, _record, nil), do: :ok

  defp check_relation_targets(raw, record, relations) do
    ok? =
      Enum.all?(relations, fn {other, _, _} ->
        other != record and :binary.at(raw, @wizard_offset + other * @wizard_record + 1) != 0
      end)

    if ok?, do: :ok, else: {:error, :bad_relations}
  end

  # Time Stop's flag must come back as it is in the save.
  defp check_globals(_raw, _at, nil), do: :ok

  defp check_globals(raw, at, globals) do
    if bool_byte(Enum.at(globals, @time_stop)) == :binary.at(raw, at + 0x482 + @time_stop),
      do: :ok,
      else: {:error, :bad_globals}
  end

  defp bool_byte(true), do: 1
  defp bool_byte(false), do: 0

  defp wizard_edits(changes) do
    Enum.reduce_while(changes, {:ok, []}, fn {field, value}, {:ok, acc} ->
      case wizard_value(field, value) do
        :ok -> {:cont, {:ok, acc ++ [{field, value}]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp wizard_value(field, v)
       when field in [:gold, :mana, :fame] and is_integer(v) and v in 0..@max_wizard_value//1,
       do: :ok

  defp wizard_value(field, _) when field in [:gold, :mana, :fame], do: {:error, :"bad_#{field}"}

  defp wizard_value(:name, v) when is_binary(v) and byte_size(v) in 1..19//1 do
    if String.match?(v, ~r/\A[\x20-\x7E]+\z/) and String.trim(v) != "",
      do: :ok,
      else: {:error, :bad_name}
  end

  defp wizard_value(:name, _), do: {:error, :bad_name}

  defp wizard_value(:books, v) when is_list(v) and length(v) == 5 do
    if Enum.all?(v, &(is_integer(&1) and &1 in 0..@max_books//1)),
      do: :ok,
      else: {:error, :bad_books}
  end

  defp wizard_value(:books, _), do: {:error, :bad_books}

  defp wizard_value(:retorts, v) when is_list(v) and length(v) == @retort_count do
    if Enum.all?(v, &is_boolean/1), do: :ok, else: {:error, :bad_retorts}
  end

  defp wizard_value(:retorts, _), do: {:error, :bad_retorts}

  defp wizard_value(:globals, v) when is_list(v) and length(v) == @global_count do
    if Enum.all?(v, &is_boolean/1), do: :ok, else: {:error, :bad_globals}
  end

  defp wizard_value(:globals, _), do: {:error, :bad_globals}

  defp wizard_value(:spells, v) when is_list(v) and v != [] do
    if Enum.all?(v, &match?({n, s} when n in 1..@spell_count//1 and s in 0..3//1, &1)),
      do: :ok,
      else: {:error, :bad_spells}
  end

  defp wizard_value(:spells, _), do: {:error, :bad_spells}

  defp wizard_value(:relations, v) when is_list(v) and v != [] do
    if Enum.all?(v, &valid_relation?/1), do: :ok, else: {:error, :bad_relations}
  end

  defp wizard_value(:relations, _), do: {:error, :bad_relations}

  defp wizard_value(:researching, v) when is_integer(v) and v in 0..@spell_count//1, do: :ok
  defp wizard_value(:researching, _), do: {:error, :bad_researching}
  defp wizard_value(:research_left, v) when is_integer(v) and v in 0..65_535//1, do: :ok
  defp wizard_value(:research_left, _), do: {:error, :bad_research_left}
  defp wizard_value(other, _), do: {:error, {:unknown_field, other}}

  defp set_bit(flags, bit, true), do: Bitwise.bor(flags, bit)
  defp set_bit(flags, bit, false), do: Bitwise.band(flags, Bitwise.bnot(bit))

  defp node_edits(changes) do
    changes
    |> Enum.reduce_while({:ok, []}, fn
      {:owner, owner}, {:ok, acc} when is_nil(owner) or owner in 0..4//1 ->
        {:cont, {:ok, [{:owner, owner} | acc]}}

      {:owner, _}, _ ->
        {:halt, {:error, :bad_owner}}

      {flag, on}, {:ok, acc} when flag in [:warped, :spirit_meld] and is_boolean(on) ->
        {:cont, {:ok, [{flag, on} | acc]}}

      {flag, _}, _ when flag in [:warped, :spirit_meld] ->
        {:halt, {:error, :bad_flag}}

      {other, _}, _ ->
        {:halt, {:error, {:unknown_field, other}}}
    end)
    |> then(fn
      {:ok, edits} -> {:ok, Enum.reverse(edits)}
      error -> error
    end)
  end

  @doc """
  Magic node `index` as `%{index, x, y, plane, type, owner, power, warped, spirit_meld}` (plane 0
  or 1, type 0 Sorcery, 1 Nature, 2 Chaos, owner `nil` or 0..4), or `nil`.
  """
  @spec node_info(binary(), non_neg_integer()) :: map() | nil
  def node_info(raw, index) do
    case fetch_node(raw, index) do
      {:ok, node} ->
        node
        |> Map.take([:index, :x, :y, :plane, :type, :owner, :power])
        |> Map.merge(%{
          warped: Bitwise.band(node.flags, @warped) != 0,
          spirit_meld: Bitwise.band(node.flags, @spirit_meld) != 0
        })

      _ ->
        nil
    end
  end

  @doc """
  The magic node on `{x, y}` of `plane` (0 or 1), as `%{index, x, y, plane, type}`, or `nil`.
  `type` is 0 Sorcery, 1 Nature, 2 Chaos.
  """
  @spec node_at(binary(), integer(), integer(), 0 | 1) :: map() | nil
  def node_at(raw, x, y, plane) do
    Enum.find_value(0..29, fn i ->
      case fetch_node(raw, i) do
        {:ok, %{x: ^x, y: ^y, plane: ^plane} = node} -> node
        _ -> nil
      end
    end)
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
