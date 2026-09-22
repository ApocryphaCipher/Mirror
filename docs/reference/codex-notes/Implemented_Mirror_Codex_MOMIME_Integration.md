# Mirror ↔ MOMIME Integration Plan (Codex Prompt, GPLv2-Compatible)

You are integrating MOMIME (Master of Magic – IME) map architecture concepts *deeply* into Mirror (Elixir/Phoenix). Mirror may be GPLv2.

This prompt is not asking for a line-by-line translation. It requires **conceptual fidelity and behavioral correctness**, implemented idiomatically in Elixir.

## Attribution / Licensing (Required)
- Add GPLv2 license headers to any ported/adapted modules.
- Document which MOMIME concepts/files informed each module in module docs.
- Preserve attribution in `NOTICE`/`CREDITS` and source headers.

---

## 1) What to Port Conceptually from MOMIME

### A) Storage vs Operations split (MOMIME: `MapArea` vs `MapAreaOperations*`)
MOMIME separates:
- **Storage**: `MapArea<E,C>` interface (get/set, coordinate system)
- **Operations**: `MapAreaOperations*` classes (process all cells, copy, set all, radius ops, random selection)

Mirror must mirror this separation:
- Keep canonical map state in compact storage (binaries/arrays/ETS)
- Provide pure “ops” modules that read/write via a storage API (no Phoenix concerns)

### B) Coordinate system utilities (MOMIME: `CoordinateSystemUtilsImpl`)
Key behaviors to preserve:
- Bounds checks (`are2DCoordinatesWithinRange`)
- Coordinate normalization for wrapping (`normalizeCoordinate`)
- Direction normalization for square/diamond/hex (`normalizeDirection`)
- Movement by direction (`move2DCoordinates`) with optional wrap constraints

Mirror: support at minimum MoM Classic topology:
- width=60, height=40
- wraps left↔right (X)
- does NOT wrap top↔bottom (Y)

Implement as `Mirror.Engine.Coord` + `Mirror.Engine.Topology`.

### C) Area processing primitives (MOMIME: `processAllCells`, `processCellsWithinRadius`)
Port the *idea*:
- Efficient iteration over all tiles
- Efficient iteration within radius / rings
- Callbacks/functions applied to each coord/cell

Mirror: implement these ops as pure functions over a “map view” abstraction:
- `each_coord/2`
- `each_coord_in_radius/4`
- `flood_fill/…`
- `random_coord_matching/…` (seeded RNG)

### D) Deterministic generation scaffolding (MOMIME: `HeightMapGenerator`)
MOMIME uses a deterministic heightmap generator + post-processing.
Mirror must implement a deterministic generation pipeline scaffold (even if map gen is not fully shipped yet):
- `seed` driven
- reproducible outputs
- stage-by-stage invariants

Do not implement “generic procgen”; implement a MoM-style staged pipeline interface.

---

## 2) Mirror Engine Architecture (Idiomatic Elixir)

### Supervision Tree (per running Mirror instance)
- `Mirror.Engine.Supervisor`
  - `Mirror.Engine.Registry` (Registry for game sessions)
  - `Mirror.Engine.SessionSupervisor` (DynamicSupervisor)
  - `Mirror.Engine.Stats` (ETS/DETS research DB already exists)

### Per-Open-Save Session (authoritative world state)
For each loaded save (or generated map), start a session process:

- `Mirror.Engine.Session` (GenServer)
  - owns canonical state refs:
    - save binary (immutable baseline)
    - map layers (ETS tables or binaries in state)
    - visibility/fog tables (ETS)
    - event log / delta queue
    - deterministic RNG seed for any generation or test ops

Session is addressed by `session_id` (UUID) stored in LiveView assigns.

### ETS Usage (fast random access)
Use ETS for mutable tile arrays, keyed by `{layer, plane}`:
- `:mirror_map_{session_id}` — table storing per-layer binaries or per-tile values
  - recommended: store binaries and update via binary patch helpers; OR store arrays of ints for fast toggling experiments
- `:mirror_vis_{session_id}` — table storing per-player visibility (bitsets)

Important: keep operations in pure modules; Session only orchestrates + applies diffs.

---

## 3) Data Model / Structs

