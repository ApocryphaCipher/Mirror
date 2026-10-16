defmodule MirrorWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MirrorWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :slots, :map, default: nil, doc: "the socket's `@slots` (MirrorWeb.SaveSlots)"
  attr :active, :any, default: nil, doc: ":arcanus, :myrror or {:wizard, id}, for the header"
  attr :history, :map, default: nil, doc: "`%{undo: bool, redo: bool}` to show Undo and Redo"

  attr :full_bleed, :boolean,
    default: false,
    doc: "when true, remove max width/padding so content can span the viewport"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-slate-100">
      <div class="pointer-events-none absolute inset-0 overflow-hidden">
        <div class="absolute -left-40 top-0 h-[36rem] w-[36rem] rounded-full bg-sky-500/10 blur-[160px]" />
        <div class="absolute right-[-10rem] top-32 h-[28rem] w-[28rem] rounded-full bg-amber-400/10 blur-[140px]" />
        <div class="absolute bottom-[-12rem] left-1/4 h-[24rem] w-[24rem] rounded-full bg-emerald-400/10 blur-[140px]" />
      </div>

      <div class="relative z-10">
        <MirrorWeb.SaveSlots.header slots={@slots} active={@active} history={@history} />

        <main class={[
          @full_bleed && "w-full p-0",
          !@full_bleed && "mx-auto max-w-6xl px-6 py-10"
        ]}>
          {render_slot(@inner_block)}
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center rounded-full border border-white/10 bg-white/5 p-1 text-xs text-white/70">
      <button
        class="flex items-center gap-1 rounded-full px-3 py-1 transition hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
        <span class="hidden sm:inline">System</span>
      </button>
      <button
        class="flex items-center gap-1 rounded-full px-3 py-1 transition hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4" />
        <span class="hidden sm:inline">Light</span>
      </button>
      <button
        class="flex items-center gap-1 rounded-full px-3 py-1 transition hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4" />
        <span class="hidden sm:inline">Dark</span>
      </button>
    </div>
    """
  end
end
