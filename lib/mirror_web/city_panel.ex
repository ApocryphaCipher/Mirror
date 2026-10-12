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
        race_id: city.race,
        size: Cities.size_name(city.size),
        population: city.population,
        walled: city.walled,
        garrison: garrison(raw, city),
        buildings: buildings(city, :built),
        building_states: city.buildings,
        enchantment_casters: city.enchantments,
        owners:
          for(owner <- 0..4, name = Map.get(names, owner), name != "", do: {owner, name}) ++
            [{5, "Neutral"}],
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
  One row per building a city can have, for the form's checklist: `%{id, name, state,
  missing}` where `state` is `:built`, `:replaced` or `nil`, and `missing` names the
  buildings it needs that the city lacks (a hint: the game only enforces needs when a
  player builds, and neutral cities break them).
  """
  @spec building_rows(details()) :: [map()]
  def building_rows(details) do
    present = Map.keys(details.building_states)

    for id <- Cities.building_ids() do
      state = Map.get(details.building_states, id)

      missing =
        if state == :built,
          do:
            for(
              need <- Cities.building_requires(id),
              need not in present,
              do: Cities.building_name(need)
            ),
          else: []

      %{id: id, name: Cities.building_name(id), state: state, missing: missing}
    end
  end

  @doc """
  One row per city enchantment, for the form: `%{name, title, caster}` where `caster` is a
  wizard index or `nil`.
  """
  @spec enchantment_rows(details()) :: [map()]
  def enchantment_rows(details) do
    for name <- Cities.enchantment_names() do
      %{
        name: name,
        title: Cities.enchantment_title(name),
        caster: Map.get(details.enchantment_casters, name)
      }
    end
  end

  @doc "The race select's options, `{id, name}`."
  def race_options, do: Cities.races()

  @doc """
  The owner select's options: the wizards, neutral, and the city's current owner too if it is
  none of those, so that applying the form never changes it by accident.
  """
  @spec owner_options(details()) :: [{non_neg_integer(), String.t()}]
  def owner_options(details) do
    if Enum.any?(details.owners, fn {index, _} -> index == details.owner end),
      do: details.owners,
      else: details.owners ++ [{details.owner, "Wizard #{details.owner + 1}"}]
  end

  @doc """
  The options of one enchantment's caster select: the wizards, the neutral record, and the
  current caster too if it is none of those (a record without a name), so that applying the
  form never silently changes who cast it.
  """
  @spec caster_options(details(), map()) :: [{non_neg_integer(), String.t()}]
  def caster_options(details, %{caster: caster}) do
    if is_nil(caster) or Enum.any?(details.owners, fn {index, _} -> index == caster end),
      do: details.owners,
      else: details.owners ++ [{caster, "Wizard #{caster + 1}"}]
  end

  @doc """
  The edit form's params (`%{"name" => ..., "population" => ...}`) as the keyword list
  `Structures.edit_city/3` takes, keeping only what differs from `details`. `{:ok, []}`
  when nothing changed; `{:error, :bad_population}` for a population that is not a whole
  number, `{:error, :bad_buildings}` for a building list that is not a list of whole numbers
  (nothing is guessed or dropped: a malformed list is refused, not read as "no buildings").
  """
  @spec changes(map(), details()) ::
          {:ok, keyword()}
          | {:error,
             :bad_population | :bad_race | :bad_owner | :bad_buildings | :bad_enchantments}
  def changes(params, details) do
    name = params |> Map.get("name", details.name) |> String.trim()
    population = Map.get(params, "population", Integer.to_string(details.population))

    with {:ok, population} <- parse_population(population),
         {:ok, race} <- choice_change(params, details, "race", :race_id, :race, :bad_race, 13),
         {:ok, owner} <- choice_change(params, details, "owner", :owner, :owner, :bad_owner, 5),
         {:ok, buildings} <- building_changes(params, details),
         {:ok, enchantments} <- enchantment_changes(params, details) do
      scalars =
        [name: name, population: population]
        |> Enum.reject(fn {field, value} -> Map.fetch!(details, field) == value end)

      {:ok, scalars ++ race ++ owner ++ buildings ++ enchantments}
    end
  end

  # A select that posts a whole number 0..max (race, owner); no field in the form is no change,
  # an unreadable one is refused.
  defp choice_change(params, details, key, detail_key, field, error, max) do
    case Map.fetch(params, key) do
      :error ->
        {:ok, []}

      {:ok, value} when is_binary(value) ->
        case Integer.parse(value) do
          {n, ""} when n in 0..max//1 ->
            {:ok, if(n == Map.fetch!(details, detail_key), do: [], else: [{field, n}])}

          _ ->
            {:error, error}
        end

      {:ok, _} ->
        {:error, error}
    end
  end

  # The checklist posts the ids of the boxes that are ticked, plus a marker so that
  # "all unticked" is different from "the form had no checklist".
  defp building_changes(%{"buildings_present" => _} = params, details) do
    with {:ok, ids} <- parse_building_ids(Map.get(params, "buildings", [])) do
      wanted = ids |> Enum.sort() |> Enum.uniq()

      if wanted == details.building_states |> Map.keys() |> Enum.sort(),
        do: {:ok, []},
        else: {:ok, [buildings: wanted]}
    end
  end

  defp building_changes(_params, _details), do: {:ok, []}

  # Every value must be a whole number; a range check is `Structures.edit_city/3`'s job.
  defp parse_building_ids(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case is_binary(value) && Integer.parse(value) do
        {n, ""} -> {:cont, {:ok, [n | acc]}}
        _ -> {:halt, {:error, :bad_buildings}}
      end
    end)
  end

  defp parse_building_ids(_values), do: {:error, :bad_buildings}

  # One select per enchantment ("" for none, else the caster's wizard record 0..5); only the
  # ones that differ from the city are changes. A value that is not one of those, or a name that
  # is not an enchantment, is refused like a malformed building list, not skipped.
  defp enchantment_changes(%{"enchantments_present" => _} = params, details) do
    case Map.get(params, "enchantments", %{}) do
      chosen when is_map(chosen) ->
        known = Map.new(Cities.enchantment_names(), &{Atom.to_string(&1), &1})

        Enum.reduce_while(chosen, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
          with {:ok, name} <- Map.fetch(known, key),
               {:ok, caster} <- parse_caster(value) do
            if caster == Map.get(details.enchantment_casters, name),
              do: {:cont, {:ok, acc}},
              else: {:cont, {:ok, Map.put(acc, name, caster)}}
          else
            _ -> {:halt, {:error, :bad_enchantments}}
          end
        end)
        |> then(fn
          {:ok, changed} when map_size(changed) == 0 -> {:ok, []}
          {:ok, changed} -> {:ok, [enchantments: changed]}
          error -> error
        end)

      _ ->
        {:error, :bad_enchantments}
    end
  end

  defp enchantment_changes(_params, _details), do: {:ok, []}

  # `{:ok, nil}` for "none", `{:ok, wizard_index}` or `:error`.
  defp parse_caster(""), do: {:ok, nil}

  defp parse_caster(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n in 0..5 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_caster(_value), do: :error

  @doc "A short description of what the changes do, for the undo button and the notice."
  @spec label(details(), keyword()) :: String.t()
  def label(details, changes) do
    case Keyword.keys(changes) do
      [:name] ->
        "Renamed #{details.name} to #{changes[:name]}"

      [:population] ->
        "Set #{details.name}'s population to #{changes[:population]}"

      [:buildings] ->
        "Changed #{details.name}'s buildings" <> building_delta(details, changes[:buildings])

      [:race] ->
        "Changed #{details.name}'s race to #{Cities.race_name(changes[:race])}"

      [:owner] ->
        "Gave #{details.name} to #{owner_name(details, changes[:owner])}" <>
          if(details.enchantment_casters == %{}, do: "", else: " (its enchantments are cleared)")

      [:enchantments] ->
        "Changed #{details.name}'s enchantments" <>
          enchantment_delta(details, changes[:enchantments])

      _ ->
        "Edited #{details.name}"
    end
  end

  defp owner_name(details, owner) do
    details |> owner_options() |> Map.new() |> Map.get(owner, "wizard #{owner + 1}")
  end

  defp enchantment_delta(details, wanted) do
    owners = Map.new(details.owners)

    parts =
      for {name, caster} <- Enum.sort(wanted) do
        case caster do
          nil -> "-" <> Cities.enchantment_title(name)
          n -> "+" <> Cities.enchantment_title(name) <> " (" <> Map.get(owners, n, "?") <> ")"
        end
      end

    if parts == [], do: "", else: " (" <> Enum.join(parts, ", ") <> ")"
  end

  defp building_delta(details, wanted) do
    present = Map.keys(details.building_states)
    added = for id <- wanted, id not in present, do: "+" <> Cities.building_name(id)
    removed = for id <- present, id not in wanted, do: "-" <> Cities.building_name(id)

    case added ++ removed do
      [] -> ""
      parts -> " (" <> Enum.join(parts, ", ") <> ")"
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
  def error_message(:bad_buildings), do: "That is not a list of buildings."
  def error_message(:bad_enchantments), do: "That is not a valid enchantment or caster."
  def error_message(:bad_race), do: "That is not one of the game's races."
  def error_message(:bad_owner), do: "That is not a wizard or the neutral player."

  def error_message(:capital),
    do:
      "That city is a wizard's capital (his fortress or summoning circle is in it), so it cannot change hands here."

  def error_message(:no_such_city), do: "That city is no longer in the save."
  def error_message(_other), do: "The city could not be changed."
end
