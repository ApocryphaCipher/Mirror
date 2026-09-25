defmodule MirrorWeb.MapOverlayLayersTest do
  @moduledoc """
  The overlay-layer markup map_overlays.js depends on (STORY-009). Needs no
  game files: the map page renders before a save is loaded.
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{
      conn:
        init_test_session(conn, %{
          "mirror_session_id" => "overlay-test-#{System.unique_integer()}"
        })
    }
  end

  for path <- ["/arcanus", "/myrror"] do
    test "#{path} stacks an overlay canvas over the terrain inside the pan/zoom stage",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))

      assert has_element?(view, "[data-map-stage] #map-canvas")
      assert has_element?(view, "[data-map-stage] canvas#map-overlays[phx-hook=MapOverlays]")
    end
  end

  test "the Layers panel lists every overlay, top layer first; fog and settleable start off",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/arcanus")

    toggles =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-overlay-panel] input[data-overlay-toggle][data-for=map-overlays]")

    assert LazyHTML.attribute(toggles, "value") ==
             ~w(fog units cities sites auras roads settleable)

    checked =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-overlay-panel] input[data-overlay-toggle][checked]")

    assert LazyHTML.attribute(checked, "value") == ~w(units cities sites auras roads)
  end
end