### Canonical World State
```elixir
defmodule Mirror.Engine.World do
  @enforce_keys [:topology, :planes, :layers, :meta]
  defstruct topology: nil,
            planes: [:arcanus, :myrror],
            layers: %{},     # %{ {plane, layer} => layer_ref }
            meta: %{}        # %{seed: ..., source: :save|:generated, version: ...}
end
```

### Layer Identifiers
Use atoms for layer names:
- `:terrain_u16` (raw terrain word)
- `:terrain_base_u8` (derived: low byte)
- `:terrain_embedded_special_u8` (derived: high byte)
- `:terrain_flags_u8`
- `:minerals_u8`
- `:exploration_u8`
- `:landmass_u8`
- `:computed_adj_mask_u8` (derived)
- `:computed_ray_features` (derived/telemetry, not persisted as per-tile)

### Visibility / Fog of War
Model three truths explicitly:
1) **Canonical** world truth (what exists)
2) **Explored** per player (what has ever been seen)
3) **Visible now** per player (current LOS)

```elixir
defmodule Mirror.Engine.Visibility do
  defstruct explored: %{},   # %{player_id => bitset}
            visible: %{},    # %{player_id => bitset}
            last_seen: %{}   # optional: %{player_id => %{idx => seen_turn}}
end
```

Bitset representation:
- Use `:bitstring` binaries length = 2400 bits per plane (or 4800 for both planes).
- Provide helpers `get_bit/2`, `set_bit/3`, `or_bitsets/2`, etc.

---

## 4) Query Model: Canonical vs Player-Filtered Views

Implement query functions that return “what player knows” without mutating canonical state:

```elixir
defmodule Mirror.Engine.View do
  @type plane :: :arcanus | :myrror

  @spec tile_truth(session_id, plane, x :: non_neg_integer, y :: non_neg_integer) :: map()
  def tile_truth(session_id, plane, x, y), do: ...

  @spec tile_for_player(session_id, player_id, plane, x, y) :: map()
  def tile_for_player(session_id, player_id, plane, x, y) do
    # If not explored: return :unknown with minimal info
    # If explored but not visible: return :remembered (optional)
    # If visible: return full truth
  end
end
```

This directly mirrors the MOMIME concept of separating storage from “presentation truth.”

---

## 5) Incremental Updates (Delta-Based, Not Full Recompute)

Mirror must support event/delta updates for:
- tile edits
- brush strokes
- bit flips
- visibility changes (unit moved)
- generation stage progress

### Delta structure
```elixir
defmodule Mirror.Engine.Delta do
  defstruct type: nil,        # :tile_set | :stroke | :vis_update | ...
            plane: nil,
            layer: nil,
            changes: [],      # [{idx, old, new}] or [{x,y,old,new}]
            meta: %{}
end
```

Session should:
- apply deltas to ETS/binaries
- broadcast minimal patches to LiveView (existing mechanism)
- append deltas to an in-memory log for undo/redo and replay

Fog-of-war recompute must be incremental where possible:
- when a unit moves: recompute LOS region and update `visible` bitset deltas

---

## 6) Deterministic Map Generation Pipeline (MoM-style)

Implement a scaffold (even if not fully used yet) with stages and invariants:

```elixir
defmodule Mirror.Engine.Gen.Pipeline do
  @type stage :: :heightmap | :thresholds | :biomes | :rivers | :roads | :specials | :polish

  @spec run(seed :: integer(), opts :: map()) :: {:ok, Mirror.Engine.World.t(), [Mirror.Engine.Delta.t()]}
  def run(seed, opts), do: ...

  @spec run_stage(stage, world, rng_state, opts) :: {:ok, world, rng_state, [delta]}
  def run_stage(stage, world, rng_state, opts), do: ...
end
```

### Heightmap stage (MOMIME reference)
Port the *concept* of `HeightMapGenerator`:
- deterministic RNG
- produces an integer height field per plane
- provides threshold queries (“count above/below”, “find height with desired tile count”)

In Mirror, represent heightmap as a temporary `:height_u16` layer or local binary, not saved to MoM save files unless explicitly exported.

---

## 7) What to Port Directly vs Re-Implement

### Port/Adapt (High fidelity)
- Coordinate normalization + directional movement rules (wrap X only)
- Area iteration primitives (all cells, within radius, ring processing)
- Seeded random selection from matching cells (deterministic)
- Heightmap generator **interface + invariants** (implementation can be adapted)

