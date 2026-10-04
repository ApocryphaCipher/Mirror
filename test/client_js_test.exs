defmodule Mirror.ClientJsTest do
  @moduledoc """
  Runs the client's plain-JavaScript unit tests (`assets/test/*.test.mjs`, Node's
  built-in test runner) as part of `mix test`. Skipped where `node` is not installed.

  These cover pure helpers only; the hooks themselves need a browser DOM and are
  not tested here.
  """
  use ExUnit.Case, async: true

  @node System.find_executable("node")

  @tag skip: is_nil(@node) && "needs node"
  test "client unit tests pass" do
    files = Path.wildcard("assets/test/*.test.mjs")
    assert files != []

    {output, status} = System.cmd(@node, ["--test" | files], stderr_to_stdout: true)
    assert status == 0, output
  end

  test "both tile-delta handlers use the layer-type helper" do
    source = File.read!("assets/js/map_hooks.js")

    assert source =~ ~s|from "./layer_type.mjs"|
    # one call in the engine_delta handler, one in the tile_updates handler
    assert length(Regex.scan(~r/layerTypeAfterDelta\(/, source)) == 2
    refute source =~ "if (payload.layer_type) this.layerType = payload.layer_type"
  end
end
