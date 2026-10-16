defmodule MirrorWeb.ToastHelpers do
  @moduledoc """
  Reading the toasts a LiveView pushed (`MirrorWeb.Toast`, STORY-062) in a LiveView test.

  A toast is a `"toast"` push event, which `Phoenix.LiveViewTest` leaves in the test process's mailbox. The
  helpers look at the mailbox without taking anything out, so a test can assert on the same toast twice; use
  `flush_toasts/1` to start from none. (`assert_push_event/3` with a variable event name matches any event, and
  returns only the first match: see AGENTS.md section 10. These look at all of them.)
  """
  import ExUnit.Assertions

  @doc "Every toast pushed to `view` and not flushed, oldest first, as `%{kind: \"ok\" | \"info\" | \"error\", text: ...}`."
  def toasts(%{proxy: {ref, _topic, _pid}}) do
    {:messages, messages} = Process.info(self(), :messages)
    for {^ref, {:push_event, "toast", payload}} <- messages, do: payload
  end

  @doc "Forget the toasts so far."
  def flush_toasts(%{proxy: {ref, _topic, _pid}}) do
    receive do
      {^ref, {:push_event, "toast", _payload}} -> flush_toasts(%{proxy: {ref, nil, nil}})
    after
      0 -> :ok
    end
  end

  @doc "A toast whose text has `fragment` in it (and is of `kind`, `\"ok\"`, `\"info\"` or `\"error\"`, when given) was pushed."
  def assert_toast(view, fragment, kind \\ nil) do
    all = toasts(view)

    assert Enum.any?(all, &matches?(&1, fragment, kind)),
           "expected a #{kind || "any"} toast with #{inspect(fragment)}, got: #{inspect(all)}"
  end

  @doc "No toast with `fragment` in its text was pushed."
  def refute_toast(view, fragment) do
    all = toasts(view)

    refute Enum.any?(all, &matches?(&1, fragment, nil)),
           "expected no toast with #{inspect(fragment)}, got: #{inspect(all)}"
  end

  defp matches?(%{text: text, kind: kind}, fragment, wanted),
    do: String.contains?(text, fragment) and (is_nil(wanted) or kind == wanted)
end
