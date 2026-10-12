defmodule MirrorWeb.LairPanel do
  @moduledoc """
  What the lair panel shows (STORY-020) and accepts: one encounter zone (a lair, cave, temple,
  ruin, keep, a node's guardians or a Tower of Wizardry) in words, and the edit form's values
  turned into `Mirror.SaveFile.Structures.edit_encounter/3` changes. Pure; the page
  (`MirrorWeb.MapLive`) draws it.

  The treasure code, flags and items are shown, not edited: what the code means is
  not decoded.
  """

  alias Mirror.SaveFile.{Encounters, UnitTypes}

  @type details :: map()

  @doc "The panel's content for encounter `index`, or `nil` when the save has none."
  @spec details(binary(), non_neg_integer() | nil) :: details() | nil
  def details(raw, index) when is_binary(raw) and is_integer(index) do
    case Encounters.get(raw, index) do
      nil ->
        nil

      e ->
        %{
          index: e.index,
          x: e.x,
          y: e.y,
          plane: if(e.plane == 0, do: :arcanus, else: :myrror),
          kind: e.kind,
          kind_name: Encounters.kind_name(e.kind),
          tower?: e.kind == 0,
          intact: e.intact,
          slots: slots(e.guards),
          gold: e.gold,
          mana: e.mana,
          spell_code: e.spell_code,
          item_count: e.item_count,
          items: e.items,
          flags: e.flags
        }
    end
  end

  def details(_raw, _index), do: nil

  # Both slots, always: `%{slot, type, name, left, start}` or an empty one with type `nil`.
  defp slots(guards) do
    for slot <- [1, 2] do
      case Enum.find(guards, &(&1.slot == slot)) do
        nil ->
          %{slot: slot, type: nil, name: nil, left: nil, start: nil}

        g ->
          %{
            slot: slot,
            type: g.type,
            name: UnitTypes.display_name(g.type),
            left: g.left,
            start: g.start
          }
      end
    end
  end

  @doc "The unit type select's options, `{id, name}` for every type."
  @spec unit_type_options() :: [{non_neg_integer(), String.t()}]
  def unit_type_options, do: for(id <- 0..197, do: {id, UnitTypes.display_name(id)})

  @doc """
  The form's params (`"intact"` with its `"intact_present"` marker, `"guard1_type"`,
  `"guard1_count"`, `"guard2_type"`, `"guard2_count"`, `"gold"`, `"mana"`) as the keyword list
  `Structures.edit_encounter/3` takes, keeping only what differs from `details`. `{:ok, []}` when
  nothing changed. A guard slot with a type needs a count (`:bad_guards`), a reward that is not a
  whole number is `:bad_gold` or `:bad_mana`, and an unreadable type is `:bad_guards`.
  """
  @spec changes(map(), details()) :: {:ok, keyword()} | {:error, atom()}
  def changes(params, details) do
    with {:ok, intact} <- intact_change(params, details),
         {:ok, guards} <- guard_changes(params, details),
         {:ok, gold} <- number_change(params, "gold", :gold, details.gold, :bad_gold),
         {:ok, mana} <- number_change(params, "mana", :mana, details.mana, :bad_mana) do
      {:ok, intact ++ guards ++ gold ++ mana}
    end
  end

  defp intact_change(%{"intact_present" => _} = params, details) do
    wanted = Map.get(params, "intact") in ["on", "true"]
    if wanted == details.intact, do: {:ok, []}, else: {:ok, [intact: wanted]}
  end

  defp intact_change(_params, _details), do: {:ok, []}

  defp guard_changes(params, details) do
    Enum.reduce_while(details.slots, {:ok, %{}}, fn slot, {:ok, acc} ->
      type = Map.get(params, "guard#{slot.slot}_type")
      count = Map.get(params, "guard#{slot.slot}_count")

      case guard_slot(slot, type, count) do
        :unchanged -> {:cont, {:ok, acc}}
        {:ok, guard} -> {:cont, {:ok, Map.put(acc, slot.slot, guard)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, changed} when map_size(changed) == 0 -> {:ok, []}
      {:ok, changed} -> {:ok, [guards: changed]}
      error -> error
    end)
  end

  # No such field in the form: the slot is left as it is.
  defp guard_slot(_slot, nil, nil), do: :unchanged

  defp guard_slot(slot, "", _count), do: if(slot.type == nil, do: :unchanged, else: {:ok, nil})

  defp guard_slot(slot, type, count) when is_binary(type) and is_binary(count) do
    with {t, ""} <- Integer.parse(type),
         {c, ""} <- Integer.parse(count) do
      if {t, c} == {slot.type, slot.left}, do: :unchanged, else: {:ok, {t, c}}
    else
      _ -> {:error, :bad_guards}
    end
  end

  defp guard_slot(_slot, _type, _count), do: {:error, :bad_guards}

  defp number_change(params, key, field, current, error) do
    case Map.fetch(params, key) do
      :error ->
        {:ok, []}

      {:ok, value} when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {n, ""} -> {:ok, if(n == current, do: [], else: [{field, n}])}
          _ -> {:error, error}
        end

      {:ok, _} ->
        {:error, error}
    end
  end

  @doc "A short description of what the changes do, for the notice and undo."
  @spec label(details(), keyword()) :: String.t()
  def label(details, changes) do
    what = "the #{String.downcase(details.kind_name)}"

    case Keyword.keys(changes) do
      [:intact] -> if changes[:intact], do: "Restored #{what}", else: "Cleared #{what}"
      [:gold] -> "Set #{what}'s gold to #{changes[:gold]}"
      [:mana] -> "Set #{what}'s mana to #{changes[:mana]}"
      [:guards] -> "Changed #{what}'s guards" <> guard_delta(changes[:guards])
      _ -> "Edited #{what}"
    end
  end

  defp guard_delta(slots) do
    parts =
      for {_slot, guard} <- Enum.sort(slots) do
        case guard do
          nil -> "-guard"
          {type, count} -> "#{count} #{UnitTypes.display_name(type)}"
        end
      end

    " (" <> Enum.join(parts, ", ") <> ")"
  end

  @doc "The notice for a refused edit."
  def error_message(:bad_guards), do: "A guard needs a unit and a count from 1 to 8."
  def error_message(:bad_gold), do: "Gold is a whole number from 0 to 30000."
  def error_message(:bad_mana), do: "Mana is a whole number from 0 to 30000."
  def error_message(:bad_intact), do: "That is not a valid state."
  def error_message(:no_such_encounter), do: "That site is no longer in the save."
  def error_message(:nothing_changed), do: "Nothing to change."
  def error_message(_other), do: "The site could not be changed."
end
