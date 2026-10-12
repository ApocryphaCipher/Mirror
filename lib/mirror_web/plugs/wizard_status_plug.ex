defmodule MirrorWeb.WizardStatusPlug do
  @moduledoc """
  Makes `/wizard/:id` answer **404** for a wizard that does not exist (STORY-047), while the page
  itself (`MirrorWeb.WizardLive`) still draws the note. An id outside 1 to 5 is always a 404; an id in
  range is a 404 when the loaded save has no such wizard, and a 200 ("no save loaded") when no save is
  loaded yet.
  """

  import Plug.Conn

  alias Mirror.SessionStore
  alias MirrorWeb.WizardPanel

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"id" => id}} = conn, _opts) do
    case {Integer.parse(id), raw_of(get_session(conn, :mirror_session_id))} do
      {{n, ""}, nil} when n in 1..5//1 ->
        conn

      {{n, ""}, raw} when is_binary(raw) ->
        if WizardPanel.details(raw, n), do: conn, else: not_found(conn)

      _ ->
        not_found(conn)
    end
  end

  def call(conn, _opts), do: conn

  defp not_found(conn), do: put_status(conn, 404)

  defp raw_of(nil), do: nil

  defp raw_of(session_id) do
    case SessionStore.get(session_id) do
      %{save: %{raw: raw}} when is_binary(raw) -> raw
      _ -> nil
    end
  end
end
