defmodule Mirror.Engine.FogTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Mirror.Engine.Fog

  describe "bitsets for tile counts not divisible by 8 (STORY-040)" do
    test "a 9-tile map's last bit can be set" do
      bitset = Fog.set_bit(Fog.empty_bitset(9), 8, 1)
      assert (:binary.at(bitset, 1) &&& 1) == 1
    end

    test "an unpadded bitset is padded, not refused" do
      assert Fog.normalize_bitset(<<0::size(9)>>, 9) == <<0, 0>>
    end
  end
end
