defmodule Mirror.SessionStoreTest do
  use ExUnit.Case, async: true

  alias Mirror.SessionStore

  test "subscribe/1 and put/2 broadcast state updates to other subscribers" do
    session_id = "test-session-#{System.unique_integer([:positive])}"
    SessionStore.subscribe(session_id)

    # Spawn another process to perform put
    task =
      Task.async(fn ->
        SessionStore.put(session_id, %{draft: 1})
      end)

    Task.await(task)

    assert_receive {:session_state_updated, ^session_id, %{draft: 1}, sender}
    assert is_pid(sender)
    assert sender != self()
    assert SessionStore.get(session_id) == %{draft: 1}
  end

  test "update/2 serializes state updates and broadcasts to subscribers" do
    session_id = "test-session-#{System.unique_integer([:positive])}"
    SessionStore.subscribe(session_id)

    {:ok, state} =
      SessionStore.update(session_id, fn current ->
        Map.put(current, :counter, 42)
      end)

    assert state == %{counter: 42}
    assert SessionStore.get(session_id) == %{counter: 42}
    assert_receive {:session_state_updated, ^session_id, %{counter: 42}, sender}
    assert sender == self()
  end
end
