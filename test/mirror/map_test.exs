defmodule Mirror.MapTest do
  use ExUnit.Case, async: true

  alias Mirror.Map

  test "wrap_x/1 normalizes any integer into map bounds" do
    width = Map.width()

    assert Map.wrap_x(-1) == width - 1
    assert Map.wrap_x(width) == 0
    assert Map.wrap_x(width + 5) == 5
    assert Map.wrap_x(-(width * 1000 + 1)) == width - 1
  end
end
