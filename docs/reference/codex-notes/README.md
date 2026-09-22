The actual prompt/plan documents from the prior Codex sessions that built the
current MOMIME-PNG rendering path (~7 months ago), pulled from `Mirror Docs.zip`
on Kevin's Google Drive. Kept verbatim for reference — these are historical
planning docs, not current instructions.

Read [../../notes/2026-09-22-momime-source-findings.md](../../notes/2026-09-22-momime-source-findings.md) first — it traces
through these files to explain exactly where the rotation logic went wrong
and why iterating on it never converged.

Most relevant to the rotation bug, in the order the work actually happened:

1. `Implemented_Mirror_Codex_Fix_Grassland_And_Coast_Rotation.md` — first
   diagnosis, proposed the "try 4 rotations, see what matches a real file"
   approach.
2. `Implemented_Mirror_Codex_Shoreline_Adjacency_Canonicalization.md` — where
   the (incorrect) "diagonals are ternary, `2` = corner unsupported by
   cardinals" theory was invented and formalized.
3. `Implemented_Mirror_Codex_Fix_Toothy_Shorelines.md` — noticed the above
   was collapsing distinct shorelines into the same wrong tile, fixed the
   resource-indexing regex (binary → ternary keys) and shore-as-water
   classification.
4. `Implemented_Mirror_Codex_Shoreline_Semantic_Classifier.md` — added the
   `straight_edge`/`convex_corner`/`concave_inlet`/`peninsula`/`island_tip`/`channel`
   classifier to stop fallback from crossing semantically different shore
   shapes. This is the last rotation-related doc — after this the theory
   never got checked against real MOMIME source, which is what today's
   session did instead.

The rest (`MOMIME_Integration.md`, `MOMIME_Like_Render_Pipeline.md`,
`MOMIME_PNG_Terrain_Renderer.md`, `Part1_Core.md`, `Part2_LBX_Renderer.md`,
`LBX_Palette_and_Decode.md`, `Canvas_Geometry_Invariants.md`,
`Terrain_Phase_Loop_Autodetect.md`, `Terrain_Phase_Rendering_v2.md`,
`Tile_Bit_Inspector.md`) are architecture/infra planning docs — not yet read
in detail this session, kept here for whenever they're needed.
