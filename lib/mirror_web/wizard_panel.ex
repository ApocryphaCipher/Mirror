defmodule MirrorWeb.WizardPanel do
  @moduledoc """
  What the wizard page shows (STORY-047): the decoded fields of one wizard of a save, in
  words. Pure; `MirrorWeb.WizardLive` draws it.

  The page address is the save's wizard record plus one (`/wizard/1` is the player, record 0).
  Record 5, the neutral player, has no name, gold, mana or books in any save we have looked
  at (SAVE1 to SAVE9, 2026-10-12), only its banner and bytes of the undecoded diplomacy block, so it
  has no page: `details/2` returns `nil` for it, as it does for a record with no name.

  Offsets are from the start of the wizard record; see
  `docs/reference/wizard-record-and-exploration.md`.
  """

  alias Mirror.SaveFile.{Cities, Sites, Units, Wizards}

  @offset 0x9E8
  @record 0x4C8
  @wizards 5

  @retorts ~w(Alchemy Warlord) ++
             ["Chaos Mastery", "Nature Mastery", "Sorcery Mastery", "Infernal Power"] ++
             ["Divine Power", "Sage Master", "Channeler", "Myrran", "Archmage"] ++
             ["Mana Focusing", "Node Mastery", "Famous", "Runemaster", "Conjurer"] ++
             ["Charismatic", "Artificer"]

  @realms ["Nature", "Sorcery", "Chaos", "Life", "Death"]
  @realms_atoms [:nature, :sorcery, :chaos, :life, :death]

  # Spell numbers per ReMoM: 1..40 Nature, 41..80 Sorcery, 81..120 Chaos, 121..160 Life,
  # 161..200 Death, 201..214 Arcane.
  @spell_realms @realms ++ ["Arcane"]

  # The banner colours the page paints, in the same hues as the map's flags and plaques.
  @colours %{
    blue: "#3b6fd4",
    green: "#3fa34d",
    purple: "#8a4fc7",
    red: "#c93a3a",
    yellow: "#d4b02a",
    neutral: "#8a6a3d"
  }

  @doc "The wizard numbers a save has pages for (1 to 5, those with a name), as `{id, name}`."
  @spec wizards(binary()) :: [{pos_integer(), String.t()}]
  def wizards(raw) when is_binary(raw) do
    for {record, name} <- Enum.sort(Wizards.names(raw)), name != "", do: {record + 1, name}
  end

  def wizards(_raw), do: []

  @doc """
  The page number of a map owner (a record index) given the name the panel shows for it, or `nil`
  when there is no page: the neutral player, or a record with no name (a small world).
  """
  @spec page_id(term(), term()) :: pos_integer() | nil
  def page_id(owner, name)
      when is_integer(owner) and owner in 0..(@wizards - 1)//1 and is_binary(name) and name != "",
      do: owner + 1

  def page_id(_owner, _name), do: nil

  @doc "The banner colour (a CSS colour) for a banner atom."
  @spec colour(atom()) :: String.t()
  def colour(banner), do: Map.get(@colours, banner, @colours.neutral)

  @doc "The page's content for wizard number `id` (1-based), or `nil` when there is no such wizard."
  @spec details(binary(), term()) :: map() | nil
  def details(raw, id) when is_binary(raw) and is_integer(id) and id in 1..@wizards//1 do
    record = id - 1
    names = Wizards.names(raw)

    with name when name not in [nil, ""] <- Map.get(names, record),
         true <- byte_size(raw) >= @offset + (record + 1) * @record do
      rec = binary_part(raw, @offset + record * @record, @record)
      banner = Map.get(Wizards.banners(raw), record, :neutral)

      <<portrait, _::binary>> = rec
      <<_::binary-size(0x24), fame::little-16, power_base::little-16, _::binary>> = rec
      <<_::binary-size(0x2A), research, mana_pct, skill_pct, _::binary>> = rec

      <<_::binary-size(0x2E), cx::little-signed-16, cy::little-signed-16, cplane::little-16,
        _::binary>> = rec

      <<_::binary-size(0x54), skill_left::little-16, skill::little-16, tax::little-16, _::binary>> =
        rec

      <<_::binary-size(0x5A), books::binary-size(10), _::binary>> = rec
      <<_::binary-size(0x64), retorts::binary-size(18), _::binary>> = rec

      <<_::binary-size(0x25A), research_left::little-16, mana::little-16, _::binary-size(4),
        researching::little-16, library::binary-size(240), _::binary>> = rec

      <<_::binary-size(0x356), gold::little-16, _::binary>> = rec

      %{
        id: id,
        record: record,
        name: name,
        portrait: portrait,
        banner: banner,
        colour: colour(banner),
        fame: fame,
        power_base: power_base,
        gold: gold,
        mana: mana,
        casting_skill: skill,
        skill_left: skill_left,
        tax: tax_label(tax),
        circle: circle(cx, cy, cplane),
        ratios: %{research: research, mana: mana_pct, skill: skill_pct},
        books:
          for(
            {realm, <<n::little-signed-16>>} <- Enum.zip(@realms, chunks(books, 2)),
            n > 0,
            do: {realm, n}
          ),
        retorts: for({name, 1} <- Enum.zip(@retorts, :binary.bin_to_list(retorts)), do: name),
        retort_flags:
          for(
            {name, byte} <- Enum.zip(@retorts, :binary.bin_to_list(retorts)),
            do: {name, byte == 1}
          ),
        book_counts:
          for(
            {realm, <<n::little-signed-16>>} <- Enum.zip(@realms, chunks(books, 2)),
            do: {realm, n}
          ),
        researching: spell(researching),
        research_left: research_left,
        researching_number: researching,
        library: :binary.bin_to_list(binary_part(library, 0, 214)),
        spells: known_by_realm(library),
        standing: standing(raw, record)
      }
    else
      _ -> nil
    end
  end

  def details(_raw, _id), do: nil

  defp chunks(bin, size), do: for(<<c::binary-size(^size) <- bin>>, do: c)

  defp tax_label(index) when index in 0..6//1 do
    gold = index / 2
    "#{if gold == trunc(gold), do: trunc(gold), else: gold} gold per citizen"
  end

  defp tax_label(index), do: "tax #{index}"

  defp circle(x, y, plane) when x in 0..59//1 and y in 0..39//1 and plane in 0..1//1,
    do: %{x: x, y: y, plane: if(plane == 0, do: :arcanus, else: :myrror)}

  defp circle(_x, _y, _plane), do: nil

  defp spell(0), do: nil
  defp spell(n) when n in 1..214//1, do: %{number: n, realm: Enum.at(@spell_realms, realm_of(n))}
  defp spell(n), do: %{number: n, realm: nil}

  defp realm_of(n) when n <= 200, do: div(n - 1, 40)
  defp realm_of(_n), do: 5

  # State 2 in the library is "known" (checked by editing, wizard-record-and-exploration.md).
  defp known_by_realm(library) do
    known =
      for {2, i} <- Enum.with_index(:binary.bin_to_list(binary_part(library, 0, 214))),
          do: realm_of(i + 1)

    for {realm, index} <- Enum.with_index(@spell_realms),
        do: {realm, Enum.count(known, &(&1 == index))}
  end

  defp standing(raw, record) do
    %{
      cities: count(Cities.parse(raw), record),
      units: count(Units.parse(raw), record),
      nodes:
        case Sites.parse(raw) do
          {:ok, %{nodes: nodes}} -> Enum.count(nodes, &(&1.owner == record))
          _ -> 0
        end
    }
  end

  defp count({:ok, list}, record), do: Enum.count(list, &(&1.owner == record))
  defp count(_error, _record), do: 0

  @doc """
  The edit form's values (`params`) turned into `Mirror.SaveFile.Structures.edit_wizard/3` changes,
  keeping only what differs from `details`, or `{:error, reason}` for a value that is not a number or text
  of the right kind (the same reasons `edit_wizard/3` refuses with).
  """
  @spec changes(map(), map()) :: {:ok, keyword()} | {:error, atom()}
  def changes(params, details) when is_map(params) do
    with {:ok, nums} <- numbers(params, details),
         {:ok, books} <- books(params, details),
         {:ok, retorts} <- retorts(params, details),
         {:ok, spells} <- spells(params, details),
         {:ok, research} <- research(params, details),
         {:ok, name} <- name(params, details) do
      changes =
        nums ++
          if(name != details.name, do: [name: name], else: []) ++
          books ++ retorts ++ spells ++ research

      {:ok, changes}
    end
  end

  def changes(_params, _details), do: {:ok, []}

  defp name(params, details) do
    case Map.get(params, "name", details.name) do
      name when is_binary(name) -> {:ok, String.trim(name)}
      _ -> {:error, :bad_name}
    end
  end

  defp numbers(params, details) do
    Enum.reduce_while([:gold, :mana, :fame], {:ok, []}, fn field, {:ok, acc} ->
      case number(Map.get(params, Atom.to_string(field))) do
        :skip -> {:cont, {:ok, acc}}
        {:ok, n} when n == :erlang.map_get(field, details) -> {:cont, {:ok, acc}}
        {:ok, n} -> {:cont, {:ok, acc ++ [{field, n}]}}
        :error -> {:halt, {:error, :"bad_#{field}"}}
      end
    end)
  end

  defp books(%{"books" => given}, details) when is_map(given) do
    current = Enum.map(details.book_counts, &elem(&1, 1))

    wanted =
      for i <- 0..4 do
        case number(Map.get(given, Integer.to_string(i))) do
          :skip -> {:ok, Enum.at(current, i)}
          other -> other
        end
      end

    if Enum.all?(wanted, &match?({:ok, _}, &1)) do
      wanted = Enum.map(wanted, &elem(&1, 1))
      {:ok, if(wanted == current, do: [], else: [books: wanted])}
    else
      {:error, :bad_books}
    end
  end

  # A `books` value that is not a map is a bad form, not an omitted field.
  defp books(%{"books" => _}, _details), do: {:error, :bad_books}
  defp books(_params, _details), do: {:ok, []}

  # A checkbox that is not ticked is not sent, so `retorts_present` says the form had them.
  defp retorts(%{"retorts_present" => _} = params, details) do
    case Map.get(params, "retorts", %{}) do
      given when is_map(given) ->
        wanted =
          for i <- 0..(length(details.retort_flags) - 1),
              do: Map.get(given, Integer.to_string(i)) in ["on", "true"]

        current = Enum.map(details.retort_flags, &elem(&1, 1))
        {:ok, if(wanted == current, do: [], else: [retorts: wanted])}

      _ ->
        {:error, :bad_retorts}
    end
  end

  defp retorts(_params, _details), do: {:ok, []}

  # The spell checkboxes (`spells[N]` = "on" for known); `spells_present` says the form had them. Ticking a
  # spell makes it known (2); unticking a known one makes it knowable again (1). Others are left as they are.
  defp spells(%{"spells_present" => _} = params, details) do
    case Map.get(params, "spells", %{}) do
      given when is_map(given) ->
        changes =
          for {state, number} <- Enum.with_index(details.library, 1),
              # a generator, not `want = ...`: a `false` there would be a filter and drop the spell
              want <- [Map.get(given, Integer.to_string(number)) in ["on", "true"]],
              new <- [spell_state(state, want)],
              new != state,
              do: {number, new}

        {:ok, if(changes == [], do: [], else: [spells: changes])}

      _ ->
        {:error, :bad_spells}
    end
  end

  defp spells(_params, _details), do: {:ok, []}

  defp spell_state(_state, true), do: 2
  defp spell_state(2, false), do: 1
  defp spell_state(state, false), do: state

  defp research(params, details) do
    with {:ok, spell} <-
           optional_change(params, "researching", details.researching_number, :bad_researching),
         {:ok, left} <-
           optional_change(params, "research_left", details.research_left, :bad_research_left) do
      {:ok, Enum.reject([researching: spell, research_left: left], &(elem(&1, 1) == :same))}
    end
  end

  defp optional_change(params, key, current, error) do
    case number(Map.get(params, key)) do
      :skip -> {:ok, :same}
      {:ok, ^current} -> {:ok, :same}
      {:ok, n} -> {:ok, n}
      :error -> {:error, error}
    end
  end

  @doc """
  The change that makes every spell of `realm` (an atom of `Mirror.Spells.realms/0`) known, or `[]` when all are. Spells
  are numbered by realm: 40 each for the five realms, then the 14 Arcane spells (201 to 214).
  """
  @spec learn_realm(map(), atom()) :: keyword()
  def learn_realm(details, realm) do
    numbers = realm_numbers(realm)

    case for(n <- numbers, Enum.at(details.library, n - 1) != 2, do: {n, 2}) do
      [] -> []
      changes -> [spells: changes]
    end
  end

  @doc "The spell numbers of a realm."
  @spec realm_numbers(atom()) :: [pos_integer()]
  def realm_numbers(:arcane), do: Enum.to_list(201..214)

  def realm_numbers(realm) do
    case Enum.find_index(@realms_atoms, &(&1 == realm)) do
      nil -> []
      i -> Enum.to_list((i * 40 + 1)..(i * 40 + 40))
    end
  end

  @doc """
  The spell library of `details` grouped by realm, each spell with its name, cost and state, for the page. `table` is
  `Mirror.Spells.table/0`'s map (or `nil`, then spells have number names).
  """
  @spec spell_rows(map(), map() | nil) :: [{atom(), [map()]}]
  def spell_rows(details, table) do
    for realm <- @realms_atoms ++ [:arcane] do
      rows =
        for n <- realm_numbers(realm) do
          state = Enum.at(details.library, n - 1)
          spell = if is_map(table), do: Map.get(table, n)

          %{
            number: n,
            name: Mirror.Spells.name(table, n),
            cost: spell && spell.cost,
            state: state
          }
        end

      {realm, rows}
    end
  end

  defp number(nil), do: :skip
  defp number(""), do: :skip

  defp number(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp number(_), do: :error

  @doc "A short description of an edit, for the notice and the undo list."
  @spec label(map(), keyword()) :: String.t()
  def label(details, changes) do
    parts =
      Enum.map(changes, fn
        {:gold, n} -> "gold #{n}"
        {:mana, n} -> "mana #{n}"
        {:fame, n} -> "fame #{n}"
        {:name, n} -> "name #{n}"
        {:books, _} -> "books"
        {:retorts, _} -> "retorts"
        {:spells, list} -> "#{length(list)} #{if length(list) == 1, do: "spell", else: "spells"}"
        {:researching, 0} -> "no spell researched"
        {:researching, n} -> "researching spell #{n}"
        {:research_left, n} -> "#{n} research points left"
      end)

    "Edited #{details.name}: #{Enum.join(parts, ", ")}"
  end

  @doc "The words for a refused edit."
  @spec error_message(term()) :: String.t()
  def error_message(:bad_gold), do: "Gold is a whole number from 0 to 30000."
  def error_message(:bad_mana), do: "Mana is a whole number from 0 to 30000."
  def error_message(:bad_fame), do: "Fame is a whole number from 0 to 30000."

  def error_message(:bad_name),
    do: "A name is 1 to 19 letters, digits or punctuation (no accents)."

  def error_message(:bad_books), do: "Books are whole numbers from 0 to 13."
  def error_message(:bad_spells), do: "Those spells could not be read."

  def error_message(:bad_researching),
    do: "Researching is a spell number from 1 to 214, or 0 for none."

  def error_message(:bad_research_left),
    do: "Research points left is a whole number from 0 to 65535."

  def error_message(:bad_retorts), do: "Those retorts could not be read."
  def error_message(:no_such_wizard), do: "That wizard is no longer in the save."
  def error_message(:nothing_changed), do: "Nothing to change."
  def error_message(_other), do: "The wizard could not be changed."
end
