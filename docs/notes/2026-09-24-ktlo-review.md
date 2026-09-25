# 2026-09-24: Keeping the Lights On review (raw findings)

Two read-only reviews of `main` at `79e4ff1`, run by OpenAI Codex (GPT-6)
under Claude's direction (Kevin's request). The model had a read-only
sandbox and a clean checkout with no game files. The findings are
reproduced as it wrote them; line numbers refer to `79e4ff1`.

**Verified by Claude:**
- **Save safety, findings 1 and 5:** confirmed by reading the code.
- **Discard doesn't refresh the overlays:** confirmed. It's Claude's own
  mistake from STORY-035/036.
- **Docs, surveyor-formula wording (wild game, feature order):**
  confirmed.

Everything else is the model's claim, with the verification it
describes. Check each before fixing it. The triage into stories is
[EPIC-008](../epics/EPIC-008-keeping-the-lights-on.md).

## Code review (lib/, test/, assets/js/, scripts/)

- **High — `lib/mirror_web/live/map_live.ex:2998`:** After “Save as,” submitting an empty destination passes the guard using `state.save_path`, but the writer falls back to the originally loaded file. **Fix:** Resolve one explicit destination and use it for both validation and writing. **Verified:** Executed the extracted guard in memory: it returned `:ok`, while the writer’s fallback selected `SAVE1.GAM`.

- **High — `lib/mirror_web/live/map_live.ex:3000`:** The Lab explicitly bypasses protection against overwriting the loaded save. **Fix:** Enforce source protection inside `SaveFile.write/3` for every caller. **Verified:** Executed the guard with `lab?: true` and identical source/destination paths; it returned `:ok`.

- **High — `lib/mirror_web/live/map_live.ex:3000`:** Comparing expanded path strings permits overwriting the original through symlinks, hard links, or differently cased names on case-insensitive filesystems. **Fix:** Check filesystem identity and enforce destination safety when opening the output. **Verified:** Traced `Path.expand/1` comparisons directly into unrestricted `File.write/2`; no identity check exists.

- **High — `lib/mirror_web/live/map_live.ex:2145`:** Terrain edits change terrain bytes without maintaining landmass IDs, allowing inconsistent saves after land/water transitions. **Fix:** Update dependent landmass data transactionally or reject unsupported transitions. **Verified:** Traced edit and serialization paths, searched all landmass handling, and confirmed in-memory serialization leaves landmass bytes unchanged.

- **High — `lib/mirror/save_file.ex:99`:** Saving over another existing save backs up the source instead of the destination, destroying the destination’s previous contents without preserving them. **Fix:** Refuse existing destinations or back up the actual destination before replacing it. **Verified:** Checked branch ordering: an existing source always wins over the destination-backup branch.

- **High — `lib/mirror/session_store.ex:21`:** Two tabs sharing a session can silently replace each other’s drafts because each writes its entire stale socket state into ETS. **Fix:** Serialize edits against authoritative session state and synchronize subscribers. **Verified:** Traced the shared cookie ID, mount-time state reads, and unconditional whole-state writes from editing and brush-selection handlers.

- **Medium — `lib/mirror/save_file.ex:67`:** Writing directly to the destination can leave a truncated save after an interrupted or failed write. **Fix:** Write and validate a temporary sibling file, then atomically install it while preserving overwrite protections. **Verified:** The write path contains only `File.write/2`, with no temporary file or atomic replacement.

- **Medium — `lib/mirror/terrain_lbx.ex:55`:** Terrain decoding accepts an undersized minimap table that subsequently crashes payload construction. **Fix:** Validate both planes’ minimap bytes before returning `{:ok, terrain}`. **Verified:** A synthetic zero-byte minimap passed `decode/2`, then raised `ArgumentError` in `payload/1`.

