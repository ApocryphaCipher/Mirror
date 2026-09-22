Source files pulled from the real MOMIME project (GPLv2, see [../../../NOTICE.md](../../../NOTICE.md))
for reference while porting the terrain smoothing/rotation algorithm to Elixir. Not
built or imported — reference only.

- Repo: `git clone https://git.code.sf.net/p/momime/momime` (main game — Common/Client/Server modules)
- Repo: `git clone https://git.code.sf.net/p/momime/map` (small standalone `com.ndg.map` coordinate utility library)

| File | From | Why it matters |
| --- | --- | --- |
| `SquareMapDirection.java` | `momime/map` repo, `src/main/java/com/ndg/map/` | Canonical direction order: N=1, NE=2, E=3, SE=4, S=5, SW=6, W=7, NW=8. Matches Mirror's own `@dirs` ordering in `map.ex`/`shore_mask.ex`, just 1-indexed instead of 0-indexed. |
| `TileSetBitmaskGeneratorImpl.java` | `momime` repo, `Client/src/main/java/momime/client/calculations/` | **The actual algorithm for computing a tile's raw (unsmoothed) rotation bitmask.** See [../../notes/2026-09-22-momime-source-findings.md](../../notes/2026-09-22-momime-source-findings.md) for the breakdown — this is the piece Mirror got wrong. |
| `SmoothingSystemEx.java` | `momime` repo, `Common/src/main/java/momime/common/database/` | The declarative rule engine that reduces a raw bitmask down to one that actually has an image, when no exact/rotated match exists. Rules come from graphics XML data (direction/repetition/value conditions), not a generic nearest-match search. |
| `SmoothedTileTypeEx.java` | same | Shows how the reduced bitmask maps to the final image list (random pick among multiple images per bitmask, for visual variety). |
