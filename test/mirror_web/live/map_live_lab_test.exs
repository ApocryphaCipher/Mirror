defmodule MirrorWeb.MapLiveLabTest do
  @moduledoc """
  Tests for Lab view interaction mode (STORY-039).
  """
  use MirrorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "lab does not receive edit_mode event on mount (STORY-039)", %{conn: conn} do
    conn =
      init_test_session(conn, %{"mirror_session_id" => "lab-test-#{System.unique_integer()}"})

    {:ok, view, _html} = live(conn, ~p"/lab/arcanus")

    refute_push_event(view, "edit_mode", %{})
  end

  test "regular map view receives edit_mode: view on mount", %{conn: conn} do
    conn =
      init_test_session(conn, %{"mirror_session_id" => "view-test-#{System.unique_integer()}"})

    {:ok, view, _html} = live(conn, ~p"/arcanus")

    assert_push_event(view, "edit_mode", %{mode: "view"})
  end
end
