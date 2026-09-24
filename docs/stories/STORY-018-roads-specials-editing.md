# STORY-018: Roads, corruption and resource editing

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** open. The terrain-flags and minerals meanings it needed are now
in [kazzmir-save-layouts.md](../reference/kazzmir-save-layouts.md). It builds on STORY-013's drawing.
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
