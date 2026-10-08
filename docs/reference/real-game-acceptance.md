# Checking edits against the real game

The real Master of Magic running in DOSBox is the ultimate arbiter of whether an edited save is valid. Every editing story must be signed off by successfully loading a hand-edited save into the real game.

## Environment

This procedure relies on the standard GOG install on Kevin's machine:
- **DOSBox version:** DOSBox 0.74-3 at `/Applications/dosbox.app`
- **Mounts:** `~/DOS` mounted as `C:`
- **Game directory:** `~/DOS/MAGIC` (the installed game)

*Note: This is the plain end-user DOSBox + GOG install flow. Do not confuse this with the separate DOSBox Staging live-RAM tooling documented in `docs/reference/live-ram-map.md`, which is a research tool.*

## Procedure

This procedure requires a human at the keyboard. DOSBox will not run headless, so this step cannot be automated.

1. **Prepare the edit:** Create a single hand-edited save that tests your feature (e.g., modifying one tile).
2. **Find a free slot:** Check with Kevin which save slots (1-9) are free, or backup an existing slot. Never overwrite an in-progress save.
3. **Copy the save:** Place your edited save into `~/DOS/MAGIC/SAVEn.GAM`, where `n` is the chosen slot.
4. **Launch DOSBox:** Open `/Applications/dosbox.app`.
5. **Start the game:** Inside DOSBox, type:
   ```dos
   C:
   cd MAGIC
   magic
   ```
6. **Load the save:** From the game's main menu, select "Load Game" and choose the slot you replaced.
7. **Verify:** Confirm the game accepts the save (no corruption error during load) and that the edited content matches what was intended (e.g., the modified tile picture appears in the correct place on the map).

Use this as the manual sign-off step for each editing story.

## With the DOSBox Staging fork (what the 2026-10 checks used)

The plain flow above is enough to sign a story off. The research fork
(`scripts/live_session.sh start`, see [live-ram-map.md](live-ram-map.md)) does the same
load and adds a read-only API, which turns "it loaded" into evidence:

1. **Before writing a slot, back up what is in it**, outside the game folder:
   `~/.mirror/dev/DOSbox/backups/` (name it for the game and the date, e.g.
   `SAVE4-tauron-2026-10-04.GAM`). Slots 4, 5 and 6 held other saves (two other wizards' games and an
   older one), and were overwritten with test saves on 2026-10-06/07 after this was done. Slots 1-8 only; slot 9 is the autosave.
2. **Build the test save from the same code path the app uses** (`Mirror.Editor` and
   `Mirror.SaveFile.write/3`), so the check covers Mirror's own bytes, not a hand edit. Diff it
   against its source and confirm that only the intended bytes differ. Pick a source that has
   what the test needs: SAVE3 is already fully explored, so revealing it changes nothing.
3. **Load it with Load Game**, then read the same bytes back from RAM
   (`scripts/verify_loaded_save.py FILE`, or read the block by hand: terrain flags `0x773A0`, explored
   `0x78690`, nodes `0x85FE0`, minerals `0x760B0`). If RAM equals the file, the game accepted it unchanged.
4. **Look at the screen, in numbers where you can.** Take raw screenshots through the API
   (`POST /api/v1/capture/screenshot?inline=1`, a frame about every 30 ms) and compare the tile
   pixels with the sprite decoded by Mirror: an exact match on every opaque pixel is stronger than
   "looks right". For anything that moves, take a burst and measure the step and the order
   (the sparkle ripple and the 0.6 s step were found this way).
5. **Take a checkpoint** (`scripts/live_session.sh cp "name" "note"`) so the bytes and the screenshot
   are kept together in the Evi vault, and name its collection in the story.
6. **A person still has to look** at what an API can't judge (does it look right, does a Surveyor
   panel say "Unexplored"). Say what was and wasn't seen in the story; "nobody has watched it
   animate" is a fine thing to write.

