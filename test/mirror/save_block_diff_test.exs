defmodule Mirror.SaveBlockDiffTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveBlockDiff

  test "empty binaries diff to an empty map instead of raising" do
    assert SaveBlockDiff.diff(<<>>, <<>>) == %{}
  end

  test "identical binaries diff to an empty map" do
    assert SaveBlockDiff.diff(<<1, 2, 3>>, <<1, 2, 3>>) == %{}
  end

  test "a byte outside every named block is reported under :other" do
    size = 123_300
    before_binary = :binary.copy(<<0>>, size)
    # Byte 0 sits before the first named block (cities_count at 0x9E0), so it's unaccounted.
    after_binary = <<1, :binary.part(before_binary, 1, size - 1)::binary>>

    assert SaveBlockDiff.diff(before_binary, after_binary) == %{other: [0]}
  end
end
