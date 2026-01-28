defmodule MirrorWeb.SessionIdPlug do
  @moduledoc false

  import Plug.Conn

  @session_key :mirror_session_id

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, @session_key) do
      nil ->
        session_id = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
        put_session(conn, @session_key, session_id)

      _ ->
        conn
    end
  end
end
