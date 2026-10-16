defmodule MirrorWeb.Toast do
  @moduledoc """
  A message for the user, shown as a toast in the bottom right corner (STORY-062).

      socket |> Toast.push(:ok, "Edited Jafar: gold 5000", action: :undo)

  The page's `toast.js` keeps the stack: the newest in front, the older ones tucked behind it, each
  fading by itself (an error stays longer), a click dismisses one. The stack lives outside the
  LiveView page, so a toast pushed just before a page change is still there after it.

  Kinds: `:ok` (done, green), `:info` (neutral), `:error` (refused or failed, red). `action: :undo`
  adds an Undo button that clicks the page's own Undo (`#header-undo`), so use it only on pages that
  have one. This replaces the flash messages (`put_flash`) for everything the user did.
  """
  import Phoenix.LiveView, only: [push_event: 3]

  @kinds [:ok, :info, :error]

  @spec push(Phoenix.LiveView.Socket.t(), :ok | :info | :error, String.t(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def push(socket, kind, text, opts \\ []) when kind in @kinds and is_binary(text) do
    payload = %{kind: Atom.to_string(kind), text: text}
    payload = if opts[:action] == :undo, do: Map.put(payload, :action, "undo"), else: payload
    push_event(socket, "toast", payload)
  end
end
