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
end
