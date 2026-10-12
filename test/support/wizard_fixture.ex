defmodule Mirror.WizardFixture do
  @moduledoc "A synthetic save with two wizards (no game data), for the wizard page and edit tests."

  @offset 0x9E8
  @record 0x4C8

  def put(raw, at, bytes) do
    size = byte_size(bytes)
    <<head::binary-size(^at), _::binary-size(^size), tail::binary>> = raw
    head <> bytes <> tail
  end

  def field(raw, record, at, bytes), do: put(raw, @offset + record * @record + at, bytes)

  # A zeroed save with Jafar (record 0, blue) and a rival (record 1, red).
  def synthetic do
    # Unused node records are 0xFF, as in the game (a zeroed one is a node owned by wizard 0).
    raw = put(:binary.copy(<<0>>, 123_300), 0x6058, :binary.copy(<<0xFF>>, 30 * 48))

    raw
    |> field(0, 0x00, <<7>>)
    |> field(0, 0x01, String.pad_trailing("Jafar", 20, <<0>>))
    |> field(0, 0x16, <<0>>)
    |> field(0, 0x24, <<10::little-16, 12::little-16>>)
    |> field(0, 0x2A, <<34, 33, 33>>)
    |> field(0, 0x2E, <<38::little-16, 21::little-16, 1::little-16>>)
    |> field(0, 0x54, <<5::little-16, 60::little-16, 2::little-16>>)
    |> field(0, 0x5A, <<0::little-16, 12::little-16, 0::little-16, 3::little-16, 0::little-16>>)
    |> field(0, 0x64 + 0, <<1>>)
    |> field(0, 0x64 + 13, <<1>>)
    |> field(
      0,
      0x25A,
      <<383::little-16, 500::little-16, 2500::little-16, 0::little-16, 19::little-16>>
    )
    |> field(0, 0x264, <<2, 1, 1>>)
    |> field(0, 0x264 + 40, <<2>>)
    |> field(0, 0x356, <<1234::little-16>>)
    |> field(1, 0x01, String.pad_trailing("Sharee", 20, <<0>>))
    |> field(1, 0x16, <<3>>)
  end

  def put_bytes(raw, at, bytes), do: put(raw, at, bytes)
end
