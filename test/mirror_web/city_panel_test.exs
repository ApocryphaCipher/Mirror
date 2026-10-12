defmodule MirrorWeb.CityPanelTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.CityPanel

  # The parts of `details/2` that `changes/2` reads: a Hamlet city with a Temple built.
  @details %{
    name: "Hialanth",
    population: 6,
    building_states: %{23 => :built, 22 => :replaced},
    enchantment_casters: %{}
  }

  defp form(extra), do: Map.merge(%{"name" => "Hialanth", "population" => "6"}, extra)

  test "nothing different is no change" do
    assert {:ok, []} = CityPanel.changes(form(%{}), @details)

    assert {:ok, []} =
             CityPanel.changes(
               form(%{"buildings_present" => "1", "buildings" => ["22", "23"]}),
               @details
             )
  end

  test "a changed name, population and building list are each a change" do
    params =
      form(%{
        "name" => " Nar ",
        "population" => "9",
        "buildings_present" => "1",
        "buildings" => ["23", "26"]
      })

    assert {:ok, [name: "Nar", population: 9, buildings: [23, 26]]} =
             CityPanel.changes(params, @details)
  end

  test "unticking everything is a real change, not a missing checklist" do
    assert {:ok, [buildings: []]} =
             CityPanel.changes(form(%{"buildings_present" => "1"}), @details)
  end

  test "a malformed building list is refused, not read as fewer buildings" do
    for bad <- [["23", "not-a-building"], ["", "23"], [23], %{"0" => "23"}, "23", [["23"]]] do
      assert {:error, :bad_buildings} =
               CityPanel.changes(
                 form(%{"buildings_present" => "1", "buildings" => bad}),
                 @details
               ),
             "expected #{inspect(bad)} to be refused"
    end
  end

  test "a number outside the building ids passes through for the editor to refuse" do
    assert {:ok, [buildings: [2, 23]]} =
             CityPanel.changes(
               form(%{"buildings_present" => "1", "buildings" => ["2", "23"]}),
               @details
             )
  end

  test "a bad population is refused" do
    assert {:error, :bad_population} = CityPanel.changes(form(%{"population" => "six"}), @details)
  end

  describe "enchantments" do
    @details_ench %{
      name: "Hialanth",
      population: 6,
      building_states: %{},
      enchantment_casters: %{famine: 5, natures_eye: 0},
      owners: [{0, "Jafar"}, {1, "Freya"}, {5, "Neutral"}]
    }

    defp ench_form(chosen), do: form(%{"enchantments_present" => "1", "enchantments" => chosen})

    test "the form as posted, unchanged, is no change (a neutral caster stays selected)" do
      assert {:ok, []} =
               CityPanel.changes(
                 ench_form(%{"famine" => "5", "natures_eye" => "0", "prosperity" => ""}),
                 @details_ench
               )
    end

    test "a different caster, a new one and 'none' are each a change" do
      assert {:ok, [enchantments: %{famine: nil, natures_eye: 1, prosperity: 0}]} =
               CityPanel.changes(
                 ench_form(%{"famine" => "", "natures_eye" => "1", "prosperity" => "0"}),
                 @details_ench
               )
    end

    test "an unreadable caster, an unknown enchantment or a non-map are refused, not skipped" do
      for bad <- [
            %{"famine" => "9"},
            %{"famine" => "x"},
            %{"fireball" => "1"},
            %{"famine" => 1},
            "famine",
            ["famine"]
          ] do
        assert {:error, :bad_enchantments} = CityPanel.changes(ench_form(bad), @details_ench),
               "expected #{inspect(bad)} to be refused"
      end
    end

    test "no enchantment list in the form leaves the enchantments alone" do
      assert {:ok, []} = CityPanel.changes(form(%{}), @details_ench)
    end

    test "the caster select always offers the current caster" do
      row = fn caster -> %{caster: caster} end
      assert CityPanel.caster_options(@details_ench, row.(5)) == @details_ench.owners
      assert CityPanel.caster_options(@details_ench, row.(nil)) == @details_ench.owners
      # a wizard record with no name is not in the list: it is added, so Apply cannot clear it
      assert CityPanel.caster_options(@details_ench, row.(3)) ==
               @details_ench.owners ++ [{3, "Wizard 4"}]
    end
  end

  describe "race and owner" do
    @details_ro %{
      name: "Hialanth",
      population: 6,
      building_states: %{},
      enchantment_casters: %{},
      race_id: 6,
      owner: 0,
      owners: [{0, "Jafar"}, {1, "Freya"}, {5, "Neutral"}]
    }

    test "a different race or owner is a change; the same one is not" do
      assert {:ok, []} = CityPanel.changes(form(%{"race" => "6", "owner" => "0"}), @details_ro)
      assert {:ok, [race: 4]} = CityPanel.changes(form(%{"race" => "4"}), @details_ro)
      assert {:ok, [owner: 5]} = CityPanel.changes(form(%{"owner" => "5"}), @details_ro)

      assert {:ok, [race: 10, owner: 1]} =
               CityPanel.changes(form(%{"race" => "10", "owner" => "1"}), @details_ro)
    end

    test "an unreadable race or owner is refused, not skipped" do
      for bad <- ["14", "-1", "x", ""] do
        assert {:error, :bad_race} = CityPanel.changes(form(%{"race" => bad}), @details_ro)
      end

      for bad <- ["6", "x", ""] do
        assert {:error, :bad_owner} = CityPanel.changes(form(%{"owner" => bad}), @details_ro)
      end

      assert {:error, :bad_race} = CityPanel.changes(form(%{"race" => ["4"]}), @details_ro)
    end

    test "the owner select always offers the current owner" do
      assert CityPanel.owner_options(@details_ro) == @details_ro.owners
      unnamed = %{@details_ro | owner: 3}
      assert CityPanel.owner_options(unnamed) == @details_ro.owners ++ [{3, "Wizard 4"}]
    end

    test "labels say what happened" do
      assert CityPanel.label(@details_ro, race: 4) == "Changed Hialanth's race to Dwarf"
      assert CityPanel.label(@details_ro, owner: 1) == "Gave Hialanth to Freya"
    end
  end
end
