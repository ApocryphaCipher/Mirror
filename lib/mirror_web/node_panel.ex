defmodule MirrorWeb.NodePanel do
  @moduledoc """
  What the node panel shows (STORY-020) and accepts: one magic node in words, its guardians,
  and the edit form's values turned into `Mirror.SaveFile.Structures.edit_node/3` changes.
  Pure; the page (`MirrorWeb.MapLive`) draws it.

  A node is **melded** when it has an owner. In every save here an owned node has its guardians
  cleared and an unowned one still has them, so giving a node an owner also clears the
  guardians (`melding_clears_guardians?/2`), and the panel has a button that clears them alone.
  """

  alias Mirror.SaveFile.{Encounters, Structures, UnitTypes, Wizards}

  @type details :: map()

  @type_names %{0 => "Sorcery", 1 => "Nature", 2 => "Chaos"}

  @doc "The panel's content for node `index`, or `nil` when the save has no such node."
  @spec details(binary(), non_neg_integer() | nil) :: details() | nil
  def details(raw, index) when is_binary(raw) and is_integer(index) do
    case Structures.node_info(raw, index) do
      nil ->
        nil

      node ->
        names = Wizards.names(raw)
        guardians = guardians(raw, node)

        %{
          index: node.index,
          x: node.x,
          y: node.y,
          plane: if(node.plane == 0, do: :arcanus, else: :myrror),
          type: node.type,
          type_name: Map.fetch!(@type_names, node.type),
          power: node.power,
          owner: node.owner,
          owner_name: node.owner && Map.get(names, node.owner, "Wizard #{node.owner + 1}"),
          owners: for(o <- 0..4, name = Map.get(names, o), name != "", do: {o, name}),
          warped: node.warped,
          spirit_meld: node.spirit_meld,
          guardian_record: guardians && guardians.index,
          guardians_alive: guardians != nil and guardians.intact,
          guards: guardians && guardians.guards
        }
    end
  end

  def details(_raw, _index), do: nil

  # The encounter record that holds the node's defenders: kind 1 to 3 on the node's tile.
  defp guardians(raw, node) do
    case Enum.find(Encounters.at(raw, {node.x, node.y, node.plane}), &(&1.kind in 1..3)) do
      nil ->
        nil

      e ->
        %{
          index: e.index,
          intact: e.intact,
          guards: for(g <- e.guards, do: %{name: UnitTypes.display_name(g.type), left: g.left})
        }
    end
  end

  @doc """
  The owner select's options: the named wizards, and the node's current owner too if it is
  none of them, so that applying the form never changes it by accident.
  """
  @spec owner_options(details()) :: [{non_neg_integer(), String.t()}]
  def owner_options(%{owner: nil, owners: owners}), do: owners

  def owner_options(%{owner: owner, owners: owners}) do
    if Enum.any?(owners, fn {o, _} -> o == owner end),
      do: owners,
      else: owners ++ [{owner, "Wizard #{owner + 1}"}]
  end

  @doc """
  The form's params (`"owner"`: `""` for none or a wizard record number, and `"warped"` and
  `"spirit_meld"` with a `"flags_present"` marker) as the keyword list `Structures.edit_node/3`
  takes, keeping only what differs from `details`. An unreadable owner is `:bad_owner`, a flag value other than `"on"` or `"true"` is `:bad_flag`; a form
  with none of the fields changes nothing.
  """
  @spec changes(map(), details()) :: {:ok, keyword()} | {:error, :bad_owner | :bad_flag}
  def changes(params, details) do
    with {:ok, owner} <- owner_change(params, details),
         {:ok, flags} <- flag_changes(params, details) do
      {:ok, owner ++ flags}
    end
  end

  defp owner_change(params, details) do
    case Map.fetch(params, "owner") do
      :error ->
        {:ok, []}

      {:ok, ""} ->
        {:ok, if(details.owner == nil, do: [], else: [owner: nil])}

      {:ok, value} when is_binary(value) ->
        case Integer.parse(value) do
          {n, ""} when n == details.owner -> {:ok, []}
          {n, ""} when n in 0..4 -> {:ok, [owner: n]}
          _ -> {:error, :bad_owner}
        end

      {:ok, _} ->
        {:error, :bad_owner}
    end
  end

  # With the marker, a missing key is an unticked box, as a browser posts nothing for one. A
  # value that is present but is not what a ticked box posts is refused, not read as unticked.
  defp flag_changes(%{"flags_present" => _} = params, details) do
    Enum.reduce_while([{"warped", :warped}, {"spirit_meld", :spirit_meld}], {:ok, []}, fn
      {key, field}, {:ok, acc} ->
        case Map.fetch(params, key) do
          :error -> {:cont, {:ok, add_flag(acc, field, false, details)}}
          {:ok, v} when v in ["on", "true"] -> {:cont, {:ok, add_flag(acc, field, true, details)}}
          {:ok, _} -> {:halt, {:error, :bad_flag}}
        end
    end)
  end

  defp flag_changes(_params, _details), do: {:ok, []}

  defp add_flag(acc, field, wanted, details),
    do: if(wanted == Map.fetch!(details, field), do: acc, else: acc ++ [{field, wanted}])

  @doc """
  True when applying `changes` gives an owner to a node whose guardians are still alive: melding
  needs them gone, so the editor clears them in the same step.
  """
  @spec melding_clears_guardians?(details(), keyword()) :: boolean()
  def melding_clears_guardians?(details, changes) do
    is_integer(changes[:owner]) and details.guardians_alive
  end

  @doc "A short description of what the changes do, for the notice and undo."
  @spec label(details(), keyword()) :: String.t()
  def label(details, changes) do
    what = "the #{details.type_name} node"

    case Keyword.keys(changes) do
      [:owner] -> owner_label(details, what, changes[:owner])
      [:warped] -> if changes[:warped], do: "Warped #{what}", else: "Unwarped #{what}"
      [:spirit_meld] -> "Changed #{what}'s Guardian Spirit meld"
      _ -> "Edited #{what}"
    end
  end

  defp owner_label(_details, what, nil), do: "Took away #{what}'s melder"

  defp owner_label(details, what, owner) do
    name = details |> owner_options() |> Map.new() |> Map.get(owner, "wizard #{owner + 1}")
    "Gave #{what} to #{name}"
  end

  @doc "The notice for a refused edit."
  def error_message(:bad_owner), do: "That is not a wizard."
  def error_message(:bad_flag), do: "That is not a valid setting."
  def error_message(:no_such_node), do: "That node is no longer in the save."
  def error_message(:nothing_changed), do: "Nothing to change."
  def error_message(_other), do: "The node could not be changed."
end
