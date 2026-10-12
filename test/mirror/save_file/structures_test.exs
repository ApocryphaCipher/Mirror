defmodule Mirror.SaveFile.StructuresTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.{Cities, Sites, Structures, Units}

  @cities 0x8AAC
  @units 0xB734
  @wizards 0x9E8
  @wizard 0x4C8
  @fortresses 0x65F8
  @towers 0x6610
  @encounters 0x6628

  defp put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  defp blank, do: :binary.copy(<<0>>, @units + 1009 * 32)

  defp city(raw, i, name, x, y, plane, owner) do
    count = max(i + 1, binary_part(raw, 0x9E0, 2) |> :binary.decode_unsigned(:little))

    raw
    |> put(0x9E0, <<count::little-16>>)
    |> put(
      @cities + i * 114,
      String.pad_trailing(name, 14, <<0>>) <> <<5, x, y, plane, owner, 1, 4>>
    )
  end

  defp unit(raw, i, x, y, plane, owner) do
    count = max(i + 1, binary_part(raw, 0x9E2, 2) |> :binary.decode_unsigned(:little))

    raw
    |> put(0x9E2, <<count::little-16>>)
    |> put(@units + i * 32, <<x, y, plane, owner, 2, 39>>)
  end

  defp wizard_circle(raw, owner, x, y, plane) do
    at = @wizards + owner * @wizard
    put(raw, at + 0x2E, <<x::little-16, y::little-16, plane::little-16>>)
  end

  defp circle(raw, owner) do
    at = @wizards + owner * @wizard
    <<x::little-16>> = binary_part(raw, at + 0x2E, 2)
    <<y::little-16>> = binary_part(raw, at + 0x30, 2)
    <<p::little-16>> = binary_part(raw, at + 0x32, 2)
    {x, y, p}
  end

  defp fortress(raw, i, x, y, plane), do: put(raw, @fortresses + i * 4, <<x, y, plane, 1>>)

  defp tower(raw, i, x, y), do: put(raw, @towers + i * 4, <<x, y, 255, 0>>)

  defp encounter(raw, i, x, y, plane, kind),
    do: put(raw, @encounters + i * 24, <<x, y, plane, 1, kind, 7, 1>>)

  defp city_at(raw, i) do
    {:ok, cities} = Cities.parse(raw)
    Enum.find(cities, &(&1.index == i))
  end

  describe "move_city/3" do
    test "moves the city and its garrison, and nothing else" do
      raw =
        blank()
        |> city(0, "Norport", 38, 21, 0, 0)
        |> city(1, "Other", 5, 5, 0, 1)
        |> unit(0, 38, 21, 0, 0)
        |> unit(1, 38, 21, 0, 0)
        |> unit(2, 38, 22, 0, 0)
        |> unit(3, 38, 21, 1, 0)

      assert {:ok, moved, report} = Structures.move_city(raw, 0, {10, 12, 0})

      assert %{x: 10, y: 12, plane: :arcanus, name: "Norport", owner: 0} = city_at(moved, 0)
      assert %{x: 5, y: 5} = city_at(moved, 1)
      assert report.garrison == 2

      {:ok, units} = Units.parse(moved)

      assert for(u <- units, do: {u.x, u.y, u.plane}) ==
               [{10, 12, :arcanus}, {10, 12, :arcanus}, {38, 22, :arcanus}, {38, 21, :myrror}]

      # only the city's x, y and the garrison's x, y changed
      diffs =
        for {a, b} <- Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(moved)),
            a != b,
            do: 1

      assert length(diffs) <= 2 + 2 * 2
    end

    test "to the other plane changes the plane of the city and its garrison" do
      raw = blank() |> city(0, "A", 3, 4, 0, 2) |> unit(0, 3, 4, 0, 2)

      assert {:ok, moved, _} = Structures.move_city(raw, 0, {7, 8, 1})
      assert %{x: 7, y: 8, plane: :myrror} = city_at(moved, 0)
      assert {:ok, [%{x: 7, y: 8, plane: :myrror}]} = Units.parse(moved)
    end

    test "a capital takes its summoning circle and fortress with it" do
      raw =
        blank()
        |> city(0, "Capital", 38, 21, 0, 0)
        |> wizard_circle(0, 38, 21, 0)
        |> fortress(0, 38, 21, 0)

      assert {:ok, moved, %{followed: [:summoning_circle, :fortress]}} =
               Structures.move_city(raw, 0, {20, 9, 1})

      assert circle(moved, 0) == {20, 9, 1}
      assert binary_part(moved, @fortresses, 4) == <<20, 9, 1, 1>>
    end

    test "leaves a circle and fortress that are somewhere else alone" do
      raw =
        blank()
        |> city(0, "Colony", 14, 14, 0, 0)
        |> wizard_circle(0, 38, 21, 0)
        |> fortress(0, 38, 21, 0)

      assert {:ok, moved, %{followed: []}} = Structures.move_city(raw, 0, {15, 15, 0})
      assert circle(moved, 0) == {38, 21, 0}
      assert binary_part(moved, @fortresses, 4) == <<38, 21, 0, 1>>
    end

    test "a neutral city (owner 5) has no wizard to follow" do
      raw = blank() |> city(0, "Free", 3, 3, 0, 5)
      assert {:ok, _moved, %{followed: []}} = Structures.move_city(raw, 0, {4, 4, 0})
    end

    test "refuses a destination off the map" do
      raw = blank() |> city(0, "A", 3, 3, 0, 0)
      assert {:error, :off_map} = Structures.move_city(raw, 0, {60, 3, 0})
      assert {:error, :off_map} = Structures.move_city(raw, 0, {3, 40, 0})
      assert {:error, :off_map} = Structures.move_city(raw, 0, {3, 3, 2})
    end

    test "refuses another city's tile, but only on the same plane" do
      raw = blank() |> city(0, "A", 3, 3, 0, 0) |> city(1, "B", 9, 9, 0, 1)
      assert {:error, :city_at_destination} = Structures.move_city(raw, 0, {9, 9, 0})
      assert {:ok, _, _} = Structures.move_city(raw, 0, {9, 9, 1})
    end

    test "refuses a tile holding another owner's units, accepts the owner's own" do
      raw = blank() |> city(0, "A", 3, 3, 0, 0) |> unit(0, 8, 8, 0, 1) |> unit(1, 6, 6, 0, 0)
      assert {:error, :foreign_units_at_destination} = Structures.move_city(raw, 0, {8, 8, 0})
      assert {:ok, _, _} = Structures.move_city(raw, 0, {6, 6, 0})
    end

    test "an unknown city is an error" do
      assert {:error, :no_such_city} = Structures.move_city(blank(), 3, {1, 1, 0})
    end

    test "garbage input is an error, not a crash" do
      assert {:error, _} = Structures.move_city(<<1, 2, 3>>, 0, {1, 1, 0})
    end
  end

  describe "edit_city/3" do
    test "renames the city and fills the whole field, leaving no tail of the old name" do
      raw = blank() |> city(0, "Hialanthxxxxx", 11, 15, 0, 5)

      assert {:ok, edited, %{changed: [:name]}} = Structures.edit_city(raw, 0, name: "Nar")
      assert %{name: "Nar", x: 11, y: 15, owner: 5, population: 4} = city_at(edited, 0)
      assert binary_part(edited, 0x8AAC, 14) == "Nar" <> :binary.copy(<<0>>, 11)
    end

    test "sets the population byte and nothing else" do
      raw = blank() |> city(0, "Deventor", 38, 21, 0, 0)

      assert {:ok, edited, %{changed: [:population]}} =
               Structures.edit_city(raw, 0, population: 9)

      assert %{population: 9, name: "Deventor", size: 1} = city_at(edited, 0)

      diff =
        for {a, b} <- Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(edited)),
            a != b,
            do: 1

      assert length(diff) == 1
    end

    test "name and population together; the name is trimmed" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)

      assert {:ok, edited, %{changed: [:name, :population]}} =
               Structures.edit_city(raw, 0, name: "  Zurich 2 ", population: 12)

      assert %{name: "Zurich 2", population: 12} = city_at(edited, 0)
    end

    test "refuses bad values and writes nothing" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)

      assert {:error, :bad_name} = Structures.edit_city(raw, 0, name: "")
      assert {:error, :bad_name} = Structures.edit_city(raw, 0, name: "    ")
      assert {:error, :bad_name} = Structures.edit_city(raw, 0, name: "Fourteen chars")
      assert {:error, :bad_name} = Structures.edit_city(raw, 0, name: "Tab\there")
      assert {:error, :bad_name} = Structures.edit_city(raw, 0, name: "Λ")
      # the game's font has no u-umlaut: "Zürich" showed as "Zrich" in the game
      assert {:error, :bad_name} = Structures.edit_city(raw, 0, name: "Zürich")
      assert {:error, :bad_population} = Structures.edit_city(raw, 0, population: 0)
      assert {:error, :bad_population} = Structures.edit_city(raw, 0, population: 26)
      assert {:error, :bad_population} = Structures.edit_city(raw, 0, population: "5")
      assert {:error, {:unknown_field, :fame}} = Structures.edit_city(raw, 0, fame: 1)
      # a good field next to a bad one: nothing is applied
      assert {:error, :bad_name} = Structures.edit_city(raw, 0, population: 5, name: "")
      assert {:error, :no_such_city} = Structures.edit_city(raw, 7, name: "X")
    end
  end

  describe "edit_city/3 buildings" do
    # building ids: 22 Shrine, 23 Temple, 24 Parthenon, 32 Builders Hall, 35 City Walls
    @shrine 22
    @temple 23

    defp with_buildings(raw, index, built) do
      bytes =
        for id <- 0..35, into: <<>> do
          case Map.get(built, id) do
            nil -> <<if(id == 0, do: 0, else: 0xFF)>>
            :built -> <<1>>
            :replaced -> <<0>>
          end
        end

      put(raw, 0x8AAC + index * 114 + 31, bytes)
    end

    defp building_state(raw, index, id), do: :binary.at(raw, 0x8AAC + index * 114 + 31 + id)

    test "adding a building marks the one it replaces as replaced, as the game does" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0) |> with_buildings(0, %{@shrine => :built})

      assert {:ok, edited, %{changed: [:buildings]}} =
               Structures.edit_city(raw, 0, buildings: [@shrine, @temple])

      assert building_state(edited, 0, @temple) == 1
      assert building_state(edited, 0, @shrine) == 0
      assert %{buildings: %{@temple => :built, @shrine => :replaced}} = city_at(edited, 0)
    end

    test "a building whose predecessor is absent is just built; needs are not enforced" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0) |> with_buildings(0, %{})

      assert {:ok, edited, _} = Structures.edit_city(raw, 0, buildings: [@temple])
      assert building_state(edited, 0, @temple) == 1
      assert building_state(edited, 0, @shrine) == 0xFF
      assert building_state(edited, 0, 32) == 0xFF
    end

    test "removing the replacing building brings the replaced one back" do
      raw =
        blank()
        |> city(0, "A", 1, 1, 0, 0)
        |> with_buildings(0, %{@shrine => :replaced, @temple => :built})

      assert {:ok, edited, _} = Structures.edit_city(raw, 0, buildings: [@shrine])
      assert building_state(edited, 0, @temple) == 0xFF
      assert building_state(edited, 0, @shrine) == 1
    end

    test "removing a replaced building leaves it gone; swapping in one call works" do
      raw =
        blank()
        |> city(0, "A", 1, 1, 0, 0)
        |> with_buildings(0, %{@shrine => :replaced, @temple => :built, 35 => :built})

      assert {:ok, edited, _} = Structures.edit_city(raw, 0, buildings: [@temple, 35])
      assert building_state(edited, 0, @shrine) == 0xFF
      assert building_state(edited, 0, @temple) == 1

      # drop the Temple and take a Parthenon in one edit: the Temple goes, the Parthenon replaces nothing
      assert {:ok, swapped, _} = Structures.edit_city(raw, 0, buildings: [@shrine, 24, 35])
      assert building_state(swapped, 0, @temple) == 0xFF
      assert building_state(swapped, 0, 24) == 1
      assert city_at(swapped, 0).walled
    end

    test "unticking everything leaves nothing behind, replaced buildings included" do
      raw =
        blank()
        |> city(0, "A", 1, 1, 0, 0)
        |> with_buildings(0, %{
          22 => :replaced,
          23 => :replaced,
          24 => :built,
          26 => :built,
          35 => :built
        })

      assert {:ok, edited, _} = Structures.edit_city(raw, 0, buildings: [])
      assert city_at(edited, 0).buildings == %{}

      # dropping the top of a chain brings back only what was asked for
      assert {:ok, partial, _} = Structures.edit_city(raw, 0, buildings: [23, 26, 35])
      assert building_state(partial, 0, 22) == 0xFF
      assert building_state(partial, 0, 23) == 1
      assert building_state(partial, 0, 24) == 0xFF
    end

    test "only the building bytes change, and byte 0 stays 0" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0) |> with_buildings(0, %{35 => :built})
      assert {:ok, edited, _} = Structures.edit_city(raw, 0, buildings: [35, 26])

      diff =
        for {{a, b}, i} <-
              Enum.with_index(Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(edited))),
            a != b,
            do: i

      assert diff == [0x8AAC + 31 + 26]
      assert building_state(edited, 0, 0) == 0
    end

    test "refuses ids outside 3..35" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)
      assert {:error, :bad_buildings} = Structures.edit_city(raw, 0, buildings: [2])
      assert {:error, :bad_buildings} = Structures.edit_city(raw, 0, buildings: [36])
      assert {:error, :bad_buildings} = Structures.edit_city(raw, 0, buildings: :all)
    end
  end

  describe "edit_city/3 race and owner" do
    test "race is the byte at +14 and nothing else changes" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)
      assert {:ok, edited, %{changed: [:race]}} = Structures.edit_city(raw, 0, race: 4)
      assert %{race: 4} = city_at(edited, 0)

      diff =
        for {{a, b}, i} <-
              Enum.with_index(Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(edited))),
            a != b,
            do: i

      assert diff == [0x8AAC + 14]

      assert {:error, :bad_race} = Structures.edit_city(raw, 0, race: 14)
      assert {:error, :bad_race} = Structures.edit_city(raw, 0, race: -1)
      assert {:error, :bad_race} = Structures.edit_city(raw, 0, race: "4")
    end

    test "a new owner takes the units standing in the city, and only those" do
      raw =
        blank()
        |> city(0, "A", 5, 5, 0, 2)
        |> unit(0, 5, 5, 0, 2)
        |> unit(1, 5, 5, 0, 2)
        |> unit(2, 6, 5, 0, 2)
        |> unit(3, 5, 5, 1, 2)

      assert {:ok, edited, %{changed: [:owner], units_handed_over: 2}} =
               Structures.edit_city(raw, 0, owner: 4)

      assert %{owner: 4} = city_at(edited, 0)
      {:ok, units} = Units.parse(edited)
      assert Enum.map(units, & &1.owner) == [4, 4, 2, 2]
    end

    test "a new owner clears the city's enchantments; an enchantment set in the same call stays" do
      raw = blank() |> city(0, "A", 5, 5, 0, 2)

      {:ok, raw, _} =
        Structures.edit_city(raw, 0, enchantments: %{famine: 1, natures_eye: 2, prosperity: 2})

      assert {:ok, edited, %{enchantments_cleared: 3}} = Structures.edit_city(raw, 0, owner: 4)
      assert city_at(edited, 0).enchantments == %{}

      assert {:ok, set_after, %{enchantments_cleared: 3}} =
               Structures.edit_city(raw, 0, enchantments: %{wall_of_fire: 4}, owner: 4)

      assert city_at(set_after, 0).enchantments == %{wall_of_fire: 4}
    end

    test "giving a city to its own owner changes nothing, so it keeps its enchantments" do
      raw = blank() |> city(0, "A", 5, 5, 0, 2) |> unit(0, 5, 5, 0, 2)
      {:ok, raw, _} = Structures.edit_city(raw, 0, enchantments: %{famine: 1})

      assert {:ok, same, %{changed: [], units_handed_over: 0, enchantments_cleared: 0}} =
               Structures.edit_city(raw, 0, owner: 2)

      assert same == raw
    end

    test "to neutral and back; a bad owner is refused" do
      raw = blank() |> city(0, "A", 5, 5, 0, 1) |> unit(0, 5, 5, 0, 1)
      assert {:ok, neutral, _} = Structures.edit_city(raw, 0, owner: 5)
      assert %{owner: 5} = city_at(neutral, 0)
      assert {:ok, [%{owner: 5}]} = Units.parse(neutral)
      assert {:error, :bad_owner} = Structures.edit_city(raw, 0, owner: 6)
      assert {:error, :bad_owner} = Structures.edit_city(raw, 0, owner: nil)
    end

    test "a wizard's capital cannot change hands: fortress or summoning circle" do
      capital = blank() |> city(0, "Cap", 9, 9, 0, 0) |> fortress(0, 9, 9, 0)
      assert {:error, :capital} = Structures.edit_city(capital, 0, owner: 2)

      circle =
        blank()
        |> city(0, "Cap", 9, 9, 0, 1)
        |> put(0x9E8 + 0x4C8 + 1, "Freya" <> <<0>>)
        |> wizard_circle(1, 9, 9, 0)

      assert {:error, :capital} = Structures.edit_city(circle, 0, owner: 2)

      # the same tile on the other plane is another city
      other_plane = blank() |> city(0, "Cap", 9, 9, 1, 0) |> fortress(0, 9, 9, 0)
      assert {:ok, _, _} = Structures.edit_city(other_plane, 0, owner: 2)

      # an inactive fortress record or an unnamed wizard's zeroed circle is not a capital
      inactive = blank() |> city(0, "Corner", 0, 0, 0, 0) |> put(0x65F8, <<0, 0, 0, 0>>)
      assert {:ok, _, _} = Structures.edit_city(inactive, 0, owner: 2)

      # no wizard has a name here, so every circle is a zeroed one
      unnamed = blank() |> city(0, "Corner", 0, 0, 0, 0)
      assert {:ok, _, _} = Structures.edit_city(unnamed, 0, owner: 2)

      # a named wizard whose circle really is at (0, 0) does count
      named = unnamed |> put(0x9E8 + 1, "Jafar" <> <<0>>)
      assert {:error, :capital} = Structures.edit_city(named, 0, owner: 2)

      # but a real one at (0, 0) still counts
      real = blank() |> city(0, "Corner", 0, 0, 0, 0) |> fortress(0, 0, 0, 0)
      assert {:error, :capital} = Structures.edit_city(real, 0, owner: 2)

      # and race and the rest still work on a capital
      assert {:ok, _, %{changed: [:race]}} = Structures.edit_city(capital, 0, race: 3)
    end
  end

  describe "edit_city/3 enchantments" do
    # slots: 14 Nature's Eye, 7 Famine
    test "sets a caster as index plus one and clears with nil, touching only that byte" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)
      eye = 0x8AAC + 67 + 14

      assert {:ok, edited, %{changed: [:enchantments]}} =
               Structures.edit_city(raw, 0, enchantments: %{natures_eye: 2})

      assert :binary.at(edited, eye) == 3
      assert %{enchantments: %{natures_eye: 2}} = city_at(edited, 0)

      diff =
        for {{a, b}, i} <-
              Enum.with_index(Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(edited))),
            a != b,
            do: i

      assert diff == [eye]

      assert {:ok, cleared, _} =
               Structures.edit_city(edited, 0, enchantments: %{natures_eye: nil})

      assert :binary.at(cleared, eye) == 0
      assert city_at(cleared, 0).enchantments == %{}
    end

    test "several at once, and a mix with a population change" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)

      assert {:ok, edited, %{changed: [:population, :enchantments]}} =
               Structures.edit_city(raw, 0,
                 population: 7,
                 enchantments: %{famine: 1, nature_ward: 0, wall_of_fire: 4}
               )

      assert %{population: 7, enchantments: %{famine: 1, nature_ward: 0, wall_of_fire: 4}} =
               city_at(edited, 0)
    end

    test "the neutral record (5) is a caster like any other" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)
      assert {:ok, edited, _} = Structures.edit_city(raw, 0, enchantments: %{famine: 5})
      assert :binary.at(edited, 0x8AAC + 67 + 7) == 6
      assert %{enchantments: %{famine: 5}} = city_at(edited, 0)
    end

    test "refuses an unknown enchantment or a caster outside 0..5" do
      raw = blank() |> city(0, "A", 1, 1, 0, 0)

      assert {:error, :bad_enchantments} =
               Structures.edit_city(raw, 0, enchantments: %{fireball: 1})

      assert {:error, :bad_enchantments} =
               Structures.edit_city(raw, 0, enchantments: %{famine: 6})

      assert {:error, :bad_enchantments} =
               Structures.edit_city(raw, 0, enchantments: %{famine: -1})

      assert {:error, :bad_enchantments} = Structures.edit_city(raw, 0, enchantments: [famine: 1])
    end
  end

  describe "move_units/3" do
    @landmass 0x4D98

    defp unit_type(raw, i, type), do: put(raw, 0xB734 + i * 32 + 5, <<type>>)

    defp unit_orders(raw, i, dx, dy, status),
      do: put(raw, 0xB734 + i * 32 + 9, <<dx, dy, status>>)

    defp land(raw, plane, x, y), do: put(raw, @landmass + plane * 2400 + y * 60 + x, <<1>>)
    defp unit_at(raw, i), do: binary_part(raw, 0xB734 + i * 32, 12)

    test "moves the chosen units only; an idle unit changes in x, y and plane and nothing else" do
      raw =
        blank()
        |> unit(0, 5, 5, 0, 2)
        |> unit(1, 5, 5, 0, 2)
        |> unit(2, 5, 5, 0, 2)
        |> land(0, 7, 6)

      assert {:ok, moved, %{count: 2, from: [{5, 5, 0}], to: {7, 6, 1}}} =
               Structures.move_units(raw, [0, 2], {7, 6, 1})

      assert {:ok, [a, b, c]} = Units.parse(moved)
      assert {a.x, a.y, a.plane} == {7, 6, :myrror}
      assert {b.x, b.y, b.plane} == {5, 5, :arcanus}
      assert {c.x, c.y, c.plane} == {7, 6, :myrror}

      diff =
        for {{x, y}, i} <-
              Enum.with_index(Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(moved))),
            x != y,
            do: i

      assert length(diff) == 6
    end

    test "a go-to order is cleared; sentry and idle-after-a-turn are kept" do
      raw =
        blank()
        |> unit(0, 5, 5, 0, 2)
        |> unit(1, 5, 5, 0, 2)
        |> unit(2, 5, 5, 0, 2)
        |> unit(3, 5, 5, 0, 2)
        |> unit_orders(0, 20, 20, 3)
        |> unit_orders(1, 0, 0, 1)
        |> unit_orders(2, 0, 0, 4)
        |> unit_orders(3, 9, 9, 0)

      assert {:ok, moved, _} = Structures.move_units(raw, [0, 1, 2, 3], {6, 6, 0})
      assert binary_part(unit_at(moved, 0), 9, 3) == <<0, 0, 0>>
      assert binary_part(unit_at(moved, 1), 9, 3) == <<0, 0, 1>>
      assert binary_part(unit_at(moved, 2), 9, 3) == <<0, 0, 4>>
      assert binary_part(unit_at(moved, 3), 9, 3) == <<0, 0, 0>>
    end

    test "refuses what it cannot do, and writes nothing" do
      raw =
        blank()
        |> city(0, "Mine", 9, 9, 0, 2)
        |> city(1, "Theirs", 12, 12, 0, 3)
        |> unit(0, 5, 5, 0, 2)
        |> unit(1, 6, 6, 0, 3)
        |> unit(2, 20, 20, 0, 3)

      assert {:error, :off_map} = Structures.move_units(raw, [0], {60, 5, 0})
      assert {:error, :no_units} = Structures.move_units(raw, [], {7, 7, 0})
      assert {:error, :no_such_unit} = Structures.move_units(raw, [9], {7, 7, 0})
      assert {:error, :no_such_unit} = Structures.move_units(raw, [0, 0], {7, 7, 0})
      assert {:error, :mixed_owners} = Structures.move_units(raw, [0, 1], {7, 7, 0})
      assert {:error, :foreign_city_at_destination} = Structures.move_units(raw, [0], {12, 12, 0})
      assert {:error, :foreign_units_at_destination} = Structures.move_units(raw, [0], {6, 6, 0})
      assert {:ok, _, _} = Structures.move_units(raw, [0], {9, 9, 0})
    end

    test "a stack holds at most nine" do
      raw =
        Enum.reduce(0..8, blank(), &unit(&2, &1, 5, 5, 0, 2))
        |> unit(9, 8, 8, 0, 2)
        |> unit(10, 8, 8, 0, 2)

      assert {:error, :stack_full} = Structures.move_units(raw, [9], {5, 5, 0})
      assert {:ok, _, _} = Structures.move_units(raw, [0, 1], {8, 8, 0})
      # units already on the tile do not count twice when they are the ones moving
      assert {:ok, _, _} = Structures.move_units(raw, Enum.to_list(0..8), {5, 5, 0})
    end

    test "warns about a land unit on water, a boat on land, and not about a boat's passengers or flyers" do
      base = blank() |> unit(0, 5, 5, 0, 2) |> land(0, 7, 7)

      # the blank save has no land anywhere: (8, 8) is water
      assert {:ok, _, %{warnings: [cannot_be_on_water: [39]]}} =
               Structures.move_units(base, [0], {8, 8, 0})

      assert {:ok, _, %{warnings: []}} = Structures.move_units(base, [0], {7, 7, 0})

      flyer = base |> unit_type(0, 136)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(flyer, [0], {8, 8, 0})

      boat = base |> unit_type(0, 35)

      assert {:ok, _, %{warnings: [boat_on_land: [35]]}} =
               Structures.move_units(boat, [0], {7, 7, 0})

      assert {:ok, _, %{warnings: []}} = Structures.move_units(boat, [0], {8, 8, 0})

      # demon wings (mutation bit 8, record +23) fly, whatever the type
      winged = put(base, 0xB734 + 23, <<8>>)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(winged, [0], {8, 8, 0})
      wingless = put(base, 0xB734 + 23, <<32>>)

      assert {:ok, _, %{warnings: [cannot_be_on_water: [39]]}} =
               Structures.move_units(wingless, [0], {8, 8, 0})

      # a land unit joining a boat on the water is aboard it
      aboard = base |> unit(1, 8, 8, 0, 2) |> unit_type(1, 36)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(aboard, [0], {8, 8, 0})

      # a boat in a city is fine
      port = boat |> city(0, "Port", 7, 7, 0, 2)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(port, [0], {7, 7, 0})

      # the polar rows have no landmass id and are land
      assert {:ok, _, %{warnings: []}} = Structures.move_units(base, [0], {8, 0, 0})
    end
  end

  describe "move_node/4" do
    @nodes 0x6058

    defp magic_node(raw, i, x, y, plane, owner, power, type) do
      xs = for k <- 0..19, into: <<>>, do: <<if(k < power, do: x + rem(k, 3) - 1, else: 0)>>
      ys = for k <- 0..19, into: <<>>, do: <<if(k < power, do: y + div(k, 3) - 1, else: 0)>>
      put(raw, @nodes + i * 48, <<x, y, plane, owner, power>> <> xs <> ys <> <<type, 0, 0>>)
    end

    # Grass (tile 1) everywhere, except the node's own tile, which is the node (168 + type).
    defp terrain(overrides \\ %{}) do
      fn pos -> Map.get(overrides, pos, 1) end
    end

    defp node_at(raw, i), do: binary_part(raw, @nodes + i * 48, 48)

    test "moves the record, the aura squares together, the guardians and the units on it" do
      raw =
        blank()
        |> magic_node(3, 20, 10, 0, 0, 5, 0)
        |> encounter(7, 20, 10, 0, 3)
        |> encounter(8, 33, 7, 0, 8)
        |> unit(0, 20, 10, 0, 0)
        |> unit(1, 21, 10, 0, 0)

      assert {:ok, moved, report} =
               Structures.move_node(raw, 3, {23, 12}, terrain(%{{20, 10} => 168}))

      <<x, y, plane, owner, power, ax::binary-size(20), ay::binary-size(20), type, _::binary>> =
        node_at(moved, 3)

      assert {x, y, plane, owner, power, type} == {23, 12, 0, 0, 5, 0}
      # the first five aura squares moved by (+3, +2); the unused slots stayed zero
      assert binary_part(ax, 0, 5) == <<22, 23, 24, 22, 23>>
      assert binary_part(ay, 0, 5) == <<11, 11, 11, 12, 12>>
      assert binary_part(ax, 5, 15) == :binary.copy(<<0>>, 15)

      assert %{moved: :node, from: {20, 10}, to: {23, 12}, guardians: 1, units: 1} = report
      assert Mirror.SaveFile.Encounters.get(moved, 7) |> then(&{&1.x, &1.y}) == {23, 12}
      assert Mirror.SaveFile.Encounters.get(moved, 8) |> then(&{&1.x, &1.y}) == {33, 7}
      assert {:ok, [moved_unit, other]} = Units.parse(moved)
      assert {moved_unit.x, moved_unit.y} == {23, 12}
      assert {other.x, other.y} == {21, 10}

      # the caller turns the new spot into this tile (and the old one back into land)
      assert report.node_tile == 168
    end

    test "the new tile is the node of its type: 168 Sorcery, 169 Nature, 170 Chaos" do
      for {type, tile} <- [{0, 168}, {1, 169}, {2, 170}] do
        raw = blank() |> magic_node(0, 20, 10, 0, 5, 3, type)

        assert {:ok, _, %{node_tile: ^tile}} = Structures.move_node(raw, 0, {22, 10}, terrain())
      end
    end

    test "a node can go on any land, not on water, a river, a lake, a volcano, a node or the polar rows" do
      raw = blank() |> magic_node(0, 20, 10, 0, 5, 3, 1)

      for {name, tile} <- [
            grass: 1,
            forest: 163,
            swamp: 166,
            desert: 165,
            tundra: 167,
            hill: 171,
            mountain: 164
          ] do
        assert {:ok, _, _} = Structures.move_node(raw, 0, {22, 10}, terrain(%{{22, 10} => tile})),
               "#{name} should do"
      end

      for {name, tile} <- [ocean: 0, coast: 2, river: 185, lake: 18, volcano: 179, node: 169] do
        assert {:error, :bad_terrain} =
                 Structures.move_node(raw, 0, {22, 10}, terrain(%{{22, 10} => tile})),
               "#{name} should be refused"
      end

      # the polar rows are tundra, but a node does not go there
      polar = blank() |> magic_node(0, 20, 5, 0, 3, 3, 1)

      assert {:error, :bad_terrain} =
               Structures.move_node(polar, 0, {22, 1}, terrain(%{{22, 1} => 167}))
    end

    test "refuses what it cannot do, and writes nothing" do
      raw =
        blank()
        |> city(0, "Mine", 9, 9, 0, 2)
        |> city(1, "Theirs", 12, 12, 0, 3)
        |> unit(0, 5, 5, 0, 2)
        |> unit(1, 6, 6, 0, 3)
        |> unit(2, 20, 20, 0, 3)

      assert {:error, :off_map} = Structures.move_units(raw, [0], {60, 5, 0})
      assert {:error, :no_units} = Structures.move_units(raw, [], {7, 7, 0})
      assert {:error, :no_such_unit} = Structures.move_units(raw, [9], {7, 7, 0})
      assert {:error, :no_such_unit} = Structures.move_units(raw, [0, 0], {7, 7, 0})
      assert {:error, :mixed_owners} = Structures.move_units(raw, [0, 1], {7, 7, 0})
      assert {:error, :foreign_city_at_destination} = Structures.move_units(raw, [0], {12, 12, 0})
      assert {:error, :foreign_units_at_destination} = Structures.move_units(raw, [0], {6, 6, 0})
      assert {:ok, _, _} = Structures.move_units(raw, [0], {9, 9, 0})
    end

    test "a stack holds at most nine" do
      raw =
        Enum.reduce(0..8, blank(), &unit(&2, &1, 5, 5, 0, 2))
        |> unit(9, 8, 8, 0, 2)
        |> unit(10, 8, 8, 0, 2)

      assert {:error, :stack_full} = Structures.move_units(raw, [9], {5, 5, 0})
      assert {:ok, _, _} = Structures.move_units(raw, [0, 1], {8, 8, 0})
      # units already on the tile do not count twice when they are the ones moving
      assert {:ok, _, _} = Structures.move_units(raw, Enum.to_list(0..8), {5, 5, 0})
    end

    test "warns about a land unit on water, a boat on land, and not about a boat's passengers or flyers" do
      base = blank() |> unit(0, 5, 5, 0, 2) |> land(0, 7, 7)

      # the blank save has no land anywhere: (8, 8) is water
      assert {:ok, _, %{warnings: [cannot_be_on_water: [39]]}} =
               Structures.move_units(base, [0], {8, 8, 0})

      assert {:ok, _, %{warnings: []}} = Structures.move_units(base, [0], {7, 7, 0})

      flyer = base |> unit_type(0, 136)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(flyer, [0], {8, 8, 0})

      boat = base |> unit_type(0, 35)

      assert {:ok, _, %{warnings: [boat_on_land: [35]]}} =
               Structures.move_units(boat, [0], {7, 7, 0})

      assert {:ok, _, %{warnings: []}} = Structures.move_units(boat, [0], {8, 8, 0})

      # demon wings (mutation bit 8, record +23) fly, whatever the type
      winged = put(base, 0xB734 + 23, <<8>>)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(winged, [0], {8, 8, 0})
      wingless = put(base, 0xB734 + 23, <<32>>)

      assert {:ok, _, %{warnings: [cannot_be_on_water: [39]]}} =
               Structures.move_units(wingless, [0], {8, 8, 0})

      # a land unit joining a boat on the water is aboard it
      aboard = base |> unit(1, 8, 8, 0, 2) |> unit_type(1, 36)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(aboard, [0], {8, 8, 0})

      # a boat in a city is fine
      port = boat |> city(0, "Port", 7, 7, 0, 2)
      assert {:ok, _, %{warnings: []}} = Structures.move_units(port, [0], {7, 7, 0})

      # the polar rows have no landmass id and are land
      assert {:ok, _, %{warnings: []}} = Structures.move_units(base, [0], {8, 0, 0})
    end

    test "a stack of nine on the destination leaves no room" do
      raw =
        Enum.reduce(
          0..8,
          blank() |> magic_node(0, 20, 10, 0, 0, 5, 0),
          &unit(&2, &1, 30, 10, 0, 0)
        )
        |> unit(9, 20, 10, 0, 0)

      assert {:error, :stack_full} = Structures.move_node(raw, 0, {30, 10}, terrain())
      assert {:ok, _, _} = Structures.move_node(raw, 0, {31, 10}, terrain())
    end

    test "a truncated save or a zeroed node slot is no node, not a crash" do
      assert {:error, :no_such_node} = Structures.move_node(<<1, 2, 3>>, 0, {22, 10}, terrain())
      assert {:error, :no_such_node} = Structures.move_node(blank(), 0, {22, 10}, terrain())
      assert Structures.node_at(<<1, 2, 3>>, 0, 0, 0) == nil
      assert Structures.node_at(blank(), 0, 0, 0) == nil

      raw = blank() |> magic_node(4, 20, 10, 0, 5, 3, 1)
      assert %{index: 4, type: 1} = Structures.node_at(raw, 20, 10, 0)
      assert Structures.node_at(raw, 20, 10, 1) == nil
      assert Structures.node_at(raw, 21, 10, 0) == nil
    end

    test "a node with no units may move onto a tile where another player's units stand" do
      # nothing of its own to bring, so there is nobody to put among them
      raw = blank() |> magic_node(0, 20, 10, 0, 5, 3, 1) |> unit(0, 22, 10, 0, 3)
      assert {:ok, _, %{units: 0}} = Structures.move_node(raw, 0, {22, 10}, terrain())
    end
  end

  describe "move_tower/3" do
    test "moves the tower, both of its sides, and units on its tile on either plane" do
      raw =
        blank()
        |> tower(0, 33, 7)
        |> tower(1, 12, 12)
        |> encounter(0, 33, 7, 0, 0)
        |> encounter(6, 33, 7, 1, 0)
        |> encounter(1, 12, 12, 0, 0)
        |> unit(0, 33, 7, 0, 0)
        |> unit(1, 33, 7, 1, 0)

      assert {:ok, moved, report} = Structures.move_tower(raw, 0, {20, 20})
      assert report.encounter_sides == 2
      assert report.garrison == 2

      assert {:ok, %{towers: towers, encounters: encounters}} = Sites.parse(moved)

      assert towers |> Enum.map(&{&1.x, &1.y}) |> Enum.reject(&(&1 == {0, 0})) |> Enum.sort() ==
               [{12, 12}, {20, 20}]

      assert binary_part(moved, @towers, 8) == <<20, 20, 255, 0, 12, 12, 255, 0>>

      assert encounters
             |> Enum.filter(&(&1.kind == 0 and {&1.x, &1.y} != {0, 0}))
             |> Enum.map(&{&1.x, &1.y, &1.plane})
             |> Enum.sort() ==
               Enum.sort([{20, 20, :arcanus}, {20, 20, :myrror}, {12, 12, :arcanus}])

      assert {:ok, [%{x: 20, y: 20, plane: :arcanus}, %{x: 20, y: 20, plane: :myrror}]} =
               Units.parse(moved)
    end

    test "warns when the new tile is not land on both planes" do
      # landmass ids at 0x4D98: land on Arcanus (7), ocean on Myrror (0)
      raw = blank() |> tower(0, 33, 7) |> put(0x4D98 + 7 * 60 + 20, <<7>>)

      assert {:ok, _, %{warnings: [water: :myrror]}} = Structures.move_tower(raw, 0, {20, 7})

      assert {:ok, _, %{warnings: [water: :arcanus, water: :myrror]}} =
               Structures.move_tower(raw, 0, {21, 7})
    end

    test "refuses another tower's tile and a tile off the map" do
      raw = blank() |> tower(0, 33, 7) |> tower(1, 12, 12)
      assert {:error, :tower_at_destination} = Structures.move_tower(raw, 0, {12, 12})
      assert {:error, :off_map} = Structures.move_tower(raw, 0, {70, 1})
      assert {:error, :no_such_tower} = Structures.move_tower(raw, 4, {1, 1})
    end
  end

  describe "edit_node/3 and node_info/2" do
    test "node_info reads owner (none is nil) and the two flags" do
      raw =
        blank()
        |> magic_node(0, 20, 10, 0, 255, 5, 1)
        |> magic_node(1, 30, 12, 1, 2, 5, 2)
        |> put(0x6058 + 48 + 0x2E, <<3>>)

      assert %{owner: nil, warped: false, spirit_meld: false, type: 1, power: 5} =
               Structures.node_info(raw, 0)

      assert %{owner: 2, warped: true, spirit_meld: true, plane: 1, type: 2} =
               Structures.node_info(raw, 1)

      assert Structures.node_info(raw, 30) == nil
    end

    test "owner and flags change only their own bytes" do
      raw = blank() |> magic_node(4, 20, 10, 0, 255, 5, 0)

      assert {:ok, edited, %{changed: [:owner, :warped]}} =
               Structures.edit_node(raw, 4, owner: 3, warped: true)

      base = 0x6058 + 4 * 48

      diff =
        for {{a, b}, i} <-
              Enum.with_index(Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(edited))),
            a != b,
            do: i

      assert diff == [base + 3, base + 0x2E]
      assert %{owner: 3, warped: true, spirit_meld: false} = Structures.node_info(edited, 4)
    end

    test "a flag is cleared without touching the other, and none is written 0xFF" do
      raw = blank() |> magic_node(0, 20, 10, 0, 1, 5, 0) |> put(0x6058 + 0x2E, <<3>>)

      assert {:ok, edited, _} = Structures.edit_node(raw, 0, spirit_meld: false, owner: nil)

      assert %{owner: nil, warped: true, spirit_meld: false} = Structures.node_info(edited, 0)
      assert binary_part(edited, 0x6058 + 3, 1) == <<0xFF>>
    end

    test "refuses a bad owner, a bad flag, an unknown field and a missing node" do
      raw = blank() |> magic_node(0, 20, 10, 0, 255, 5, 0)

      assert {:error, :bad_owner} = Structures.edit_node(raw, 0, owner: 5)
      assert {:error, :bad_flag} = Structures.edit_node(raw, 0, warped: 1)
      assert {:error, {:unknown_field, :power}} = Structures.edit_node(raw, 0, power: 3)
      assert {:error, _} = Structures.edit_node(raw, 29, owner: 1)
    end
  end

  describe "edit_encounter/3" do
    defp enc(raw, i), do: Mirror.SaveFile.Encounters.get(raw, i)

    test "intact, gold and mana are written, and only those bytes change" do
      raw = blank() |> encounter(20, 10, 11, 0, 8)

      assert {:ok, edited, %{changed: [:intact, :gold, :mana], records: [20]}} =
               Structures.edit_encounter(raw, 20, intact: false, gold: 620, mana: 330)

      assert %{intact: false, gold: 620, mana: 330, kind: 8, x: 10, y: 11} = enc(edited, 20)

      diff =
        for {{a, b}, i} <-
              Enum.with_index(Enum.zip(:binary.bin_to_list(raw), :binary.bin_to_list(edited))),
            a != b,
            do: i

      assert diff == [
               @encounters + 20 * 24 + 3,
               @encounters + 20 * 24 + 10,
               @encounters + 20 * 24 + 11,
               @encounters + 20 * 24 + 12,
               @encounters + 20 * 24 + 13
             ]
    end

    test "guards: set a slot with equal nibbles, empty another" do
      # encounter/6 gives guard 1 = type 7, count byte 1 and nothing in slot 2
      raw = blank() |> encounter(20, 10, 11, 0, 8)

      assert {:ok, edited, %{changed: [:guards]}} =
               Structures.edit_encounter(raw, 20, guards: %{1 => {189, 3}, 2 => {180, 8}})

      assert binary_part(edited, @encounters + 20 * 24 + 5, 4) == <<189, 0x33, 180, 0x88>>

      assert [%{type: 189, left: 3, start: 3}, %{type: 180, left: 8, start: 8}] =
               enc(edited, 20).guards

      assert {:ok, emptied, _} = Structures.edit_encounter(edited, 20, guards: %{1 => nil})
      assert binary_part(emptied, @encounters + 20 * 24 + 5, 4) == <<0, 0, 180, 0x88>>
      assert [%{slot: 2}] = enc(emptied, 20).guards
    end

    test "a tower is edited on both sides; a lair on its own record only" do
      raw =
        blank()
        |> encounter(0, 33, 7, 0, 0)
        |> encounter(6, 33, 7, 1, 0)
        |> encounter(1, 12, 12, 0, 0)
        |> encounter(20, 33, 7, 0, 8)

      assert {:ok, edited, %{records: [0, 6]}} =
               Structures.edit_encounter(raw, 6, gold: 77, intact: false)

      assert %{gold: 77, intact: false} = enc(edited, 0)
      assert %{gold: 77, intact: false} = enc(edited, 6)
      assert %{gold: 0, intact: true} = enc(edited, 1)
      # a lair on the same tile as the tower is not one of its sides
      assert %{gold: 0, intact: true} = enc(edited, 20)

      assert {:ok, lair, %{records: [20]}} = Structures.edit_encounter(raw, 20, gold: 5)
      assert %{gold: 5} = enc(lair, 20)
      assert %{gold: 0} = enc(lair, 0)
    end

    test "refuses bad values and writes nothing" do
      raw = blank() |> encounter(20, 10, 11, 0, 8)

      assert {:error, :no_such_encounter} = Structures.edit_encounter(raw, 21, gold: 1)
      assert {:error, :bad_intact} = Structures.edit_encounter(raw, 20, intact: 1)
      assert {:error, :bad_gold} = Structures.edit_encounter(raw, 20, gold: -1)
      assert {:error, :bad_gold} = Structures.edit_encounter(raw, 20, gold: 30_001)
      assert {:error, :bad_gold} = Structures.edit_encounter(raw, 20, gold: "5")
      assert {:error, :bad_mana} = Structures.edit_encounter(raw, 20, mana: 40_000)
      assert {:error, :bad_guards} = Structures.edit_encounter(raw, 20, guards: %{})
      assert {:error, :bad_guards} = Structures.edit_encounter(raw, 20, guards: %{3 => {7, 1}})
      assert {:error, :bad_guards} = Structures.edit_encounter(raw, 20, guards: %{1 => {198, 1}})
      assert {:error, :bad_guards} = Structures.edit_encounter(raw, 20, guards: %{1 => {7, 0}})
      assert {:error, :bad_guards} = Structures.edit_encounter(raw, 20, guards: %{1 => {7, 9}})
      assert {:error, :bad_guards} = Structures.edit_encounter(raw, 20, guards: [{1, {7, 1}}])
      assert {:error, {:unknown_field, :spell}} = Structures.edit_encounter(raw, 20, spell: 1)
      # a good field next to a bad one: nothing applied
      assert {:error, :bad_mana} = Structures.edit_encounter(raw, 20, gold: 9, mana: -5)
    end
  end

  describe "move_encounter/3" do
    test "moves a lair to the other plane and leaves other encounters alone" do
      raw = blank() |> encounter(20, 10, 11, 0, 8) |> encounter(21, 30, 30, 1, 4)

      assert {:ok, moved, %{from: {10, 11, 0}, to: {15, 16, 1}}} =
               Structures.move_encounter(raw, 20, {15, 16, 1})

      assert binary_part(moved, @encounters + 20 * 24, 3) == <<15, 16, 1>>
      assert binary_part(moved, @encounters + 21 * 24, 3) == <<30, 30, 1>>
    end

    test "towers and node guardians move with their tower or node" do
      raw = blank() |> encounter(0, 33, 7, 0, 0) |> encounter(1, 8, 8, 0, 2)
      assert {:error, :move_the_tower} = Structures.move_encounter(raw, 0, {1, 1, 0})
      assert {:error, :move_the_node} = Structures.move_encounter(raw, 1, {1, 1, 0})
    end

    test "refuses a tile that holds another encounter on that plane" do
      raw = blank() |> encounter(20, 10, 11, 0, 8) |> encounter(21, 30, 30, 0, 4)
      assert {:error, :encounter_at_destination} = Structures.move_encounter(raw, 20, {30, 30, 0})
      assert {:ok, _, _} = Structures.move_encounter(raw, 20, {30, 30, 1})
    end

    test "an empty slot is not an encounter" do
      assert {:error, :no_such_encounter} = Structures.move_encounter(blank(), 99, {1, 1, 0})
    end
  end
end
