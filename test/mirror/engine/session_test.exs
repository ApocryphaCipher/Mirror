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

  test "stop/1 terminates session process and unregisters it (STORY-039)" do
    {:ok, pid} = SessionSupervisor.start_session(seed: 1234)
    save = synthetic_save()
    {:ok, session_id} = Session.load_save(pid, save)

    assert Process.alive?(pid)
    assert Session.whereis(session_id) == pid

    ref = Process.monitor(pid)
    assert :ok = Session.stop(session_id)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert Session.whereis(session_id) == nil
  end

  test "stop_session/1 terminates by pid (STORY-039)" do
    {:ok, pid} = SessionSupervisor.start_session(seed: 1234)
    assert Process.alive?(pid)
    ref = Process.monitor(pid)
    assert :ok = SessionSupervisor.stop_session(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    refute Process.alive?(pid)
  end
end