- **Medium — `lib/mirror/save_file/cities.ex:91`:** City names can retain invalid UTF-8 and reach LiveView’s JSON payloads, potentially breaking rendering or event delivery. **Fix:** Validate or convert names to valid UTF-8 at the decoding boundary. **Verified:** A synthetic name containing `0xFF` parsed successfully with `String.valid?/1 == false`; downstream serialization failure is **unverified**.

- **Medium — `lib/mirror_web/live/map_live.ex:132`:** The Lab receives `edit_mode: "view"`, disabling its client-side painting and wheel controls. **Fix:** Preserve `"lab"` interaction mode or omit this event for Lab views. **Verified:** Executed the actual JavaScript hook with the server’s payload; painting changed from enabled to disabled.

- **Medium — `lib/mirror_web/live/map_live.ex:530`:** Statistics export passes tuple-valued identifiers and tuple map keys to `Jason.encode!/2`, which cannot encode that structure. **Fix:** Convert identifiers and keys into JSON-compatible strings or structured records. **Verified:** Traced `Stats.handle_call/3` and the identity `format_key/1` into the encoder; end-to-end execution is **unverified** because dependencies are absent.

- **Medium — `lib/mirror_web/live/map_live.ex:2010`:** Starting a paint drag on a tile already matching the brush creates no active stroke, so subsequent dragged-over tiles are ignored. **Fix:** Start an empty stroke on pointer-down and record history when its first actual change occurs. **Verified:** Traced the no-change branch into `handle_pointer_drag/3`, which requires an existing active stroke.

- **Medium — `lib/mirror_web/live/map_live.ex:200`:** Discard after “Save as” restores the last-saved planes but reloads the engine from the original file, making engine-backed inspection disagree with the canvas. **Fix:** Rebuild the engine from the restored in-memory planes. **Verified:** Saving updates `original_planes` without changing `save.path`, and hover inspection prefers engine layer values.

- **Medium — `lib/mirror_web/live/map_live.ex:214`:** Discard reloads terrain without refreshing settleable and fog overlays, leaving overlays calculated from discarded edits. **Fix:** Refresh derived overlays and hover state after restoring planes. **Verified:** Compared discard’s push chain with undo/redo, which explicitly call `push_map_layers/1`.

- **Medium — `lib/mirror_web/live/map_live.ex:3316`:** Loading or discarding repeatedly starts supervised engine sessions without terminating superseded sessions, retaining their saves, ETS tables, and delta histories. **Fix:** Reuse the session or explicitly stop replaced and failed-start sessions. **Verified:** Searched lifecycle callers and found session creation but no termination or cleanup path.

- **Medium — `lib/mirror_web/live/map_live.ex:2336`:** Terrain changes update server-side adjacency masks without sending those changed masks to the browser, leaving the Lab’s adjacency overlay stale. **Fix:** Emit updates for affected adjacency cells alongside terrain changes. **Verified:** Traced mask recomputation into payload construction, which sends only the edited layer.

- **Medium — `lib/mirror_web/live/map_live.ex:2234`:** Undo and redo change map data without reversing or reapplying histogram updates, so displayed research statistics diverge from the map. **Fix:** Route history operations through the same statistics-update logic as ordinary edits. **Verified:** Compared `apply_stroke/4` with `do_apply_change/7`; only the latter calls `update_stats/9`.

- **Medium — `lib/mirror_web/live/map_live.ex:3059`:** When all nine save slots are occupied, the suggested destination becomes `*-edited.GAM`, which the game cannot load. **Fix:** Report exhausted slots and require another directory containing an available `SAVE1`–`SAVE9` slot. **Verified:** Checked the explicit fallback against AGENTS.md’s supported save filenames.

- **Medium — `lib/mirror/engine/map_ops.ex:221`:** Wrapped radius traversal counts repeated coordinates toward its stopping limit, terminating before visiting all eligible tiles. **Fix:** Track visited coordinates and decrement the remaining count only for new tiles. **Verified:** A radius-five traversal on a wrapped `3×8` map produced 24 visits but only 15 unique coordinates instead of 24.

