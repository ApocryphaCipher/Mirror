defmodule Mirror.SaveFile.HeroTypes do
  @moduledoc """
  The 35 hero unit types (0 to 34, `Mirror.SaveFile.UnitTypes`) and the three equipment places each has (STORY-053).

  A hero's list entry holds one **slot type** per place (`Mirror.SaveFile.Heroes`): 1 melee weapon, 2 bow, 3 any weapon,
  4 staff or wand, 5 armor, 6 jewelry. Observed in SAVE2: Sir Harold and Bahgtru (1, 5, 6), Warrax (3, 5, 6). The rest
  come from kazzmir's `GetArtifactSlots`, matched to the save's hero numbers by name:

    * fighters (1, 5, 6): the heroes not listed below
    * mages (4, 6, 6): Zaldron, Greyfairer, Malleus, Jaer, Morgana, Yramrag, Aerie, Elana, Ravashack
    * archers (2, 5, 6): B'Shan, Shuri, Marcus, Alorra
    * any weapon (3, 5, 6): Reywind, Mystic X, Warrax
  """

  @mages [2, 10, 13, 15, 18, 23, 25, 27, 32]
  @archers [3, 8, 16, 30]
  @any_weapon [12, 24, 33]

  @doc "The hero types, 0 to 34."
  @spec all() :: [0..34]
  def all, do: Enum.to_list(0..34)

  @doc "The three slot types of hero type `type`, in the order of the list entry's places."
  @spec slot_types(0..34) :: [pos_integer()]
  def slot_types(type) when type in @mages, do: [4, 6, 6]
  def slot_types(type) when type in @archers, do: [2, 5, 6]
  def slot_types(type) when type in @any_weapon, do: [3, 5, 6]
  def slot_types(type) when type in 0..34//1, do: [1, 5, 6]
end
