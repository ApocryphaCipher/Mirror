# STORY-037: Reveal all: make every tile explored for the player

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open, nice-to-have
**Size:** small
**Requested by:** [Kevin](https://github.com/KevinAsbury), 2026-09-24

## Goal

An edit action, **Reveal all**, that marks every tile as explored for the
player, so the game shows the whole map when the save is loaded. This is
the save-file version of the Nature Awareness / Earth Lore effect, and
what MMS called "reveal all".

It differs from its neighbours:
- [STORY-036](STORY-036-fog-of-war-layer.md) only *draws* the fog in
  Mirror; it never changes the save.
- [STORY-029](STORY-029-safe-editing-see-everything.md)'s "show
  everything" is about Mirror's view while editing.

This one **edits the save**.

## What's known

The explored map is one byte per tile at `0x014814`, Arcanus then Myrror;
0 means unexplored and 15 fully explored
([wizard-record-and-exploration.md](../reference/wizard-record-and-exploration.md#explored-map-fog-of-war)).
Setting all 4,800 bytes to 15 is how the "God mode" save lost its fog:
the game loaded it and showed the whole map, on both planes. So the edit
itself is checked.

## Design

- **The action:** a button in edit mode, "Reveal all", for the current
  plane or both planes (pick one; both is what MMS did). It writes 15 to
  every tile of the `exploration` layer.
- **Undo:** it's one entry on the undo stack, like a stroke, so it can be
  undone and discarded, and the unsaved-edits counter counts it.
- **Saving:** it goes through the usual **Save as** (AGENTS.md §9: never
  overwrite the loaded save).
- **Redraw:** the fog layer (STORY-036) redraws at once. It's pushed after
  edits.
- *Optional:* "Reveal around…" (a radius around a tile or a city) could
  share the code later. It isn't part of this story.

## Open questions

- **Does exploring change anything else the game keeps?** Encounter
  sites' "looked at" flag, for example, is separate (see
  `Mirror.SaveFile.Sites`), and should stay unchanged. Check in the game
  that a revealed lair still says "Unexplored" in the Surveyor.
- **Does the game recompute anything from the explored map on load**
  (the mini-map, AI knowledge)? The God-mode save suggests it just shows
  it, but check the mini-map once.

## Done when

- In edit mode, Reveal all sets every tile of the chosen plane(s) to 15.
  The fog layer clears, and undo brings the fog back.
- Save as, then load in the game (DOSBox): the whole map is visible, and
  a lair that was never looked at still says "Unexplored".
- A test covers it: after the action, the exploration layer is all 15;
  after undo, it's the original bytes.
