defmodule Mirror.SaveFile.UnitTypes do
  @moduledoc """
  The 198 unit types of a save (a unit record's `+5` byte, 0 to 197) with their names and races.

  From kazzmir's `getUnitType` switch (`load/convert.go`) and each unit definition's `Name` and
  `Race` (`units/unit.go`), read 2026-10-11. **Type 131 (Nomad Magicians) is a guess**: kazzmir has
  no definition for it (the `case` is commented out), but the id falls where the Nomad
  Magicians belong in the game's order. Names are checked in the game only for a few types
  (Sky Drake 196 on Kevin's screen, the Lizardman units 120 and 121, Halfling 90); the order of
  the whole table is the game's own, since kazzmir's reads real saves.

  kazzmir's spellings were corrected where they are plainly typos ("Calvary", "ElvenLord",
  "WereWolves"). `display_name/1` puts the race in front of the plain names that several races share
  ("Barbarian Spearmen"); heroes, fantastic creatures and the boats and catapult keep their own.
  """

  @types %{
    0 => {"Brax", :hero},
    1 => {"Gunther", :hero},
    2 => {"Zaldron", :hero},
    3 => {"B'Shan", :hero},
    4 => {"Rakir", :hero},
    5 => {"Valana", :hero},
    6 => {"Bahgtru", :hero},
    7 => {"Serena", :hero},
    8 => {"Shuri", :hero},
    9 => {"Theria", :hero},
    10 => {"Greyfairer", :hero},
    11 => {"Taki", :hero},
    12 => {"Reywind", :hero},
    13 => {"Malleus", :hero},
    14 => {"Tumu", :hero},
    15 => {"Jaer", :hero},
    16 => {"Marcus", :hero},
    17 => {"Fang", :hero},
    18 => {"Morgana", :hero},
    19 => {"Aureus", :hero},
    20 => {"Shin Bo", :hero},
    21 => {"Spyder", :hero},
    22 => {"Shalla", :hero},
    23 => {"Yramrag", :hero},
    24 => {"Mystic X", :hero},
    25 => {"Aerie", :hero},
    26 => {"Deth Stryke", :hero},
    27 => {"Elana", :hero},
    28 => {"Roland", :hero},
    29 => {"Mortu", :hero},
    30 => {"Alorra", :hero},
    31 => {"Sir Harold", :hero},
    32 => {"Ravashack", :hero},
    33 => {"Warrax", :hero},
    34 => {"Torin", :hero},
    35 => {"Trireme", :all},
    36 => {"Galley", :all},
    37 => {"Catapult", :all},
    38 => {"Warship", :all},
    39 => {"Spearmen", :barbarian},
    40 => {"Swordsmen", :barbarian},
    41 => {"Bowmen", :barbarian},
    42 => {"Cavalry", :barbarian},
    43 => {"Shaman", :barbarian},
    44 => {"Settlers", :barbarian},
    45 => {"Berserkers", :barbarian},
    46 => {"Spearmen", :beastmen},
    47 => {"Swordsmen", :beastmen},
    48 => {"Halberdiers", :beastmen},
    49 => {"Bowmen", :beastmen},
    50 => {"Priests", :beastmen},
    51 => {"Magicians", :beastmen},
    52 => {"Engineers", :beastmen},
    53 => {"Settlers", :beastmen},
    54 => {"Centaurs", :beastmen},
    55 => {"Manticores", :beastmen},
    56 => {"Minotaurs", :beastmen},
    57 => {"Spearmen", :dark_elf},
    58 => {"Swordsmen", :dark_elf},
    59 => {"Halberdiers", :dark_elf},
    60 => {"Cavalry", :dark_elf},
    61 => {"Priests", :dark_elf},
    62 => {"Settlers", :dark_elf},
    63 => {"Nightblades", :dark_elf},
    64 => {"Warlocks", :dark_elf},
    65 => {"Nightmares", :dark_elf},
    66 => {"Spearmen", :draconian},
    67 => {"Swordsmen", :draconian},
    68 => {"Halberdiers", :draconian},
    69 => {"Bowmen", :draconian},
    70 => {"Shaman", :draconian},
    71 => {"Magicians", :draconian},
    72 => {"Engineers", :draconian},
    73 => {"Settlers", :draconian},
    74 => {"Doom Drake", :draconian},
    75 => {"Air Ship", :draconian},
    76 => {"Swordsmen", :dwarf},
    77 => {"Halberdiers", :dwarf},
    78 => {"Engineers", :dwarf},
    79 => {"Hammerhands", :dwarf},
    80 => {"Steam Cannon", :dwarf},
    81 => {"Golem", :dwarf},
    82 => {"Settlers", :dwarf},
    83 => {"Spearmen", :gnoll},
    84 => {"Swordsmen", :gnoll},
    85 => {"Halberdiers", :gnoll},
    86 => {"Bowmen", :gnoll},
    87 => {"Settlers", :gnoll},
    88 => {"Wolf Riders", :gnoll},
    89 => {"Spearmen", :halfling},
    90 => {"Swordsmen", :halfling},
    91 => {"Bowmen", :halfling},
    92 => {"Shamans", :halfling},
    93 => {"Settlers", :halfling},
    94 => {"Slingers", :halfling},
    95 => {"Spearmen", :high_elf},
    96 => {"Swordsmen", :high_elf},
    97 => {"Halberdiers", :high_elf},
    98 => {"Cavalry", :high_elf},
    99 => {"Magicians", :high_elf},
    100 => {"Settlers", :high_elf},
    101 => {"Longbowmen", :high_elf},
    102 => {"Elven Lord", :high_elf},
    103 => {"Pegasai", :high_elf},
    104 => {"Spearmen", :high_men},
    105 => {"Swordsmen", :high_men},
    106 => {"Bowmen", :high_men},
    107 => {"Cavalry", :high_men},
    108 => {"Priests", :high_men},
    109 => {"Magicians", :high_men},
    110 => {"Engineers", :high_men},
    111 => {"Settlers", :high_men},
    112 => {"Pikemen", :high_men},
    113 => {"Paladins", :high_men},
    114 => {"Spearmen", :klackon},
    115 => {"Swordsmen", :klackon},
    116 => {"Halberdiers", :klackon},
    117 => {"Engineers", :klackon},
    118 => {"Settlers", :klackon},
    119 => {"Stag Beetle", :klackon},
    120 => {"Spearmen", :lizardman},
    121 => {"Swordsmen", :lizardman},
    122 => {"Halberdiers", :lizardman},
    123 => {"Javelineers", :lizardman},
    124 => {"Shamans", :lizardman},
    125 => {"Settlers", :lizardman},
    126 => {"Dragon Turtle", :lizardman},
    127 => {"Spearmen", :nomad},
    128 => {"Swordsmen", :nomad},
    129 => {"Bowmen", :nomad},
    130 => {"Priests", :nomad},
    131 => {"Magicians", :nomad},
    132 => {"Settlers", :nomad},
    133 => {"Horsebowmen", :nomad},
    134 => {"Pikemen", :nomad},
    135 => {"Rangers", :nomad},
    136 => {"Griffins", :nomad},
    137 => {"Spearmen", :orc},
    138 => {"Swordsmen", :orc},
    139 => {"Halberdiers", :orc},
    140 => {"Bowmen", :orc},
    141 => {"Cavalry", :orc},
    142 => {"Shamans", :orc},
    143 => {"Magicians", :orc},
    144 => {"Engineers", :orc},
    145 => {"Settlers", :orc},
    146 => {"Wyvern Riders", :orc},
    147 => {"Spearmen", :troll},
    148 => {"Swordsmen", :troll},
    149 => {"Halberdiers", :troll},
    150 => {"Shamans", :troll},
    151 => {"Settlers", :troll},
    152 => {"War Trolls", :troll},
    153 => {"War Mammoths", :troll},
    154 => {"Magic Spirit", :fantastic},
    155 => {"Hell Hounds", :fantastic},
    156 => {"Gargoyles", :fantastic},
    157 => {"Fire Giant", :fantastic},
    158 => {"Fire Elemental", :fantastic},
    159 => {"Chaos Spawn", :fantastic},
    160 => {"Chimeras", :fantastic},
    161 => {"Doom Bat", :fantastic},
    162 => {"Efreet", :fantastic},
    163 => {"Hydra", :fantastic},
    164 => {"Great Drake", :fantastic},
    165 => {"Skeletons", :fantastic},
    166 => {"Ghouls", :fantastic},
    167 => {"Night Stalker", :fantastic},
    168 => {"Werewolves", :fantastic},
    169 => {"Demon", :fantastic},
    170 => {"Wraiths", :fantastic},
    171 => {"Shadow Demons", :fantastic},
    172 => {"Death Knights", :fantastic},
    173 => {"Demon Lord", :fantastic},
    174 => {"Zombies", :fantastic},
    175 => {"Unicorns", :fantastic},
    176 => {"Guardian Spirit", :fantastic},
    177 => {"Angel", :fantastic},
    178 => {"Arch Angel", :fantastic},
    179 => {"War Bears", :fantastic},
    180 => {"Sprites", :fantastic},
    181 => {"Cockatrices", :fantastic},
    182 => {"Basilisk", :fantastic},
    183 => {"Giant Spiders", :fantastic},
    184 => {"Stone Giant", :fantastic},
    185 => {"Colossus", :fantastic},
    186 => {"Gorgons", :fantastic},
    187 => {"Earth Elemental", :fantastic},
    188 => {"Behemoth", :fantastic},
    189 => {"Great Wyrm", :fantastic},
    190 => {"Floating Island", :fantastic},
    191 => {"Phantom Beast", :fantastic},
    192 => {"Phantom Warriors", :fantastic},
    193 => {"Storm Giant", :fantastic},
    194 => {"Air Elemental", :fantastic},
    195 => {"Djinn", :fantastic},
    196 => {"Sky Drake", :fantastic},
    197 => {"Nagas", :fantastic}
  }

  @race_titles %{
    barbarian: "Barbarian",
    beastmen: "Beastmen",
    dark_elf: "Dark Elf",
    draconian: "Draconian",
    dwarf: "Dwarf",
    gnoll: "Gnoll",
    halfling: "Halfling",
    high_elf: "High Elf",
    high_men: "High Men",
    klackon: "Klackon",
    lizardman: "Lizardman",
    nomad: "Nomad",
    orc: "Orc",
    troll: "Troll"
  }

  @doc "The unit type's plain name, or `\"unit N\"` outside 0..197."
  @spec name(integer()) :: String.t()
  def name(type) do
    case Map.fetch(@types, type) do
      {:ok, {name, _race}} -> name
      :error -> "unit #{type}"
    end
  end

  @doc "The race atom (one of the 14, or `:hero`, `:fantastic`, `:all`), or `nil`."
  @spec race(integer()) :: atom() | nil
  def race(type) do
    case Map.fetch(@types, type) do
      {:ok, {_name, race}} -> race
      :error -> nil
    end
  end

  @doc "The name with the race in front when the plain name is shared between races."
  @spec display_name(integer()) :: String.t()
  def display_name(type) do
    case Map.fetch(@types, type) do
      {:ok, {name, race}} ->
        case Map.fetch(@race_titles, race) do
          {:ok, title} -> title <> " " <> name
          :error -> name
        end

      :error ->
        "unit #{type}"
    end
  end

  @doc "How many unit types the table has."
  def count, do: map_size(@types)
end
