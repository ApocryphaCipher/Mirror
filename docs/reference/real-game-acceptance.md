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
