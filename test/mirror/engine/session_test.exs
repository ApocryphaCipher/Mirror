defmodule Mirror.Engine.SessionTest do
  use ExUnit.Case, async: true

  alias Mirror.Engine.{Session, SessionSupervisor, View}
  alias Mirror.SaveFile

  defp synthetic_save do
    plane_layers = %{
      terrain: <<42::little-16>> <> :binary.copy(<<0::little-16>>, 60 * 40 - 1),
      terrain_flags: :binary.copy(<<0>>, 60 * 40),
      minerals: :binary.copy(<<0>>, 60 * 40),
      exploration: :binary.copy(<<15>>, 60 * 40),
      landmass: :binary.copy(<<1>>, 60 * 40)
    }

    %SaveFile{
      path: "/fake/SAVE1.GAM",
      raw: <<>>,
      planes: %{
        arcanus: plane_layers,
        myrror: plane_layers
      }
    }
  end

  test "load_save accepts %SaveFile{} and populates world state" do
    {:ok, pid} = SessionSupervisor.start_session(seed: 1234)
    save = synthetic_save()

    assert {:ok, session_id} = Session.load_save(pid, save)
    tile = View.tile_truth(session_id, :arcanus, 0, 0)
    assert tile.terrain_u16 == 42
  end
end
