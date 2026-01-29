defmodule MirrorWeb.TileProbeLive do
  use MirrorWeb, :live_view

  alias Mirror.{AssetMap, LBX, Paths, TileCache}
  alias Mirror.LBX.Palette

  @page_size 80

  @impl true
  def mount(_params, _session, socket) do
    mom_path = Paths.mom_path()
    lbx_files = LBX.list_files(mom_path)
    selected_lbx = List.first(lbx_files)

    {entries, entry_count} = load_entries(mom_path, selected_lbx)

    socket =
      socket
      |> assign(:mom_path, mom_path)
      |> assign(:lbx_files, lbx_files)
      |> assign(:selected_lbx, selected_lbx)
      |> assign(:entries, entries)
      |> assign(:entry_count, entry_count)
      |> assign(:page, 0)
      |> assign(:page_size, @page_size)
      |> assign(:selected_entry, nil)
      |> assign(:selected_frame, 0)
      |> assign(:preview, nil)
      |> assign(:palette_source, "default")
      |> assign_forms()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_lbx", %{"lbx" => lbx_name}, socket) do
    mom_path = socket.assigns.mom_path
    {entries, entry_count} = load_entries(mom_path, lbx_name)

    socket =
      socket
      |> assign(:selected_lbx, lbx_name)
      |> assign(:entries, entries)
      |> assign(:entry_count, entry_count)
      |> assign(:page, 0)
      |> assign(:selected_entry, nil)
      |> assign(:selected_frame, 0)
      |> assign(:preview, nil)
      |> assign_forms()

    {:noreply, socket}
  end

  def handle_event("page_prev", _params, socket) do
    page = max(socket.assigns.page - 1, 0)
    {:noreply, assign(socket, :page, page)}
  end

  def handle_event("page_next", _params, socket) do
    page =
      if (socket.assigns.page + 1) * socket.assigns.page_size < socket.assigns.entry_count do
        socket.assigns.page + 1
      else
        socket.assigns.page
      end

    {:noreply, assign(socket, :page, page)}
  end

  def handle_event("select_entry", %{"index" => index}, socket) do
    mom_path = socket.assigns.mom_path
    lbx_name = socket.assigns.selected_lbx
    index = parse_int(index, 0)
    palette = Palette.default()

    preview =
      case load_entry_preview(mom_path, lbx_name, index, palette) do
        {:ok, preview} -> preview
        {:error, reason} -> %{error: reason}
      end

    socket =
      socket
      |> assign(:selected_entry, index)
      |> assign(:selected_frame, 0)
      |> assign(:preview, preview)
      |> assign_forms()

    {:noreply, socket}
  end

  def handle_event("select_frame", %{"frame" => frame}, socket) do
    frame = parse_int(frame, 0)
    {:noreply, assign(socket, :selected_frame, frame)}
  end

  def handle_event("save_label", %{"label" => params}, socket) do
    kind = parse_kind(params["kind"])
    group = params["group"] || ""
    variant = String.trim(params["variant"] || "")
    frame = parse_int(params["frame"], socket.assigns.selected_frame || 0)
    selected_entry = socket.assigns.selected_entry

    if selected_entry == nil do
      {:noreply, put_flash(socket, :error, "Select an entry before saving.")}
    else
      entry = %{
        "lbx" => socket.assigns.selected_lbx,
        "index" => selected_entry,
        "frame" => frame
      }

      entry = if variant == "", do: entry, else: Map.put(entry, "variant", variant)

      case AssetMap.add_entry(kind, group, entry) do
        {:ok, _map} ->
          {:noreply, put_flash(socket, :info, "Saved mapping for #{group}.")}

        {:error, :missing_group} ->
          {:noreply, put_flash(socket, :error, "Add a group name before saving.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Save failed: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-8">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Tile probe</p>
            <h2 class="text-3xl font-semibold text-white">LBX explorer + labeler</h2>
            <p class="text-sm text-slate-400">
              {if @mom_path, do: @mom_path, else: "Set MIRROR_MOM_PATH to scan LBX files."}
            </p>
          </div>
          <div class="rounded-full border border-white/10 px-4 py-2 text-xs text-slate-300">
            {if @selected_lbx, do: @selected_lbx, else: "No LBX selected"}
          </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-[1.1fr_0.9fr]">
          <section class="space-y-6">
            <div class="rounded-3xl border border-white/10 bg-white/5 p-6 shadow-lg shadow-black/40">
              <p class="text-xs uppercase tracking-[0.3em] text-slate-400">LBX selection</p>
              <.form
                for={@lbx_form}
                id="lbx-form"
                phx-change="select_lbx"
                class="mt-4 grid gap-3 md:grid-cols-[1fr_auto]"
              >
                <.input
                  field={@lbx_form[:lbx]}
                  type="select"
                  options={@lbx_options}
                  prompt="Choose an LBX file"
                  class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200"
                />
                <div class="flex items-center justify-end text-xs text-slate-400">
                  {@entry_count} entries
                </div>
              </.form>
            </div>

            <div class="rounded-3xl border border-white/10 bg-white/5 p-6 shadow-lg shadow-black/40">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Entries</p>
                  <p class="text-sm text-slate-300">
                    Page {@page + 1} · {page_count(@entry_count, @page_size)} total
                  </p>
                </div>
                <div class="flex gap-2">
                  <button
                    id="entries-prev"
                    type="button"
                    phx-click="page_prev"
                    class="rounded-full border border-white/20 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                  >
                    Prev
                  </button>
                  <button
                    id="entries-next"
                    type="button"
                    phx-click="page_next"
                    class="rounded-full border border-white/20 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                  >
                    Next
                  </button>
                </div>
              </div>

              <div class="mt-4 grid gap-2 sm:grid-cols-4 lg:grid-cols-5">
                <%= for entry <- page_entries(@entries, @page, @page_size) do %>
                  <button
                    id={"entry-#{entry.index}"}
                    type="button"
                    phx-click="select_entry"
                    phx-value-index={entry.index}
                    class={[
                      "flex flex-col rounded-2xl border px-3 py-2 text-left text-xs transition",
                      @selected_entry == entry.index &&
                        "border-amber-300/60 bg-amber-300/10 text-white",
                      @selected_entry != entry.index &&
                        "border-white/10 text-slate-300 hover:border-white/30"
                    ]}
                  >
                    <span class="font-semibold">#{entry.index}</span>
                    <span class="text-[0.6rem] uppercase tracking-[0.2em] text-slate-500">
                      #{entry.type}
                    </span>
                    <span class="text-[0.65rem] text-slate-400">{entry.size} bytes</span>
                  </button>
                <% end %>
              </div>
            </div>
          </section>

          <aside class="space-y-6">
            <div class="rounded-3xl border border-white/10 bg-white/5 p-6 shadow-lg shadow-black/40">
              <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Preview</p>
              <%= if @preview && @preview[:frames] do %>
                <div class="mt-4 grid gap-4">
                  <div class="grid gap-3 sm:grid-cols-2">
                    <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-3 text-xs text-slate-300">
                      <p class="uppercase tracking-[0.2em] text-slate-500">Metadata</p>
                      <p class="mt-2">Entry #{@selected_entry}</p>
                      <p>Frames: {@preview.frame_count}</p>
                      <p>Size: {@preview.width}×{@preview.height}</p>
                    </div>
                    <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-3 text-xs text-slate-300">
                      <p class="uppercase tracking-[0.2em] text-slate-500">Active frame</p>
                      <p class="mt-2">Frame #{@selected_frame}</p>
                      <p>Palette: {@palette_source}</p>
                    </div>
                  </div>
                  <div class="grid gap-3 sm:grid-cols-2">
                    <%= for frame <- @preview.frames do %>
                      <button
                        id={"frame-#{frame.index}"}
                        type="button"
                        phx-click="select_frame"
                        phx-value-frame={frame.index}
                        class={[
                          "rounded-2xl border p-2 text-left transition",
                          @selected_frame == frame.index &&
                            "border-amber-300/60 bg-amber-300/10",
                          @selected_frame != frame.index && "border-white/10 hover:border-white/30"
                        ]}
                      >
                        <canvas
                          id={"frame-canvas-#{frame.index}"}
                          phx-hook="RgbaCanvas"
                          data-width={frame.width}
                          data-height={frame.height}
                          data-rgba={frame.rgba}
                          class="h-auto w-full rounded-xl bg-slate-900"
                        >
                        </canvas>
                        <div class="mt-2 text-xs text-slate-300">
                          Frame {frame.index}
                        </div>
                      </button>
                    <% end %>
                  </div>
                </div>
              <% else %>
                <p class="mt-3 text-sm text-slate-400">
                  Select an entry to decode and preview.
                </p>
                <%= if @preview && @preview[:error] do %>
                  <p class="mt-2 text-xs text-rose-300">
                    Decode failed: {@preview.error}
                  </p>
                <% end %>
              <% end %>
            </div>

            <div class="rounded-3xl border border-white/10 bg-white/5 p-6 shadow-lg shadow-black/40">
              <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Label tile</p>
              <.form
                for={@label_form}
                id="label-form"
                phx-submit="save_label"
                class="mt-4 space-y-3"
              >
                <div class="grid gap-3 sm:grid-cols-2">
                  <.input
                    field={@label_form[:kind]}
                    type="select"
                    options={[{"Terrain", "terrain"}, {"Overlay", "overlay"}]}
                    class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200"
                  />
                  <.input
                    field={@label_form[:group]}
                    type="text"
                    placeholder="Group name (e.g. grass, shore_E)"
                    class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200"
                  />
                </div>
                <div class="grid gap-3 sm:grid-cols-2">
                  <.input
                    field={@label_form[:variant]}
                    type="text"
                    placeholder="Variant hint (optional)"
                    class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200"
                  />
                  <.input
                    field={@label_form[:frame]}
                    type="number"
                    class="rounded-2xl border border-white/10 bg-slate-950/60 text-slate-200"
                  />
                </div>
                <button
                  id="save-label-button"
                  type="submit"
                  class="w-full rounded-2xl bg-amber-300 px-4 py-2 text-xs font-semibold uppercase tracking-[0.2em] text-slate-950 shadow-lg shadow-amber-500/30 transition hover:-translate-y-0.5 hover:bg-amber-200"
                >
                  Save mapping
                </button>
              </.form>
            </div>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp assign_forms(socket) do
    lbx_form = to_form(%{"lbx" => socket.assigns.selected_lbx || ""})

    label_form =
      to_form(
        %{
          "kind" => "terrain",
          "group" => "",
          "variant" => "",
          "frame" => socket.assigns.selected_frame || 0
        },
        as: :label
      )

    assign(socket,
      lbx_form: lbx_form,
      label_form: label_form,
      lbx_options: Enum.map(socket.assigns.lbx_files, &{&1, &1})
    )
  end

  defp load_entries(_mom_path, nil), do: {[], 0}

  defp load_entries(mom_path, lbx_name) do
    path = resolve_lbx_path(mom_path, lbx_name)

    case LBX.open(path) do
      {:ok, lbx} ->
        entries = LBX.entries(lbx)
        {entries, length(entries)}

      {:error, _} ->
        {[], 0}
    end
  end

  defp load_entry_preview(mom_path, lbx_name, index, palette) do
    path = resolve_lbx_path(mom_path, lbx_name)

    with {:ok, lbx} <- LBX.open(path),
         {:ok, image} <- TileCache.fetch(lbx, index, palette: palette) do
      frames =
        Enum.map(image.frames, fn frame ->
          %{
            index: frame.index,
            width: frame.width,
            height: frame.height,
            rgba: Base.encode64(frame.rgba)
          }
        end)

      {:ok,
       %{
         width: image.width,
         height: image.height,
         frame_count: image.frame_count,
         frames: frames
       }}
    end
  end

  defp resolve_lbx_path(mom_path, lbx_name) do
    cond do
      lbx_name in [nil, ""] -> ""
      Path.type(lbx_name) == :absolute -> lbx_name
      mom_path in [nil, ""] -> lbx_name
      true -> Path.join(mom_path, lbx_name)
    end
  end

  defp page_entries(entries, page, page_size) do
    Enum.slice(entries, page * page_size, page_size)
  end

  defp page_count(count, page_size) do
    pages = Float.ceil(count / page_size)
    max(trunc(pages), 1)
  end

  defp parse_kind("overlay"), do: :overlay
  defp parse_kind(_), do: :terrain

  defp parse_int(nil, fallback), do: fallback
  defp parse_int(value, _fallback) when is_integer(value), do: value

  defp parse_int(value, fallback) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> fallback
    end
  end
end
