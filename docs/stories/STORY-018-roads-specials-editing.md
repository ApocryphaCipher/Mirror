# STORY-018: Roads, corruption and resource editing

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** Done (2026-10-06): checked in the running game, the bytes and what the player
sees. Roads on ocean tiles ("bridges") are allowed but were not tried in the game. The Road, Corruption
and Special tools are in the edit toolbar (`MirrorWeb.RoadTool`,
`MirrorWeb.MapLive`); the meanings they use are in
[kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md). It builds on
STORY-013's drawing.
**Size:** small–medium

## What to do

- **Roads & specials** edit layer: click to cycle none → road → enchanted
  road; corruption on/off; a separate tool cycles resources (gold, game,
  mithril…).
- Allow roads on ocean (the game treats them as bridges, per MMS docs).
- Road pieces redraw from neighbours automatically (same logic STORY-013
  uses to render them).

## Definition of done

- Edits show immediately, survive Save as, and appear the same in the real
  game.

## What was built

- **🛣️ Road:** a click steps a tile none → road (`0x08`) → enchanted road
  (`0x18`) → none; right-click or shift-click steps back. Any tile can take a
  road, water included (bridges).
- **☠️ Corruption:** a click flips the `0x20` bit.
- **💎 Special:** a dropdown of the eleven values the game uses (ores, gems,
  crystals, wild game, nightshade); a click places it, right-click or
  shift-click removes it.
- Each click is one undo step and keeps the other bits of the byte (corruption
  stays when a road is cycled, and the other way round). Road pieces redraw from
  their neighbours because the overlay is rebuilt from the flags after every
  edit. Edits are saved by Save as like any other.

## Checked in the real game (2026-10-06)

A save was built from SAVE3 with a road at (32,21), an enchanted road at
(33,21), corruption at (35,18) and mithril at (36,18), all written with the
tools' own values, plus Freya given one Sorcery book and Enchant Road known.
Loaded in the DOSBox fork, then Enchant Road cast (checkpoint 70, collection
`mom-live-2026-10-06`):

- **The game accepts the save and keeps every byte:** `0x08`, `0x18`, `0x20`
  and minerals `6` were in RAM exactly as written.
- **Enchant Road writes `0x18`** (road bit kept, `0x10` added): five connected
  road tiles went `0x08` → `0x18`, including the tool-made road at (32,21),
  which the game treated as part of the network. That is the value the tool
  writes. SAVE3's 13 Myrror road tiles are `0x18` too (an earlier note here said
  `0x10`; it was wrong).

- **On screen** (12 raw screenshots, 0.25 s apart, tile pixels compared):
  - the tool-written enchanted road at (33,21) and the tool road the spell
    enchanted at (32,21) flicker in the same on/off pattern as the game's own
    enchanted roads at (31,22) and (31,23);
  - the plain road at (31,20) and a grass control tile never change;
  - the corruption at (35,18) is drawn as the game's dark corrupted tile, and
    the mithril at (36,18) as a sparkling ore sprite.

## Still to check in the real game

- Roads on ocean tiles (bridges) were not tried.
