defmodule Mirror.Quality.SmoothingRulesTest do
  use ExUnit.Case, async: true

  alias Mirror.Quality.SmoothingRules

  test "reduce_mask/2 fills in a corner between two adjacent land cardinals (SS161)" do
    # N=1(land), NE=0, E=1(land), rest water — the real rule "if two
    # adjacent edges are land, the corner between them must also be land"
    # should set NE to land too.
    assert SmoothingRules.reduce_mask("10100000", "SS161") == "11100000"
  end

  test "reduce_mask/2 leaves an already-consistent mask unchanged" do
    assert SmoothingRules.reduce_mask("11100000", "SS161") == "11100000"
    assert SmoothingRules.reduce_mask("00000000", "SS161") == "00000000"
  end

  test "reduce_mask/2 never produces a ternary digit from binary input" do
    for n <- 0..255 do
      raw =
        for bit <- 7..0//-1, into: "" do
          if Bitwise.band(n, Bitwise.bsl(1, bit)) != 0, do: "1", else: "0"
        end

      reduced = SmoothingRules.reduce_mask(raw, "SS161EX")
      assert reduced =~ ~r/^[01]{8}$/, "expected binary-only output for #{raw}, got #{reduced}"
    end
  end

  test "build_lookup/1 covers all 256 binary combinations" do
    lookup = SmoothingRules.build_lookup("SS161")
    assert map_size(lookup) == 256
  end

  test "build_lookup/1 for SS161EX collapses to exactly 161 distinct outputs" do
    # Matches the smoothing system's own name/design ("161 tile set,
    # extended") — strong independent check that the port is faithful to
    # the real ruleset.
    distinct =
      "SS161EX"
      |> SmoothingRules.build_lookup()
      |> Map.values()
      |> Enum.uniq()
      |> length()

    assert distinct == 161
  end

  test "max_value/1 reports binary systems as 1 and shore's as ternary (2)" do
    assert SmoothingRules.max_value("SS16") == 1
    assert SmoothingRules.max_value("SS161") == 1
    assert SmoothingRules.max_value("SS161EX") == 2
  end
end
