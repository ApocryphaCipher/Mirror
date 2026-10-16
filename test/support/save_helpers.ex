defmodule MirrorWeb.SaveHelpers do
  @moduledoc """
  Opening and saving a save file in a LiveView test, the way the browser does it (EPIC-012): the bytes go
  into the session, nothing is read from or written to a path by the app. `open_save/2` is what clicking a slot
  does; `save_to/2` is what the browser does after the server sends the bytes for a slot.
  """
  import Phoenix.LiveViewTest

  alias Mirror.{SaveManager, SessionStore}

  @doc "Open the save file at `path` in `view`'s session, as a slot click does. Returns the rendered page."
  def open_save(view, path) do
    sid = session_id(view)
    bytes = File.read!(path)
    {:ok, state, _} = SaveManager.load_bytes(bytes, Path.basename(path), SessionStore.get(sid))
    SessionStore.put(sid, state)
    render(view)
  end

  @doc "Write the session's save, edits and all, to `target`, and mark it saved. Returns the rendered page."
  def save_to(view, target) do
    sid = session_id(view)
    {:ok, bytes} = SaveManager.slot_bytes(SessionStore.get(sid))
    File.write!(target, bytes)
    {:ok, _} = SessionStore.update(sid, &SaveManager.mark_saved(&1, Path.basename(target), bytes))
    render(view)
  end

  defp session_id(view), do: :sys.get_state(view.pid).socket.assigns.slots.session_id
end
