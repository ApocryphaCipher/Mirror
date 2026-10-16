defmodule MirrorWeb.LandingLive do
  @moduledoc """
  The start page (`/`, EPIC-012): pick the game folder, then click the save to open. Opening a
  save goes on to the map. To open a different save later, come back here (the logo links to it).
  The work is in `MirrorWeb.SaveSlots`; this page only lays it out.
  """
  use MirrorWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-slate-100">
      <MirrorWeb.SaveSlots.landing slots={@slots} />
      <MirrorWeb.Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
