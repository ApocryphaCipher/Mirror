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

  test "competing concurrent updates preserve all mutations without loss (STORY-039)" do
    session_id = "test-session-#{System.unique_integer([:positive])}"
    SessionStore.put(session_id, %{tiles: %{}})

    # Both tasks read the same starting state
    s0_1 = SessionStore.get(session_id)
    s0_2 = SessionStore.get(session_id)
    assert s0_1 == s0_2

    # Task 1 updates tile {1, 1}
    t1 =
      Task.async(fn ->
        SessionStore.update(session_id, fn current ->
          Map.update!(current, :tiles, &Map.put(&1, {1, 1}, :grass))
        end)
      end)

    # Task 2 updates tile {2, 2}
    t2 =
      Task.async(fn ->
        SessionStore.update(session_id, fn current ->
          Map.update!(current, :tiles, &Map.put(&1, {2, 2}, :mountain))
        end)
      end)

    Task.await(t1)
    Task.await(t2)

    final = SessionStore.get(session_id)
    assert final.tiles[{1, 1}] == :grass
    assert final.tiles[{2, 2}] == :mountain
  end
end
