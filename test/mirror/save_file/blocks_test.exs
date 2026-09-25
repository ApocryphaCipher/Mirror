defmodule Mirror.SaveFile.BlocksTest do
  use ExUnit.Case, async: true

  alias Mirror.SaveFile.Blocks

  test "writing a plane into a too-short save is an error, not a crash (STORY-040)" do
    slice = :binary.copy(<<0>>, Blocks.layer_size(:terrain))
    assert Blocks.put_plane_slice(<<>>, :terrain, 0, slice) == {:error, {:short_binary, :terrain}}
  end
end
