# STORY-018: Roads, corruption and resource editing

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** implemented, **real-game check still to do**. The Road, Corruption
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

## Still to check in the real game

- **An enchanted road is written as `0x18`** (both bits), as we believe the
  game's Enchant Road spell leaves it on top of the plain road bit. SAVE1's
  Myrror roads have only `0x10`, which the tool reads as enchanted and clears
  with a click. Save a tile with the tool, load it in DOSBox and compare with a
  tile the game enchanted itself.
- That a road, corruption and a special placed with the tools show up in the real game.
