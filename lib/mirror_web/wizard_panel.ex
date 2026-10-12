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
        researching: spell(researching),
        research_left: research_left,
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
end
