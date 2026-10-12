defmodule Mirror.SaveFile.UnitMovement do
  @moduledoc """
  Which units may stand on water (STORY-029's edit checker needs this).

  A unit is **not** only a land unit if its type flies, swims or sails, if it is
  non-corporeal, or if an enchantment on the unit says so. The rule is
  kazzmir's (`units/overworld.go`: `IsFlying`, `IsSwimmer`, `IsSailing`,
  `IsLandWalker`), and the type table is kazzmir's `getUnitType` switch with the
  `Flying`, `Swimming`, `Sailing` and `NonCorporeal` flags of each unit
  definition (docs/reference/unit-movement.md has the table, its sources and what
  was checked). It does not look at a transport: a land unit riding a boat is
  fine, and that needs the stack, not the unit.

  The type is the unit record's `+5` byte; the enchantments are the record's `+24`
  u32 (see `Mirror.SaveFile.Units`).
  """

  import Bitwise

  # Unit-enchantment bits (u32 at +24 of the unit record), from kazzmir's
  # convert.go: Water Walking 0x100, Wind Walking 0x10000, Flight 0x20000.
  @water_walking 0x100
  @wind_walking 0x10000
  @flight 0x20000

  @flying MapSet.new([
            17,
            55,
            65,
            66,
            67,
            68,
            69,
            70,
            71,
            73,
            74,
            75,
            103,
            136,
            146,
            156,
            159,
            160,
            161,
            162,
            164,
            169,
            170,
            171,
            172,
            173,
            177,
            178,
            180,
            181,
            186,
            194,
            195,
            196
          ])
  @swimming MapSet.new([35, 36, 38, 120, 121, 122, 123, 124, 125, 126, 154, 176, 190])
  @sailing MapSet.new([35, 36, 38])
  @non_corporeal MapSet.new([154, 170, 171, 176, 191, 192])

  @doc "True when the unit type flies by nature."
  def flies?(type), do: MapSet.member?(@flying, type)

  @doc "True for types that swim: they can also be on land (lizardmen, spirits)."
  def swims?(type), do: MapSet.member?(@swimming, type)

  @doc "True for boats, which can only be on water."
  def sails?(type), do: MapSet.member?(@sailing, type)

  @doc "True for non-corporeal types (spirits, wraiths, phantoms)."
  def non_corporeal?(type), do: MapSet.member?(@non_corporeal, type)

  # Mutation bit 8 (record `+23`): Chaos Channels demon wings, which make a unit fly (kazzmir's
  # `IsFlying`).
  @demon_wings 8

  @doc """
  True when a unit of `type` carrying the `enchantments` bits (and, if given, the `mutations`
  byte) may stand on water without help from a boat. Demon wings (mutation bit 8) fly.

  Wind Walking is counted as allowing it: kazzmir has the enchantment bit but
  `IsLandWalker` does not look at it. *Guess*, so a checker should treat it as fine.
  """
  @spec can_be_on_water?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  def can_be_on_water?(type, enchantments \\ 0, mutations \\ 0) do
    flies?(type) or swims?(type) or sails?(type) or non_corporeal?(type) or
      (enchantments &&& (@water_walking ||| @wind_walking ||| @flight)) != 0 or
      (mutations &&& @demon_wings) != 0
  end

  @doc "The unit types that fly, swim, sail or are non-corporeal, as a sorted list."
  def water_capable_types do
    @flying
    |> MapSet.union(@swimming)
    |> MapSet.union(@sailing)
    |> MapSet.union(@non_corporeal)
    |> Enum.sort()
  end
end
