defmodule MirrorWeb.RoadTool do
  @moduledoc """
  The pure parts of the roads-and-specials edit tools (STORY-018): what a click
  does to a tile's `terrain_flags` byte (road, enchanted road, corruption) and
  `minerals` byte (specials), and the dropdown of specials. The page itself
  (`MirrorWeb.MapLive`) only wires these to pointer events.

  Bits and values are in `docs/reference/kazzmir-save-layouts.md`. Every function
  keeps the bits it does not own: a road click leaves corruption alone, and the
  other way round.
  """

  import Bitwise

  @road 0x08
  @enchanted 0x10
  @corruption 0x20

  # An enchanted road keeps the plain road bit too, as the game's Enchant Road
  # spell does on top of an existing road. `Mirror.SaveFile.Roads` reads either.
  @road_bits @road ||| @enchanted

  @specials [
    {"Iron ore", 1},
    {"Coal", 2},
    {"Silver ore", 3},
    {"Gold ore", 4},
    {"Gems", 5},
    {"Mithril ore", 6},
    {"Adamantium ore", 7},
    {"Quork crystals", 8},
    {"Crysx crystals", 9},
    {"Wild game", 64},
    {"Nightshade", 128}
  ]

  @default_special 4

  def default_special, do: @default_special

  @doc "`{label, value}` pairs for the special dropdown (values are strings)."
  def special_options, do: for({label, value} <- @specials, do: {label, Integer.to_string(value)})

  @doc "A special's minerals byte from the form's string, or `nil` if it is not one we paint."
  def parse_special(value) when is_binary(value) do
    with {n, ""} <- Integer.parse(value),
         true <- Enum.any?(@specials, &(elem(&1, 1) == n)) do
      n
    else
      _ -> nil
    end
  end

  def parse_special(_), do: nil

  @doc "The label for a minerals byte, `\"nothing\"` for 0 or a value we do not paint."
  def special_label(value) do
    case Enum.find(@specials, &(elem(&1, 1) == value)) do
      {label, _} -> label
      nil -> "nothing"
    end
  end

  @doc """
  The next flags byte when a tile is clicked with the Road tool: no road, then a
  road, then an enchanted road, then none again. `back` steps the other way.
  Corruption and any other bits are kept.
  """
  def cycle_road(flags, back? \\ false) do
    rest = flags &&& bnot(@road_bits)

    case {road_state(flags), back?} do
      {:none, false} -> rest ||| @road
      {:road, false} -> rest ||| @road_bits
      {:enchanted, false} -> rest
      {:none, true} -> rest ||| @road_bits
      {:road, true} -> rest
      {:enchanted, true} -> rest ||| @road
    end
  end

  @doc "`:none`, `:road` or `:enchanted` for a flags byte."
  def road_state(flags) do
    cond do
      (flags &&& @enchanted) != 0 -> :enchanted
      (flags &&& @road) != 0 -> :road
      true -> :none
    end
  end

  @doc "The flags byte with corruption switched on or off."
  def set_corruption(flags, true), do: flags ||| @corruption
  def set_corruption(flags, false), do: flags &&& bnot(@corruption)

  @doc "The flags byte with corruption flipped."
  def toggle_corruption(flags), do: set_corruption(flags, (flags &&& @corruption) == 0)

  @doc """
  A short, plain-language description of what a click did, for the status line.
  `what` is `:road`, `:corruption` or `:special`; `before` and `after` are the
  bytes of the layer the tool edits.
  """
  def describe(:road, _before, after_flags) do
    case road_state(after_flags) do
      :none -> "Road removed"
      :road -> "Road"
      :enchanted -> "Enchanted road"
    end
  end

  def describe(:corruption, _before, after_flags) do
    if (after_flags &&& @corruption) != 0, do: "Corrupted", else: "Corruption removed"
  end

  def describe(:special, _before, 0), do: "Special removed"
  def describe(:special, _before, value), do: special_label(value)
end
