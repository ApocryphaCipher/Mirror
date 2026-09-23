defmodule MirrorWeb.TileProbeLive do
  use MirrorWeb, :live_view

  alias Mirror.{AssetMap, LBX, Paths}

  @page_size 80
  @palette_entry_sizes [768, 1024]
  @max_index_grid_cells 4000
  @hex_dump_bytes 512

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
      |> assign(:palette_source, "game")
      |> assign(:palette_mode, "game")
      |> assign(:borrow_lbx, "")
      |> assign(:borrow_index, "0")
      |> assign(:palette_scan, nil)
      |> assign(:palette_scan_running, false)
      |> assign(:max_index_grid_cells, @max_index_grid_cells)
      |> assign(:hex_dump_bytes, @hex_dump_bytes)
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
    index = parse_int(index, 0)

    socket =
      socket
      |> assign(:selected_entry, index)
      |> assign(:selected_frame, 0)
      |> reload_preview()

    {:noreply, socket}
  end

  def handle_event("set_palette_mode", %{"palette" => params}, socket) do
    socket =
      socket
      |> assign(:palette_mode, params["mode"] || "game")
      |> assign(:borrow_lbx, params["borrow_lbx"] || "")
      |> assign(:borrow_index, params["borrow_index"] || "0")
      |> reload_preview()

    {:noreply, socket}
  end

  def handle_event("scan_palettes", _params, socket) do
    results = scan_palette_candidates(socket.assigns.mom_path, socket.assigns.lbx_files)
    {:noreply, assign(socket, :palette_scan, results)}
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
                    <%= if entry.name do %>
                      <span class="truncate text-[0.7rem] text-amber-200" title={entry_label(entry)}>
                        {entry.name}
                      </span>
                      <span class="truncate text-[0.65rem] text-slate-300" title={entry_label(entry)}>
                        {entry.description}
                      </span>
                    <% end %>
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
                      <p class="mt-2">
                        {@selected_lbx} #{@selected_entry}
                        <span :if={@preview.label} class="text-amber-200">· {@preview.label}</span>
                      </p>
                      <p>Frames: {@preview.frame_count}</p>
                      <p>Size: {@preview.width}×{@preview.height}</p>
                    </div>
                    <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-3 text-xs text-slate-300">
                      <p class="uppercase tracking-[0.2em] text-slate-500">Active frame</p>
                      <p class="mt-2">Frame #{@selected_frame}</p>
                      <p>Palette: {@palette_source}</p>
                      <p>Entry bytes: {@preview.entry_size}</p>
                    </div>
                  </div>

                  <.form
                    for={to_form(%{})}
                    id="palette-mode-form"
                    phx-change="set_palette_mode"
                    class="rounded-2xl border border-white/10 bg-slate-950/40 p-3"
                  >
                    <p class="text-xs uppercase tracking-[0.2em] text-slate-500">
                      Palette mode
                    </p>
                    <div class="mt-2 grid gap-2 sm:grid-cols-3">
                      <select
                        name="palette[mode]"
                        class="rounded-xl border border-white/10 bg-slate-950/60 px-2 py-1 text-xs text-slate-200"
                      >
                        <option value="game" selected={@palette_mode == "game"}>
                          Game palette (FONTS.LBX #2 + embedded)
                        </option>
                        <option value="grayscale" selected={@palette_mode == "grayscale"}>
                          Grayscale (raw indices)
                        </option>
                        <option value="borrow" selected={@palette_mode == "borrow"}>
                          Borrow from another LBX entry
                        </option>
                      </select>
                      <input
                        type="text"
                        name="palette[borrow_lbx]"
                        value={@borrow_lbx}
                        placeholder="Other file.lbx"
                        class="rounded-xl border border-white/10 bg-slate-950/60 px-2 py-1 text-xs text-slate-200"
                      />
                      <input
                        type="text"
                        name="palette[borrow_index]"
                        value={@borrow_index}
                        placeholder="Entry index"
                        class="rounded-xl border border-white/10 bg-slate-950/60 px-2 py-1 text-xs text-slate-200"
                      />
                    </div>
                  </.form>

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
                          class="h-auto w-full rounded-xl"
                          style="image-rendering: pixelated; background: repeating-conic-gradient(#475569 0 25%, #1e293b 0 50%) 0 0 / 16px 16px;"
                        >
                        </canvas>
                        <div class="mt-2 text-xs text-slate-300">
                          Frame {frame.index}
                        </div>
                      </button>
                    <% end %>
                  </div>

                  <% active_frame = Enum.find(@preview.frames, &(&1.index == @selected_frame)) %>
                  <%= if active_frame do %>
                    <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-3 text-xs text-slate-300">
                      <p class="uppercase tracking-[0.2em] text-slate-500">
                        Raw palette indices (frame {active_frame.index})
                      </p>
                      <%= if active_frame.index_summary do %>
                        <p class="mt-2">
                          {active_frame.index_summary.count} pixels, {active_frame.index_summary.distinct_count} distinct value(s), {active_frame.index_summary.transparent} transparent (index 0):
                          <span class="font-mono">
                            {Enum.join(active_frame.index_summary.distinct_values, ", ")}{if active_frame.index_summary.distinct_truncated,
                              do: ", …"}
                          </span>
                        </p>
                      <% else %>
                        <p class="mt-2 text-slate-500">No index data for this frame.</p>
                      <% end %>
                      <%= if active_frame.index_grid do %>
                        <pre class="mt-2 rounded-xl bg-black/40 p-2 font-mono text-[0.65rem] leading-snug text-slate-300 max-h-64 overflow-auto">{Enum.join(active_frame.index_grid, "\n")}</pre>
                      <% else %>
                        <p class="mt-2 text-slate-500">
                          Grid too large to display ({active_frame.width}×{active_frame.height} — cap is {@max_index_grid_cells} cells, summary above still applies).
                        </p>
                      <% end %>
                    </div>
                  <% end %>

                  <div class="rounded-2xl border border-white/10 bg-slate-950/40 p-3 text-xs text-slate-300">
                    <p class="uppercase tracking-[0.2em] text-slate-500">
                      Hex dump (first {@hex_dump_bytes} bytes of {@preview.entry_size})
                    </p>
                    <pre class="mt-2 rounded-xl bg-black/40 p-2 font-mono text-[0.65rem] leading-snug text-slate-300 max-h-64 overflow-auto">{@preview.hex_dump}</pre>
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
              <div class="flex items-center justify-between gap-3">
                <div>
                  <p class="text-xs uppercase tracking-[0.3em] text-slate-400">Palette scan</p>
                  <p class="text-xs text-slate-500">
                    Finds candidate shared-palette entries (768/1024 bytes) across every LBX file — see EPIC-002.
                  </p>
                </div>
                <button
                  id="scan-palettes-button"
                  type="button"
                  phx-click="scan_palettes"
                  class="rounded-full border border-white/20 px-3 py-1 text-xs font-semibold uppercase tracking-[0.2em] text-white transition hover:border-white/40"
                >
                  Scan
                </button>
              </div>
              <%= if @palette_scan do %>
                <div class="mt-3 max-h-48 overflow-auto text-xs text-slate-300">
                  <%= if @palette_scan == [] do %>
                    <p class="text-slate-500">No palette-sized entries found in any file.</p>
                  <% else %>
                    <table class="w-full text-left">
                      <thead class="text-[0.6rem] uppercase tracking-[0.2em] text-slate-500">
                        <tr>
                          <th class="pb-1">File</th>
                          <th class="pb-1">Entry</th>
                          <th class="pb-1">Size</th>
                          <th class="pb-1">Type</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for candidate <- @palette_scan do %>
                          <tr class="border-t border-white/5">
                            <td class="py-1">{candidate.lbx}</td>
                            <td class="py-1">#{candidate.index}</td>
                            <td class="py-1">{candidate.size}</td>
                            <td class="py-1">#{candidate.type}</td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  <% end %>
                </div>
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

  defp reload_preview(socket) do
    mom_path = socket.assigns.mom_path
    lbx_name = socket.assigns.selected_lbx
    index = socket.assigns.selected_entry

    if index == nil do
      socket
    else
      palette_opt = resolve_palette_opt(socket)

      {preview, palette_source} =
        case load_entry_preview(mom_path, lbx_name, index, palette_opt) do
          {:ok, preview, source} -> {preview, source}
          {:error, reason} -> {%{error: inspect(reason)}, "error"}
        end

      socket
      |> assign(:preview, preview)
      |> assign(:palette_source, palette_source)
      |> assign_forms()
    end
  end

  # Translates the UI's palette_mode/borrow_lbx/borrow_index assigns into
  # whatever Mirror.LBX.resolve_palette/3's `:palette` option expects — either
  # one of its own atoms, or an explicit decoded palette list "borrowed" from
  # a different LBX file/entry. The game palette (FONTS.LBX #2) is right for
  # every image checked so far; borrowing is for probing exceptions.
  defp resolve_palette_opt(%{assigns: %{palette_mode: "borrow"} = assigns}) do
    path = resolve_lbx_path(assigns.mom_path, assigns.borrow_lbx)
    borrow_index = parse_int(assigns.borrow_index, 0)

    with {:ok, lbx} <- LBX.open(path),
         {:ok, palette} <- LBX.decode_palette(lbx, borrow_index) do
      palette
    else
      _ -> :auto
    end
  end

  defp resolve_palette_opt(%{assigns: %{palette_mode: "grayscale"}}), do: :grayscale
  defp resolve_palette_opt(_socket), do: :auto

  defp load_entry_preview(mom_path, lbx_name, index, palette_opt) do
    path = resolve_lbx_path(mom_path, lbx_name)

    with {:ok, lbx} <- LBX.open(path),
         {:ok, raw_entry} <- LBX.read_entry(lbx, index),
         label = lbx |> LBX.names() |> Enum.at(index) |> entry_label(),
         {:ok, palette, source} <- LBX.resolve_palette(lbx, index, palette: palette_opt),
         {:ok, image} <- LBX.decode_image(lbx, index, palette: palette) do
      frames =
        Enum.map(image.frames, fn frame ->
          %{
            index: frame.index,
            width: frame.width,
            height: frame.height,
            rgba: Base.encode64(frame.rgba),
            index_summary: index_summary(Map.get(frame, :indices)),
            index_grid: index_grid(Map.get(frame, :indices), frame.width, frame.height)
          }
        end)

      {:ok,
       %{
         width: image.width,
         height: image.height,
         frame_count: image.frame_count,
         frames: frames,
         label: label,
         entry_size: byte_size(raw_entry),
         hex_dump: hex_dump(raw_entry)
       }, Atom.to_string(source)}
    end
  end

  # Raw palette-index values (0-255) for a frame, independent of whatever
  # color the (possibly wrong) palette renders them as — this is what
  # actually answers "what distinct values does this data contain",
  # regardless of palette correctness. See STORY-003 for why this mattered.
  defp index_summary(indices) when is_binary(indices) and byte_size(indices) > 0 do
    values = for <<byte <- indices>>, do: byte
    distinct = values |> Enum.uniq() |> Enum.sort()

    %{
      count: length(values),
      transparent: Enum.count(values, &(&1 == 0)),
      distinct_count: length(distinct),
      distinct_values: Enum.take(distinct, 64),
      distinct_truncated: length(distinct) > 64
    }
  end

  defp index_summary(_), do: nil

  # Text grid of raw indices, row per image row, for small/narrow images
  # (like a 1xN lookup-table-shaped entry) where seeing the literal
  # sequence matters more than a rendered thumbnail. Skipped for anything
  # too big to usefully read.
  defp index_grid(indices, width, height)
       when is_binary(indices) and width * height > 0 and width * height <= @max_index_grid_cells do
    for row <- 0..(height - 1) do
      row_bytes = binary_part(indices, row * width, width)
      row_bytes |> :binary.bin_to_list() |> Enum.join(",")
    end
  end

  defp index_grid(_indices, _width, _height), do: nil

  defp hex_dump(binary) do
    binary
    |> binary_part(0, min(byte_size(binary), @hex_dump_bytes))
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, row} ->
      offset = row * 16
      hex = chunk |> Enum.map(&pad_hex/1) |> Enum.join(" ")
      ascii = chunk |> Enum.map(&printable_byte/1) |> Enum.join("")
      "#{pad_offset(offset)}  #{hex}  #{ascii}"
    end)
    |> Enum.join("\n")
  end

  defp pad_hex(byte), do: byte |> Integer.to_string(16) |> String.pad_leading(2, "0")
  defp pad_offset(offset), do: offset |> Integer.to_string(16) |> String.pad_leading(6, "0")
  defp printable_byte(b) when b >= 32 and b <= 126, do: <<b>>
  defp printable_byte(_), do: "."

  # Scans every LBX file for entries whose size matches a classic 256-color
  # palette (768 bytes = RGB triples, 1024 = RGBA quads). Kept from the
  # palette hunt (EPIC-002); the answer turned out to be FONTS.LBX #2.
  defp scan_palette_candidates(mom_path, lbx_files) do
    Enum.flat_map(lbx_files, fn lbx_name ->
      path = resolve_lbx_path(mom_path, lbx_name)

      case LBX.open(path) do
        {:ok, lbx} ->
          lbx
          |> LBX.entries()
          |> Enum.filter(&(&1.size in @palette_entry_sizes))
          |> Enum.map(&%{lbx: lbx_name, index: &1.index, size: &1.size, type: &1.type})

        {:error, _} ->
          []
      end
    end)
  end

  defp resolve_lbx_path(mom_path, lbx_name) do
    cond do
      lbx_name in [nil, ""] -> ""
      Path.type(lbx_name) == :absolute -> lbx_name
      mom_path in [nil, ""] -> lbx_name
      true -> Path.join(mom_path, lbx_name)
    end
  end

  defp entry_label(%{name: name, description: ""}), do: name
  defp entry_label(%{name: name, description: description}), do: "#{name} · #{description}"
  defp entry_label(_), do: nil

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
