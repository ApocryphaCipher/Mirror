defmodule MirrorWeb.CityPanel do
  @moduledoc """
  What the city panel shows (STORY-020) and what it accepts: the decoded fields of one
  city of a save, in words, and the values of its edit form turned into
  `Mirror.SaveFile.Structures.edit_city/3` changes. Pure; the page
  (`MirrorWeb.MapLive`) draws it.
  """

  alias Mirror.SaveFile.{Cities, Units, Wizards}

  @type details :: map()

  @doc "The panel's content for city `index`, or `nil` when the save has no such city."
  @spec details(binary(), non_neg_integer() | nil) :: details() | nil
  def details(raw, index) when is_binary(raw) and is_integer(index) do
    with {:ok, cities} <- Cities.parse(raw),
         %{} = city <- Enum.find(cities, &(&1.index == index)) do
      names = Wizards.names(raw)
      banners = Wizards.banners(raw)

      %{
        index: city.index,
        name: city.name,
        x: city.x,
        y: city.y,
        plane: city.plane,
        owner: city.owner,
        owner_name: Map.get(names, city.owner, "Neutral"),
        banner: Map.get(banners, city.owner, :neutral),
        race: Cities.race_name(city.race),
        size: Cities.size_name(city.size),
        population: city.population,
        walled: city.walled,
        garrison: garrison(raw, city),
        buildings: buildings(city, :built),
        replaced: buildings(city, :replaced),
        enchantments: enchantments(city, names),
        road_links:
          for(i <- city.road_links, other = Enum.find(cities, &(&1.index == i)), do: other.name)
      }
    else
      _ -> nil
    end
  end

  def details(_raw, _index), do: nil

  defp garrison(raw, city) do
    case Units.parse(raw) do
      {:ok, units} ->
        Enum.count(units, &({&1.x, &1.y, &1.plane} == {city.x, city.y, city.plane}))

      _ ->
        0
    end
  end

  defp buildings(city, status) do
    for {id, ^status} <- Enum.sort(city.buildings), do: Cities.building_name(id)
  end

  defp enchantments(city, wizard_names) do
    for {name, caster} <- Enum.sort(city.enchantments) do
      {name |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
       Map.get(wizard_names, caster, "?")}
    end
  end

  @doc """
  The edit form's params (`%{"name" => ..., "population" => ...}`) as the keyword list
  `Structures.edit_city/3` takes, keeping only what differs from `details`. `{:ok, []}`
  when nothing changed; `{:error, :bad_population}` for a population that is not a whole
  number.
  """
  @spec changes(map(), details()) :: {:ok, keyword()} | {:error, :bad_population}
  def changes(params, details) do
    name = params |> Map.get("name", details.name) |> String.trim()
    population = Map.get(params, "population", Integer.to_string(details.population))

    with {:ok, population} <- parse_population(population) do
      {:ok,
       [name: name, population: population]
       |> Enum.reject(fn {field, value} -> Map.fetch!(details, field) == value end)}
    end
  end

  defp parse_population(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :bad_population}
    end
  end

  defp parse_population(_value), do: {:error, :bad_population}

  @doc "The notice for a refused edit."
  def error_message(:bad_name),
    do: "A name is 1 to 13 characters: letters, digits and punctuation, no accents."

  def error_message(:bad_population), do: "Population is a whole number from 1 to 25."
  def error_message(:no_such_city), do: "That city is no longer in the save."
  def error_message(_other), do: "The city could not be changed."
end