- **Medium — `lib/mirror/engine/fog.ex:82`:** Fog bitsets support arbitrary bit counts when allocated but require whole-byte binaries when updated, crashing on map sizes not divisible by eight. **Fix:** Consistently support partial bytes or allocate padded byte storage. **Verified:** `recompute_visible_delta/5` raised `MatchError` for a valid `3×3` topology.

- **Medium — `lib/mirror/lbx.ex:382`:** A trailing RLE repeat marker without its value is accepted as a literal pixel instead of rejected as malformed input. **Fix:** Return an error for incomplete repeat pairs and propagate it through frame decoding. **Verified:** A synthetic frame ending in `0xE0` decoded successfully to pixel `224`.

- **Medium — `lib/mirror/save_file/blocks.ex:75`:** `put_plane_slice/4` raises on a truncated destination binary despite returning errors for other invalid inputs. **Fix:** Validate destination bounds before matching the replacement slice. **Verified:** An empty destination with a correctly sized terrain slice raised `MatchError`.

- **Medium — `test/mirror_web/live/map_live_edit_test.exs:17`:** Every editing and save-safety test is skipped without personal game files, leaving ordinary CI without coverage for these critical behaviors. **Fix:** Use synthetic saves for editing, history, overwrite protection, and round-trip tests. **Verified:** Inspected the module-wide skip and test inventory; 50 read-only tests passed separately, but full Mix checks were not run because dependencies/build artifacts are absent and the requested review forbids file writes.

- **Low — `lib/mirror/tile_cache.ex:1`:** The disk tile-cache module has no callers in the reviewed application, tests, or scripts. **Fix:** Propose its removal separately, or document and test a concrete retained use. **Verified:** Searched for module references and cache API calls across the requested directories.

- **Low — `lib/mirror_web/live/map_live.ex:1`:** The 3,416-line LiveView combines rendering, edit history, filesystem operations, statistics, and engine synchronization, making consistency rules difficult to maintain. **Fix:** Extract editor-state transitions and save orchestration into focused, testable modules. **Verified:** Read the event handlers and helper paths; ordinary edits, history operations, and discard currently maintain overlapping state through separate implementations.
## Documentation review (docs versus code)

- **High — `AGENTS.md:156`: original-save protection is not universal.** “Never overwrite the save that was loaded” conflicts with `MapLive.guard_original/3`, which exempts Lab mode (`lib/mirror_web/live/map_live.ex:2997`). `SaveFile.write/3` also defaults to the loaded path (`lib/mirror/save_file.ex:61`). **Suggested fix:** document this enforcement gap and apply protection consistently.

- **High — `AGENTS.md:158`: terrain edits do not maintain landmass consistency.** The rule requires consistent continent IDs, but painting and cycling update terrain and the derived adjacency mask only (`map_live.ex:2145`). **Suggested fix:** explicitly document the current raw editor’s limitation and retain consistency enforcement as unfinished STORY-017/029 work.

- **Medium — `AGENTS.md:156`: Save as does not guarantee a new `SAVE1`–`SAVE9` file.** Arbitrary names and existing destinations other than the loaded path are accepted. When all nine slots exist, the suggestion becomes `*-edited.GAM` (`map_live.ex:3058`). **Suggested fix:** describe actual naming/overwrite behavior and the nine-slot limitation.

- **Medium — `docs/reference/surveyor-formula.md:224`: contradictory empty-site wild-game formula.** This paragraph says **2 quarter-food**; lines 114–116 and `site_max_pop/2` implement **1 quarter-food**, halved again when shared (`surveyor.ex:164`). An in-memory check with 21 forests and one wild-game tile returns maximum population **10**; two quarter-food would produce **11**. **Suggested fix:** reconcile the paragraph with the implementation and explicitly state the shared-site coefficient; which coefficient matches the game remains **unverified in this review**.

- **Medium — `docs/reference/surveyor-formula.md:293`: existing cities do not always show City Resources.** `settle_check/7` checks water, towers, nodes and intact encounters **before** accepting an existing city (`surveyor.ex:451`). An in-memory city-on-water case returned “on water.” **Suggested fix:** qualify the documented exception or move the existing-city exemption before those checks.

