defmodule Mirror.StatsTest do
  use ExUnit.Case, async: true

  alias Mirror.Stats

  describe "format_key/1 (STORY-040)" do
    test "tuple keys become colon-joined strings, nested tuples included" do
      assert Stats.format_key({:hist, {:mom_classic, "a"}, :terrain, 5}) ==
               "hist:mom_classic:a:terrain:5"
    end

    test "formatted keys can be encoded as JSON" do
      assert {:ok, _} = Jason.encode(%{Stats.format_key({:meta, {:mom_classic, "x"}}) => 1})
    end
  end
end
