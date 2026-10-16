defmodule MirrorWeb.ToastTest do
  use ExUnit.Case, async: true

  alias MirrorWeb.Toast

  defp pushed(socket), do: socket.private.live_temp.push_events |> Enum.reverse()

  test "a toast is a push event with its kind and text" do
    socket = Toast.push(%Phoenix.LiveView.Socket{}, :error, "Mana is a whole number")
    assert pushed(socket) == [["toast", %{kind: "error", text: "Mana is a whole number"}]]
  end

  test "an Undo button is asked for with action: :undo, and only then" do
    plain = Toast.push(%Phoenix.LiveView.Socket{}, :ok, "Saved")
    refute Map.has_key?(hd(pushed(plain)) |> List.last(), :action)

    undo = Toast.push(%Phoenix.LiveView.Socket{}, :ok, "Edited", action: :undo)
    assert [["toast", %{kind: "ok", text: "Edited", action: "undo"}]] = pushed(undo)
  end

  test "toasts keep the order they were pushed in" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Toast.push(:info, "one")
      |> Toast.push(:ok, "two")

    assert Enum.map(pushed(socket), fn ["toast", p] -> p.text end) == ["one", "two"]
  end

  test "only the three kinds and a string are accepted" do
    socket = %Phoenix.LiveView.Socket{}
    # through apply/3: the compiler would (rightly) warn about a call it can see cannot match
    assert_raise FunctionClauseError, fn -> apply(Toast, :push, [socket, :warn, "x"]) end
    assert_raise FunctionClauseError, fn -> apply(Toast, :push, [socket, :ok, :atom]) end
  end
end