- **Medium — `docs/reference/surveyor-formula.md:279`: feature precedence is reversed.** The document lists intact sites before nodes; `site_at/4` selects a node first (`surveyor.ex:423`). An in-memory overlapping node/Keep case displayed the node. **Suggested fix:** document nodes before encounters, or change the implementation if encounter precedence is intended.

- **Medium — `docs/stories/STORY-036-fog-of-war-layer.md:13`: other layers do not “keep showing everything.”** Fog draws last and covers cities and settlement tint (`map_live.ex:36`; `assets/js/map_overlays.js:234`). Surveyor also respects exploration independently of the fog toggle. **Suggested fix:** distinguish retaining underlying layer data from keeping it visible, and describe Surveyor’s separate exploration restriction.

- **Medium — `docs/stories/STORY-035-settleable-tiles-overlay.md:38`: tinted tiles do not always show full resources on hover.** `settleable/4` treats the entire catchment as explored, whereas `panel/6` hides unexplored tiles and `city_resources/5` excludes unexplored catchment tiles for empty sites (`surveyor.ex:118,304,334`). Consequently, even an explored tile’s displayed maximum population can differ from its tint. **Suggested fix:** document the distinction and qualify the agreement promised at line 73.

- **Medium — `README.md:12`: cities are incorrectly described as upcoming and undrawn.** Cities already render with owner-coloured flags; the application also has layer toggles, Surveyor, settlement grading and optional fog (`map_overlays.js:63`; `map_live.ex:1748,2885`). **Suggested fix:** update Status and map-page usage, keeping units, sites, roads and auras listed as unfinished.

- **Medium — `docs/epics/EPIC-002-remove-momime-dependency.md:3` and `docs/stories/README.md:5`: MOMIME removal is incorrectly pending.** `Mirror.TileAtlas` has only the `TERRAIN.LBX` backend (`lib/mirror/tile_atlas.ex:15`); STORY-014 and the backlog already record removal. **Suggested fix:** mark that follow-up complete and label the epic’s contrary “today” narrative as historical.

- **Medium — `docs/epics/EPIC-006-map-first-ui-and-edit-mode.md:3`: “scoped, not started” is stale.** Lab routes, viewport controls, editing, cycling, undo/redo, discard, Surveyor and the two newer overlays are implemented. **Suggested fix:** mark the epic in progress and summarize completed versus remaining stories.

- **Medium — `docs/epics/EPIC-004-overland-map-features.md:13`: “never parsed or rendered cities” is false now.** `Cities.parse/1`, `Sites.parse/1`, city payloads and the city drawer exist. The scoping instructions also reference the deleted `scripts/build_momime_resources_index.sh` at line 61. **Suggested fix:** replace the current-state section and clearly archive the obsolete implementation plan.

- **Medium — `docs/epics/EPIC-004-overland-map-features.md:38`: city `+34` is incorrectly called an active-spells bitmask.** The current decoder reads building statuses at `+31..+66` and enchantments at `+67..+92` (`lib/mirror/save_file/cities.ex:81`). **Suggested fix:** align the field summary with the decoder and current reference documentation.

- **Medium — `docs/epics/EPIC-005-animated-terrain-and-magic.md:13` and `docs/stories/STORY-008-node-auras.md:27`: acceptance criteria still require realm-coloured auras.** STORY-008’s own updated evidence at line 9 says owner colour. The decoder distinguishes owner from node type; aura drawing remains unimplemented. **Suggested fix:** reconcile the epic and acceptance criteria with that recorded result; rendering correctness remains **unverified**.

- **Medium — `README.md:61` and `AGENTS.md:75`: game-test configuration is incomplete.** Surveyor’s real-save tests use `MIRROR_SURVEYOR_SAVE` or a separate frozen fixture, not `MIRROR_MOM_PATH` (`test/mirror/surveyor_test.exs:237`). `scripts/test_game.sh` does not provision it. **Suggested fix:** document the additional fixture and qualify “everything” in the test instructions.

