defmodule Mirror.LBX.Image do
  @moduledoc """
  Decoded LBX image data.
  """

  defstruct [
    :width,
    :height,
    :frame_count,
    :frames,
    :rgba,
    :palette_hash
  ]
end
