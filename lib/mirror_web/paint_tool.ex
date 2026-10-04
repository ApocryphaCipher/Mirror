defmodule MirrorWeb.PaintTool do
  @moduledoc """
  The pure parts of the "Paint type" edit tool (STORY-017): the options the toolbar
  offers, parsing what the form sends back, the eyedropper mapping, and the
  plain-language summary of what a paint did and did not do. The page itself
  (`MirrorWeb.MapLive`) only wires these to events.
  """

  alias Mirror.TerrainPaint

  @kinds [
    water: "Water (ocean)",
    grass: "Grassland",
    forest: "Forest",
    hill: "Hills",
    mountain: "Mountains",
    desert: "Desert",
    swamp: "Swamp",
    tundra: "Tundra"
  ]

  @sizes [{1, "1 × 1"}, {3, "3 × 3"}, {5, "5 × 5"}]

  # A plain tile per terrain for the raw tile painter's quick pick: the tile the
  # game itself uses for plain grass (162), the resolver's pick for the rest
  # (docs/reference/classic-terrain-format.md).
  @quick_tiles [
    {"Ocean", 0},
    {"Grassland", 162},
    {"Forest", 163},
    {"Hills", 277},
    {"Mountains", 261},
    {"Desert", 165},
    {"Swamp", 166},
    {"Tundra", 167}
  ]

  @default_kind :grass
  @default_size 1

  def default_kind, do: @default_kind
  def default_size, do: @default_size

  @doc "`{label, value}` pairs for the terrain dropdown (values are strings)."
  def kind_options, do: for({kind, label} <- @kinds, do: {label, Atom.to_string(kind)})

  @doc "`{label, value}` pairs for the brush size dropdown."
  def size_options, do: for({size, label} <- @sizes, do: {label, Integer.to_string(size)})

  @doc "`{label, tile number}` pairs for the raw painter's quick pick."
  def quick_tile_options, do: @quick_tiles

  @doc "The label for a kind, e.g. `:hill` -> \"Hills\"."
  def kind_label(kind), do: Keyword.fetch!(@kinds, kind)

  @doc "A kind from the form's string, or `nil` if it is not a paintable kind."
  def parse_kind(value) when is_binary(value) do
    Enum.find(TerrainPaint.kinds(), &(Atom.to_string(&1) == value))
  end

  def parse_kind(_), do: nil

  @doc "A brush size from the form's string; anything but 1, 3 or 5 gives `default`."
  def parse_size(value, default \\ @default_size) do
    with true <- is_binary(value),
         {size, ""} <- Integer.parse(value),
         true <- size in Enum.map(@sizes, &elem(&1, 0)) do
      size
    else
      _ -> default
    end
  end

  @doc "A checkbox value from the form (`\"true\"`, `\"on\"`) as a boolean."
  def parse_flag(value), do: value in [true, "true", "on", "1"]

  @doc """
  The paintable kind of a terrain type, for the eyedropper: open water is `:water`,
  a plain land type is itself, and rivers, lakes, nodes and volcanoes give `nil`
  (they cannot be painted).
  """
  def kind_of_type(type) when type in [:ocean, :shore], do: :water
  def kind_of_type(type), do: if(type in TerrainPaint.kinds(), do: type)

  @doc """
  A one-line summary of a paint for the toolbar: `{level, text}` where `level` is
  `:ok` or `:warn`. `report` has the sets of `skipped`, `unresolved` and `stale`
  cells; `changed` is how many terrain tiles changed and `landmass` how many
  landmass IDs.

  The landmass layer is normally touched only around the painted cells. If a paint
  had to fix many more IDs than it changed tiles, the save's landmass layer was out
  of step with its terrain (an earlier raw edit, say) and the summary says so.
  """
  def summary(report, changed, landmass \\ 0) do
    warnings =
      [
        {Enum.count(report.skipped), "left alone (river, lake, node, volcano or polar row)"},
        {Enum.count(report.unresolved),
         "left as they were: no tile fits that shape of coastline"},
        {Enum.count(report.stale), "neighbouring tiles may not match; try a different shape"}
      ]
      |> Enum.filter(fn {n, _} -> n > 0 end)
      |> Enum.map(fn {n, text} -> "#{n} #{text}" end)

    warnings =
      if landmass > changed,
        do:
          warnings ++
            ["landmass layer repaired on #{landmass} tiles (it was out of step with the terrain)"],
        else: warnings

    base = "#{changed} #{if changed == 1, do: "tile", else: "tiles"} changed"

    case warnings do
      [] -> {:ok, base}
      _ -> {:warn, Enum.join([base | warnings], " · ")}
    end
  end
end