### Re-Implement Idiomatically (Elixir)
- Storage backend (ETS + binaries instead of Java objects)
- Visibility bitsets and LOS computation (pure functions + ETS)
- Delta/event bus (PubSub broadcasts to LiveView)
- Undo/redo (stroke diffs, already in Mirror)

---

## 8) Concrete Implementation Tasks (Codex)
Implement the following modules with signatures + docs. Keep code testable and pure.

### Topology / Coordinate Utils
```elixir
defmodule Mirror.Engine.Topology do
  @type t :: %__MODULE__{w: pos_integer, h: pos_integer, wrap_x: boolean, wrap_y: boolean}
  defstruct w: 60, h: 40, wrap_x: true, wrap_y: false

  @spec in_bounds?(t(), x :: integer, y :: integer) :: boolean
  def in_bounds?(topo, x, y), do: ...

  @spec norm_x(t(), x :: integer) :: non_neg_integer
  def norm_x(topo, x), do: ...

  @spec norm_y(t(), y :: integer) :: {:ok, non_neg_integer} | :oob
  def norm_y(topo, y), do: ...

  @spec neighbor(t(), x :: integer, y :: integer, dir :: 0..7) :: {:ok, {x,y}} | :oob
  def neighbor(topo, x, y, dir), do: ...
end
```

### Storage API (MOMIME-style MapArea)
```elixir
defmodule Mirror.Engine.MapArea do
  @callback get(ref, x :: non_neg_integer, y :: non_neg_integer) :: integer
  @callback put(ref, x :: non_neg_integer, y :: non_neg_integer, value :: integer) :: ref
  @callback dims(ref) :: {pos_integer, pos_integer}
end
```

Provide implementations for:
- `Mirror.Engine.MapArea.BinaryU8`
- `Mirror.Engine.MapArea.BinaryU16LE`
- (optional) ETS-backed variants

### Operations (MOMIME-style MapAreaOperations)
```elixir
defmodule Mirror.Engine.MapOps do
  @spec each_coord(topo, fun((x,y) -> any)) :: :ok
  def each_coord(topo, fun), do: ...

  @spec each_coord_in_radius(topo, cx, cy, radius, fun) :: :ok
  def each_coord_in_radius(topo, cx, cy, radius, fun), do: ...

  @spec random_coord_matching(rng, topo, area_ref, predicate) :: {{x,y}, rng} | {nil, rng}
  def random_coord_matching(rng, topo, area_ref, predicate), do: ...
end
```

### Visibility / Fog-of-War
```elixir
defmodule Mirror.Engine.Fog do
  @spec visible_bitset_for_player(session_id, player_id, plane) :: bitstring
  def visible_bitset_for_player(session_id, player_id, plane), do: ...

  @spec recompute_visible_delta(world, player_id, plane, sources :: [{x,y,radius}], prev_bitset) :: {new_bitset, delta_changes}
  def recompute_visible_delta(world, player_id, plane, sources, prev), do: ...

  @spec apply_exploration(explored_bitset, visible_bitset) :: explored_bitset
  def apply_exploration(explored, visible), do: ...
end
```

### Session Process + Delta Bus
```elixir
defmodule Mirror.Engine.Session do
  use GenServer

  @spec start_link(opts) :: GenServer.on_start()
  def start_link(opts), do: ...

  @spec load_save(pid, path) :: {:ok, session_id} | {:error, term}
  def load_save(pid, path), do: ...

  @spec apply_delta(pid, Mirror.Engine.Delta.t()) :: :ok
  def apply_delta(pid, delta), do: ...

  @spec query(pid, fun) :: any
  def query(pid, fun), do: ...
end
```

---

## 9) Integration Notes for Existing Mirror Work
- Keep existing save offsets + layer extraction logic.
- Keep existing research stats system (ETS/DETS) and extend it to record fog/visibility stats if desired.
- Keep existing canvas rendering; it should render **player-filtered view** optionally:
  - “truth mode” (developer)
  - “player mode” (fog applied)

---

## Done Criteria
- Canonical world state stored once per session (ETS/binaries).
- Player-visible map derived via bitset filters (no mutation).
- Delta updates drive UI patches (no full redraw required unless requested).
- Deterministic generation scaffold exists (seeded), even if not fully used yet.
- Modules are documented with GPL attribution notes.

---

End of prompt.