- **Medium — `docs/backlog.md:16`: re-running import will not make the extra LBX files available.** The suggested import copies only five manifest filenames and numbered saves (`lib/mirror/game_files.ex:226`). **Suggested fix:** instruct readers to point `MIRROR_MOM_PATH` at the complete installation for exploration, or copy additional files explicitly.

- **Medium — `docs/notes/2026-09-24-live-ram-evaluation.md:26,79`: Surveyor is still presented as awaiting its formula.** `Mirror.Surveyor` and the LiveView card are implemented; the later Surveyor handoff explicitly supersedes that assessment. **Suggested fix:** mark both the table row and scheduling recommendation superseded and link the later handoff.

- **Low — `docs/stories/README.md:14–27`: completed stories lack completion markers.** STORY-014, 015, 016, 023, 026 and 027 are marked done/fixed in their individual files, with corresponding routes, controls and handlers in code. **Suggested fix:** synchronize those index entries and their EPIC-006 list entries; keep STORY-022 marked partially fixed.

- **Low — `docs/stories/STORY-016-edit-mode-shell.md:9`: the documented default mouse behavior is stale.** Edit mode defaults to Cycle: left advances and right/Shift reverses. Left-paint/right-sample applies to Paint (`map_live.ex:71,1916`). **Suggested fix:** describe controls separately for each tool.

- **Low — `docs/stories/STORY-015-view-mode-layout.md:12`: Edit and overlay toggles remain labelled deferred.** Both are implemented, as are city/site details through Surveyor. **Suggested fix:** replace the deferred list with the remaining omissions, including unit information and touch pinch zoom.

- **Low — `docs/stories/STORY-010-cities.md:41`: “every city uses the unwalled sprite” is stale.** The drawer always uses MAPBACK #20; wall status is decoded, and STORY-032 records why walls do not select a different sprite (`map_overlays.js:97`). **Suggested fix:** replace the obsolete follow-up statement with STORY-032’s outcome and STORY-033’s remaining verification.

- **Low — `docs/reference/surveyor-formula.md:296`: “an unexplored tile shows nothing” does not describe Mirror’s visible panel.** `panel/6` returns `:unexplored`, which LiveView renders as a “Surveyor / Unexplored” card (`map_live.ex:1759`). **Suggested fix:** distinguish the game’s behavior from Mirror’s placeholder.

- **Low — `docs/notes/2026-09-22-repo-recon.md:16,26` and `2026-09-22-momime-source-findings.md:73,100`: historical implementation claims remain misleading without prominent supersession notices.** They describe required MOMIME assets, multiple terrain backends, missing offset defaults and non-rendering tile art. Current code has one LBX backend and configured offsets (`tile_atlas.ex:15`; `config/config.exs:30`). **Suggested fix:** add top-level historical/superseded notices linking current setup and terrain documentation.

- **Low — `docs/notes/2026-09-23-evening-handoff.md:1` and `docs/README.md:3`: the recommended “start here” handoff omits newer implemented features.** Surveyor, settlement grading and fog are now present, while the entrypoint still directs readers to the older summary. **Suggested fix:** point to an updated handoff or explicitly link subsequent updates. The earlier session handoff already has an appropriate superseded notice.

- **Low — `docs/backlog.md:21`: TERRTYPE decoding duplicates STORY-017.** It is still listed as an unpromoted idea, with “if Mirror ever edits terrain,” although raw terrain editing exists. **Suggested fix:** link STORY-017 and clarify that the unfinished work concerns automatic terrain-type painting.

- **Low — `docs/backlog.md:53`: an unresolved tagging decision is assigned to completed STORY-006.** Tile-probe tagging still exists, while rendering uses `TerrainLbx` directly. **Suggested fix:** retain the unresolved decision as its own backlog item or new story rather than assigning it to a closed story.