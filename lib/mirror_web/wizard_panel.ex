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

  alias Mirror.SaveFile.{Cities, Heroes, Items, Sites, UnitTypes, Units, Wizards}

  @offset 0x9E8
  @record 0x4C8
  @wizards 5

  @retorts ~w(Alchemy Warlord) ++
             ["Chaos Mastery", "Nature Mastery", "Sorcery Mastery", "Infernal Power"] ++
             ["Divine Power", "Sage Master", "Channeler", "Myrran", "Archmage"] ++
             ["Mana Focusing", "Node Mastery", "Famous", "Runemaster", "Conjurer"] ++
             ["Charismatic", "Artificer"]

  # The 24 global enchantments in the save's byte order (`MMOMS.TXT` appendix A.3; its "Aura of
  # Mastery" at 3 is Aura of Majesty: casting that spell set byte 3, checked 2026-10-12). Byte 3 and 18 (Just
  # Cause) were seen set in the real game; the names of the others are the book's order, *not yet seen set*.
  @globals [
    "Eternal Night",
    "Evil Omens",
    "Zombie Mastery",
    "Aura of Majesty",
    "Wind Mastery",
    "Suppress Magic",
    "Time Stop",
    "Nature Awareness",
    "Nature's Wrath",
    "Herb Mastery",
    "Chaos Surge",
    "Doom Mastery",
    "Great Wasting",
    "Meteor Storm",
    "Armageddon",
    "Tranquility",
    "Life Force",
    "Crusade",
    "Just Cause",
    "Holy Arms",
    "Planar Seal",
    "Charm of Life",
    "Detect Magic",
    "Awareness"
  ]

  @time_stop 6

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
      <<_::binary-size(0x34), candidates::binary-size(16), _::binary>> = rec

      <<_::binary-size(0x2E), cx::little-signed-16, cy::little-signed-16, cplane::little-16,
        _::binary>> = rec

      <<_::binary-size(0x54), skill_left::little-16, skill::little-16, tax::little-16, _::binary>> =
        rec

      <<_::binary-size(0x5A), books::binary-size(10), _::binary>> = rec
      <<_::binary-size(0x64), retorts::binary-size(18), _::binary>> = rec

      <<_::binary-size(0x25A), research_left::little-16, mana::little-16, _::binary-size(4),
        researching::little-16, library::binary-size(240), _::binary>> = rec

      <<_::binary-size(0x356), gold::little-16, _::binary>> = rec
      <<_::binary-size(0x128), diplomacy::binary-size(306), _::binary>> = rec
      <<_::binary-size(0x482), globals::binary-size(24), _::binary>> = rec

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
        banished: banished?(raw, record),
        relations: relations(raw, record, names, diplomacy),
        globals:
          for(
            {name, value} when value != 0 <- Enum.zip(@globals, :binary.bin_to_list(globals)),
            do: name
          ),
        global_flags:
          for(
            {name, value} <- Enum.zip(@globals, :binary.bin_to_list(globals)),
            do: {name, value != 0}
          ),
        heroes:
          for(
            hero <- Heroes.for_wizard(raw, record),
            do: Map.put(hero, :item_list, Items.for_indexes(raw, hero.items))
          ),
        vault: Items.for_indexes(raw, Items.vault(raw, record)),
        vault_places: Items.vault_places(raw, record),
        free_hero_slots: free_hero_slots(raw, record),
        heroes_in_play: heroes_in_play(raw),
        candidates: for(<<n::little-16 <- candidates>>, n in 1..214//1, do: n),
        library: :binary.bin_to_list(binary_part(library, 0, 214)),
        spells: known_by_realm(library),
        standing: standing(raw, record)
      }
    else
      _ -> nil
    end
  end

  def details(_raw, _id), do: nil

  # The diplomacy block's arrays (`+0` contacted, `+42` visible relations, `+48` status), by the other player
  # 0 to 5 (5 is the neutral player). The tag words: 0 none and 1 pact are checked in the real game
  # (2026-10-12); 2 alliance and 3 war are the saved values' natural reading, *not yet changed in the game*.
  # A wizard is **banished** when the "active" byte of his fortress record (`0x65F8 + 4 × record + 3`) is 0:
  # the game draws him as a cracked stone frame on the Magic screen. Checked both ways in the real game
  # (2026-10-13): that one byte cleared on a living wizard cracked his frame; set on a banished one, it
  # went away (STORY-050). Banished is not dead: the manual says a wizard who loses his fortress starts casting
  # Spell of Return and is only resigned with no cities left (`MMOMS.TXT` 5.3).
  @fortress_block 0x65F8

  defp banished?(raw, record) when record in 0..4//1 do
    byte_size(raw) > @fortress_block + record * 4 + 3 and
      :binary.at(raw, @fortress_block + record * 4 + 3) == 0
  end

  defp banished?(_raw, _record), do: false

  defp relations(raw, record, names, diplomacy) do
    <<contacted::binary-size(6), _::binary-size(36), relations::binary-size(6),
      status::binary-size(6), _::binary>> = diplomacy

    for other <- 0..5, other != record, other == 5 or Map.get(names, other, "") != "" do
      <<relation::signed>> = binary_part(relations, other, 1)

      %{
        other: other,
        name: if(other == 5, do: "Neutral", else: Map.fetch!(names, other)),
        page: page_id(other, if(other == 5, do: "", else: Map.fetch!(names, other))),
        contacted: :binary.at(contacted, other) != 0,
        banished: banished?(raw, other),
        relation: relation,
        status: :binary.at(status, other),
        tag: status_tag(:binary.at(status, other))
      }
    end
  end

  @doc "The standings the editor offers, as `{code, label}`; a code outside them (4, or an unknown one) is kept as the current choice."
  @spec status_options(non_neg_integer()) :: [{non_neg_integer(), String.t()}]
  def status_options(current) do
    base = [{0, "None"}, {1, "Wizard pact"}, {2, "Alliance"}, {3, "War"}]
    if current in 0..3, do: base, else: base ++ [{current, status_tag(current) <> "?"}]
  end

  defp status_tag(0), do: "None"
  defp status_tag(1), do: "Wizard pact"
  defp status_tag(2), do: "Alliance"
  defp status_tag(3), do: "War"
  defp status_tag(4), do: "Final war"
  defp status_tag(n), do: "Status #{n}"

  @doc "Whether a status tag's meaning has been checked in the real game (0 to 3 have; 4 has not been seen)."
  @spec status_checked?(non_neg_integer()) :: boolean()
  def status_checked?(status), do: status in 0..3

  @doc "The global enchantment names in the save's byte order."
  @spec global_names() :: [String.t()]
  def global_names, do: @globals

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
         {:ok, globals} <- globals_changes(params, details),
         {:ok, spells} <- spells(params, details),
         {:ok, research} <- research(params, details),
         {:ok, relations} <- relations_changes(params, details),
         {:ok, name} <- name(params, details) do
      changes =
        nums ++
          if(name != details.name, do: [name: name], else: []) ++
          books ++ retorts ++ globals ++ spells ++ research ++ relations

      {:ok, changes}
    end
  end

  def changes(_params, _details), do: {:ok, []}

  @doc """
  The hero edit form's values (`name`, `level`, `experience`, `damage`) for the hero in `slot` turned into
  `Mirror.SaveFile.Structures.edit_hero/4` changes, keeping only what differs from the save.
  """
  @spec hero_changes(map(), map(), term()) :: {:ok, keyword()} | {:error, atom()}
  def hero_changes(params, details, slot) when is_map(params) do
    case Enum.find(details.heroes, &(&1.slot == slot)) do
      nil -> {:error, :no_such_hero}
      hero -> hero_fields(params, hero)
    end
  end

  def hero_changes(_params, _details, _slot), do: {:ok, []}

  defp hero_fields(params, hero) do
    name = String.trim(to_string(Map.get(params, "name", hero.name)))

    Enum.reduce_while(
      [:level, :experience, :damage],
      {:ok, if(name != hero.name, do: [name: name], else: [])},
      fn field, {:ok, acc} ->
        case number(Map.get(params, Atom.to_string(field))) do
          :skip -> {:cont, {:ok, acc}}
          {:ok, n} when n == :erlang.map_get(field, hero) -> {:cont, {:ok, acc}}
          {:ok, n} -> {:cont, {:ok, acc ++ [{field, n}]}}
          :error -> {:halt, {:error, :"bad_#{field}"}}
        end
      end
    )
  end

  @doc "A short description of a hero edit, for the notice and the undo list."
  @spec hero_label(map(), keyword()) :: String.t()
  def hero_label(hero, changes) do
    "Edited hero #{hero.name}: " <>
      Enum.map_join(changes, ", ", fn {field, v} -> "#{field} #{v}" end)
  end

  @doc """
  Where the item with index `item` is among wizard `details`' places: `{:hero, slot, place}`, `{:vault, place}` or `nil`.
  """
  @spec item_place(map(), non_neg_integer()) :: Mirror.SaveFile.Structures.item_place() | nil
  def item_place(details, item) do
    hero =
      for h <- details.heroes,
          {^item, place} <- Enum.with_index(h.item_places),
          do: {:hero, h.slot, place}

    vault = for {^item, place} <- Enum.with_index(details.vault_places), do: {:vault, place}
    List.first(hero ++ vault)
  end

  @doc """
  The places the item with index `item` could be moved to, as `{value, label}` for a select: the vault (its first
  empty place) and every empty place of a hero whose slot type is the item's own kind. Empty when the item is not
  held by this wizard or nowhere fits. `value` is what `move_request/3` reads.
  """
  @spec item_moves(map(), map()) :: [{String.t(), String.t()}]
  def item_moves(details, item) do
    from = item_place(details, item.index)

    heroes =
      for h <- details.heroes,
          {nil, place} <- Enum.with_index(h.item_places),
          Items.slot_accepts?(Enum.at(h.slot_types, place), item.slot),
          {:hero, h.slot, place} != from,
          do: {"hero:#{h.slot}:#{place}", "#{h.name} (#{slot_kind(item.slot)})"}

    vault =
      case {from, Enum.find_index(details.vault_places, &is_nil/1)} do
        {{:vault, _}, _} -> []
        {_, nil} -> []
        {_, place} -> [{"vault:#{place}", "the vault"}]
      end

    if from, do: vault ++ heroes, else: []
  end

  defp slot_kind(code), do: Items.slot_name(code) || "slot #{code}"

  @doc """
  The move form's destination (`"vault:N"` or `"hero:SLOT:PLACE"`) for the item with index `item`, as
  `{:ok, {from, to}}` for `Structures.move_item/4`, or an error: `:no_such_item` when this wizard does not hold it,
  `:bad_move` for a destination that is not one of the two forms.
  """
  @spec move_request(map(), non_neg_integer(), term()) ::
          {:ok,
           {Mirror.SaveFile.Structures.item_place(), Mirror.SaveFile.Structures.item_place()}}
          | {:error, atom()}
  def move_request(details, item, to) do
    with from when not is_nil(from) <- item_place(details, item),
         {:ok, to} <- parse_place(to) do
      {:ok, {from, to}}
    else
      nil -> {:error, :no_such_item}
      {:error, _} = error -> error
    end
  end

  defp parse_place(value) when is_binary(value) do
    case String.split(value, ":") do
      ["vault", p] ->
        with {p, ""} <- Integer.parse(p), do: {:ok, {:vault, p}}, else: (_ -> {:error, :bad_move})

      ["hero", s, p] ->
        hero_place(s, p)

      _ ->
        {:error, :bad_move}
    end
  end

  defp parse_place(_), do: {:error, :bad_move}

  defp hero_place(s, p) do
    with {s, ""} <- Integer.parse(s), {p, ""} <- Integer.parse(p) do
      {:ok, {:hero, s, p}}
    else
      _ -> {:error, :bad_move}
    end
  end

  # The hero list slots with no hero in them (the game writes -1 as the unit index).
  defp free_hero_slots(raw, record) do
    for slot <- 0..5,
        <<unit::little-signed-16>> <- [
          binary_part(raw, @offset + record * @record + 0x76 + slot * 28, 2)
        ],
        unit < 0,
        do: slot
  end

  # The hero unit types (0 to 34) that have a live unit, whoever owns it: such a hero cannot be added again.
  defp heroes_in_play(raw) do
    case Units.parse(raw) do
      {:ok, units} ->
        units |> Enum.map(& &1.type) |> Enum.filter(&(&1 in 0..34//1)) |> Enum.uniq()

      _ ->
        []
    end
  end

  @doc """
  The heroes that can be added to this wizard, `{type, name}` sorted by name: all 35 minus those in play, and none
  when his hero list has no empty place.
  """
  @spec hero_choices(map()) :: [{non_neg_integer(), String.t()}]
  def hero_choices(%{free_hero_slots: []}), do: []

  def hero_choices(details) do
    0..34
    |> Enum.reject(&(&1 in details.heroes_in_play))
    |> Enum.map(&{&1, UnitTypes.name(&1)})
    |> Enum.sort_by(fn {_type, name} -> String.downcase(name) end)
  end

  @doc """
  The hero add form's choice (`type`, a string) for `details`' first empty hero place, as `{:ok, {slot, type}}`, or an
  error: `:bad_hero_type` for something that is not a hero number, `:hero_in_play`, `:slot_taken` (no empty place).
  """
  @spec hero_add_request(map(), term()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, atom()}
  def hero_add_request(details, type) do
    case parse_int(type) do
      {type, ""} when type in 0..34 ->
        cond do
          details.free_hero_slots == [] -> {:error, :slot_taken}
          type in details.heroes_in_play -> {:error, :hero_in_play}
          true -> {:ok, {hd(details.free_hero_slots), type}}
        end

      _ ->
        {:error, :bad_hero_type}
    end
  end

  defp parse_int(value) when is_binary(value), do: Integer.parse(value)
  defp parse_int(_), do: nil

  @doc "A short description of an added hero, for the notice and the undo list."
  @spec hero_add_label(map(), non_neg_integer()) :: String.t()
  def hero_add_label(details, type),
    do: "Added #{UnitTypes.name(type)} to #{details.name}'s heroes"

  @doc """
  Every place of the wizard's items, in page order: each hero's three (with the hero's name and the place's slot
  type) and the four vault places. `key` is the form's name for the place (`"hero:SLOT:PLACE"` or `"vault:PLACE"`);
  `item` is the item index there or `nil`.
  """
  @spec item_places(map()) :: [map()]
  def item_places(details) do
    heroes =
      for h <- details.heroes, {item, place} <- Enum.with_index(h.item_places) do
        %{
          key: "hero:#{h.slot}:#{place}",
          place: {:hero, h.slot, place},
          hero: h.name,
          slot_type: Enum.at(h.slot_types, place),
          item: item
        }
      end

    vault =
      for {item, place} <- Enum.with_index(details.vault_places) do
        %{key: "vault:#{place}", place: {:vault, place}, hero: nil, slot_type: nil, item: item}
      end

    heroes ++ vault
  end

  @doc """
  The choices for one place's select, `{value, label}`: `"keep"` first (what is there now, or "empty"), then
  `"clear"` for an occupied place, then `"item:N"` for each premade item whose slot code equals a hero place's slot
  type (a vault place takes any), the dearest first and ties alphabetical (Kevin, 2026-10-16). `premade` is
  `Mirror.ItemData.table/0`'s list; names come from the table.
  """
  @spec place_choices(map(), [map()]) :: [{String.t(), String.t()}]
  def place_choices(%{item: item, slot_type: type}, premade) do
    current = {"keep", if(item, do: "(keep what is there)", else: "(empty)")}

    clear = if item, do: [{"clear", "(remove the item)"}], else: []

    items =
      for p <- Enum.sort_by(premade, &{-&1.cost, String.downcase(&1.name)}),
          is_nil(type) or Items.slot_accepts?(type, p.slot),
          do: {"item:#{p.number}", "#{p.name} (#{p.cost} gold)"}

    [current] ++ clear ++ items
  end

  @doc """
  What the place form asks for: `"keep"` (nothing), `"clear"` or `"item:N"` for the premade item number `N`, at the
  place `key`. `{:ok, nil}` for keep, `{:ok, {:clear, place}}`, `{:ok, {:set, place, premade}}`, or an error
  (`:bad_move` for a key or choice that is not one of those, `:no_such_item` for a number not in the table).
  """
  @spec set_request(map(), String.t(), term(), [map()]) ::
          {:ok, nil | {:clear, term()} | {:set, term(), map()}} | {:error, atom()}
  def set_request(details, key, choice, premade) do
    with {:ok, place} <- parse_place(key),
         true <- Enum.any?(item_places(details), &(&1.place == place)) || {:error, :bad_move} do
      case choice do
        "keep" ->
          {:ok, nil}

        "clear" ->
          {:ok, {:clear, place}}

        "item:" <> number ->
          with {number, ""} <- Integer.parse(number),
               %{} = p <- Enum.find(premade, &(&1.number == number)) do
            {:ok, {:set, place, p}}
          else
            _ -> {:error, :no_such_item}
          end

        _ ->
          {:error, :bad_move}
      end
    end
  end

  @doc "A short description of a place edit, for the notice and the undo list."
  @spec set_label(map(), term(), map()) :: String.t()
  def set_label(details, {:clear, place}, _) do
    "Removed #{item_name_at(details, place)} from #{place_owner(details, place)}"
  end

  def set_label(details, {:set, place, premade}, _) do
    "Put #{premade.name} in #{place_owner(details, place)}"
  end

  defp item_name_at(details, place) do
    index =
      case place do
        {:vault, p} ->
          Enum.at(details.vault_places, p)

        {:hero, s, p} ->
          details.heroes
          |> Enum.find(&(&1.slot == s))
          |> then(&(&1 && Enum.at(&1.item_places, p)))
      end

    held = Enum.flat_map(details.heroes, & &1.item_list) ++ details.vault
    Enum.find_value(held, "an item", &(&1.index == index && &1.name))
  end

  defp place_owner(_details, {:vault, _}), do: "the vault"

  defp place_owner(details, {:hero, slot, _}),
    do: Enum.find_value(details.heroes, "a hero", &(&1.slot == slot && &1.name))

  @doc "A short description of an item move, for the notice and the undo list."
  @spec move_label(map(), map(), Mirror.SaveFile.Structures.item_place()) :: String.t()
  def move_label(details, item, to) do
    where =
      case to do
        {:vault, _} ->
          "the vault"

        {:hero, slot, _} ->
          Enum.find_value(details.heroes, "a hero", &(&1.slot == slot && &1.name))
      end

    "Moved #{item.name} to #{where}"
  end

  @doc """
  The item edit form's values (`name`, `cost`, `attack`, `to_hit`, `defense`, `movement` as the screen shows it,
  `resistance`, `spell_skill`, `spell_save`, and `powers` with its `powers_present` marker, a map of power mask to
  `"on"`) turned into `Mirror.SaveFile.Structures.edit_item/3` changes, keeping only what differs from `item` (an
  `Mirror.SaveFile.Items` item). `powers` is `Mirror.ItemPowers.table/0`'s list or `nil`; the special powers are
  ticked boxes, and ability bits no power owns are kept as they are.
  """
  @spec item_changes(map(), map(), [map()] | nil) :: {:ok, keyword()} | {:error, atom()}
  def item_changes(params, item, powers) when is_map(params) do
    with {:ok, name} <- item_name(params, item),
         {:ok, numbers} <- item_numbers(params, item),
         {:ok, movement} <- item_movement(params, item),
         {:ok, abilities} <- item_abilities(params, item, powers) do
      {:ok, name ++ numbers ++ movement ++ abilities}
    end
  end

  def item_changes(_params, _item, _powers), do: {:ok, []}

  defp item_name(params, item) do
    case Map.get(params, "name", item.name) do
      name when is_binary(name) ->
        name = String.trim(name)
        {:ok, if(name != item.name, do: [name: name], else: [])}

      _ ->
        {:error, :bad_item_name}
    end
  end

  defp item_numbers(params, item) do
    fields = [:cost, :attack, :to_hit, :defense, :resistance, :spell_skill, :spell_save]

    Enum.reduce_while(fields, {:ok, []}, fn field, {:ok, acc} ->
      case number(Map.get(params, Atom.to_string(field))) do
        :skip -> {:cont, {:ok, acc}}
        {:ok, n} when n == :erlang.map_get(field, item) -> {:cont, {:ok, acc}}
        {:ok, n} -> {:cont, {:ok, acc ++ [{field, n}]}}
        :error -> {:halt, {:error, if(field == :cost, do: :bad_item_cost, else: :bad_item_stat)}}
      end
    end)
  end

  # The form shows movement as the screen does (4 for the byte 8); the save keeps half points.
  defp item_movement(params, item) do
    case Map.get(params, "movement") do
      nil ->
        {:ok, []}

      "" ->
        {:ok, []}

      value when is_binary(value) ->
        with {shown, ""} <- Float.parse(String.trim(value)),
             half = shown * 2,
             true <- shown >= 0 and half == Float.round(half) do
          half = trunc(half)
          {:ok, if(half == item.movement, do: [], else: [movement: half])}
        else
          _ -> {:error, :bad_item_stat}
        end

      _ ->
        {:error, :bad_item_stat}
    end
  end

  defp item_abilities(%{"powers_present" => _} = params, item, powers) when is_list(powers) do
    case Map.get(params, "powers", %{}) do
      given when is_map(given) ->
        special = for %{mask: mask} <- powers, mask != 0, do: mask
        known = Enum.reduce(special, 0, &Bitwise.bor/2)

        ticked =
          for mask <- special,
              Map.get(given, Integer.to_string(mask)) in ["on", "true"],
              reduce: 0 do
            acc -> Bitwise.bor(acc, mask)
          end

        kept = Bitwise.band(item.abilities, Bitwise.bxor(0xFFFFFFFF, known))
        abilities = Bitwise.bor(kept, ticked)
        {:ok, if(abilities == item.abilities, do: [], else: [abilities: abilities])}

      _ ->
        {:error, :bad_item_abilities}
    end
  end

  defp item_abilities(_params, _item, _powers), do: {:ok, []}

  @doc "A short description of an item edit, for the notice and the undo list."
  @spec item_label(map(), keyword()) :: String.t()
  def item_label(item, changes) do
    parts =
      Enum.map(changes, fn
        {:abilities, _} -> "powers"
        {:movement, half} -> "movement #{MirrorWeb.ItemPanel.movement_shown(half)}"
        {field, v} -> "#{field |> Atom.to_string() |> String.replace("_", " ")} #{v}"
      end)

    "Edited item #{item.name}: #{Enum.join(parts, ", ")}"
  end

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

  # The global-enchantment checkboxes (`globals[N]` = "on"); `globals_present` says the form had them. Time
  # Stop's box is disabled in the form (a disabled box is not sent), so it always keeps the save's value.
  defp globals_changes(%{"globals_present" => _} = params, details) do
    case Map.get(params, "globals", %{}) do
      given when is_map(given) ->
        wanted =
          for {{_name, on}, i} <- Enum.with_index(details.global_flags) do
            if i == @time_stop,
              do: on,
              else: Map.get(given, Integer.to_string(i)) in ["on", "true"]
          end

        current = Enum.map(details.global_flags, &elem(&1, 1))
        {:ok, if(wanted == current, do: [], else: [globals: wanted])}

      _ ->
        {:error, :bad_globals}
    end
  end

  defp globals_changes(_params, _details), do: {:ok, []}

  @doc "The save's byte index of Time Stop, the one global the page does not edit."
  @spec time_stop_index() :: non_neg_integer()
  def time_stop_index, do: @time_stop

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

  # Only a spell the game offers for research (its eight candidates, `+0x34`) can be set: a spell that is not
  # among them is researched and learned, but the game's Research page then shows nothing for it (checked
  # 2026-10-12, STORY-049), so the page does not offer one. The spell already being researched stays allowed.
  defp research(params, details) do
    with {:ok, spell} <-
           optional_change(params, "researching", details.researching_number, :bad_researching),
         :ok <- offered(spell, details),
         {:ok, left} <-
           optional_change(params, "research_left", details.research_left, :bad_research_left) do
      {:ok, Enum.reject([researching: spell, research_left: left], &(elem(&1, 1) == :same))}
    end
  end

  # The Relations rows (`relations[N][relation]` and `relations[N][status]`, N the other wizard's record 0..4;
  # `relations_present` says the form had them). Only fields that differ from the save become changes; the neutral
  # player's row is not editable. The save keeps each pair on both wizards' records and `edit_wizard/3` writes both.
  defp relations_changes(%{"relations_present" => _} = params, details) do
    case Map.get(params, "relations", %{}) do
      given when is_map(given) -> relation_rows(given, details)
      _ -> {:error, :bad_relations}
    end
  end

  defp relations_changes(_params, _details), do: {:ok, []}

  defp relation_rows(given, details) do
    # a banished wizard's row is not editable (the neutral player's never is)
    editable = Enum.filter(details.relations, &(&1.other < 5 and not &1.banished))

    editable
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, acc} ->
      case Map.get(given, Integer.to_string(row.other)) do
        nil -> {:cont, {:ok, acc}}
        fields when is_map(fields) -> relation_row(row, fields, acc)
        _ -> {:halt, {:error, :bad_relations}}
      end
    end)
    |> then(fn
      {:ok, []} -> {:ok, []}
      {:ok, rows} -> {:ok, [relations: rows]}
      error -> error
    end)
  end

  defp relation_row(row, fields, acc) do
    with {:ok, relation} <- relation_value(Map.get(fields, "relation"), row.relation),
         {:ok, status} <- relation_value(Map.get(fields, "status"), row.status) do
      if relation == nil and status == nil,
        do: {:cont, {:ok, acc}},
        else: {:cont, {:ok, acc ++ [{row.other, relation, status}]}}
    else
      _ -> {:halt, {:error, :bad_relations}}
    end
  end

  # `nil` for a value that is not given or equals the saved one, so only changes are written.
  defp relation_value(raw, current) do
    case number(raw) do
      :skip -> {:ok, nil}
      {:ok, ^current} -> {:ok, nil}
      {:ok, n} -> {:ok, n}
      :error -> :error
    end
  end

  defp offered(:same, _details), do: :ok
  defp offered(n, details), do: if(n in details.candidates, do: :ok, else: {:error, :not_offered})

  @doc "The spells the research picker offers: the game's candidates, then the spell being researched if it is not one."
  @spec research_options(map()) :: [pos_integer()]
  def research_options(details) do
    Enum.uniq(
      details.candidates ++
        if(details.researching_number > 0, do: [details.researching_number], else: [])
    )
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
        {:globals, _} -> "global enchantments"
        {:spells, list} -> "#{length(list)} #{if length(list) == 1, do: "spell", else: "spells"}"
        {:researching, 0} -> "no spell researched"
        {:researching, n} -> "researching spell #{n}"
        {:research_left, n} -> "#{n} research points left"
        {:relations, rows} -> "relations with " <> relation_names(details, rows)
      end)

    "Edited #{details.name}: #{Enum.join(parts, ", ")}"
  end

  defp relation_names(details, rows) do
    names = for {other, _, _} <- rows, r <- details.relations, r.other == other, do: r.name
    Enum.join(names, ", ")
  end

  @doc "The words for a refused edit."
  @spec error_message(term()) :: String.t()
  def error_message(:bad_gold), do: "Gold is a whole number from 0 to 30000."
  def error_message(:bad_mana), do: "Mana is a whole number from 0 to 30000."
  def error_message(:bad_fame), do: "Fame is a whole number from 0 to 30000."

  def error_message(:bad_name),
    do: "A name is 1 to 19 letters, digits or punctuation (no accents)."

  def error_message(:bad_books), do: "Books are whole numbers from 0 to 13."

  def error_message(:bad_relations),
    do:
      "A relation is a whole number from -100 to 100, a standing one of None, Pact, Alliance, War."

  def error_message(:not_offered),
    do: "Research can only be set to one of the spells the game offers (its research list)."

  def error_message(:bad_spells), do: "Those spells could not be read."

  def error_message(:bad_researching),
    do: "Researching is a spell number from 1 to 214, or 0 for none."

  def error_message(:bad_research_left),
    do: "Research points left is a whole number from 0 to 65535."

  def error_message(:bad_globals), do: "Those global enchantments could not be read."

  def error_message(:bad_hero_name),
    do: "A hero's name is 1 to 13 letters, digits or punctuation (no accents)."

  def error_message(:bad_item_name),
    do: "An item's name is 1 to 26 letters, digits or punctuation (no accents)."

  def error_message(:bad_item_cost), do: "Cost is a whole number from 0 to 65535."

  def error_message(:bad_item_stat),
    do:
      "Stats stay within what Create Artifact allows: attack 0-6, to hit 0-3, defense 0-6, movement 0-4 (halves allowed), resistance 0-6, spell skill 0-20, spell save 0-4."

  def error_message(:no_item_there), do: "There is no item in that place any more."
  def error_message(:place_taken), do: "That place is already taken; move its item away first."

  def error_message(:wrong_slot),
    do: "A hero carries each kind of item in a place of its own kind."

  def error_message(:same_place), do: "The item is already there."
  def error_message(:slot_taken), do: "His hero list has no empty place."
  def error_message(:hero_in_play), do: "That hero is already in the game."
  def error_message(:bad_hero_type), do: "That is not one of the 35 heroes."

  def error_message(:no_circle),
    do: "He has no summoning circle on the map to stand a new hero on."

  def error_message(:stack_full), do: "Nine units already stand on his summoning circle."
  def error_message(:no_free_unit), do: "The save's unit table is full."
  def error_message(:no_free_item), do: "All 138 item records are in use."
  def error_message(:bad_item_record), do: "That item could not be written."
  def error_message(:bad_move), do: "That is not a place the item can go."
  def error_message(:bad_item_abilities), do: "Those powers could not be read."
  def error_message(:no_such_item), do: "That item is no longer in the save."
  def error_message(:bad_level), do: "Level is a whole number from 0 to 9."
  def error_message(:bad_experience), do: "Experience is a whole number from 0 to 30000."
  def error_message(:bad_damage), do: "Damage is a whole number from 0 to 255."
  def error_message(:no_such_hero), do: "That hero is no longer in the save."
  def error_message(:bad_retorts), do: "Those retorts could not be read."
  def error_message(:no_such_wizard), do: "That wizard is no longer in the save."
  def error_message(:nothing_changed), do: "Nothing to change."
  def error_message(_other), do: "The wizard could not be changed."
end
