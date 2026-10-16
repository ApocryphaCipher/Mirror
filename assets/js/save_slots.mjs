// Pure helpers for the save-slot bar (EPIC-012). The browser side lives in save_slots.js.

const SLOT = /^SAVE([1-9])\.GAM$/i

// 3 for "SAVE3.GAM" (any case, like the game on Windows), null for any other name.
export function slotNumber(name) {
  const match = SLOT.exec(String(name))
  return match ? Number(match[1]) : null
}

// The filled slots among a folder's file names, sorted, each once.
export function filledSlots(names) {
  const found = new Set()
  for (const name of names) {
    const n = slotNumber(name)
    if (n !== null) found.add(n)
  }
  return [...found].sort((a, b) => a - b)
}

export function slotFileName(n) {
  return `SAVE${n}.GAM`
}

// The game ignores this name, so the copy never shows up in its Load Game screen.
export function backupFileName(n) {
  return `${slotFileName(n)}.mirror-backup`
}

// The file name in `names` that is slot n, whatever its case ("save3.gam" on a case-folded
// folder), or the standard name when there is none yet.
export function existingSlotName(names, n) {
  return [...names].find((name) => slotNumber(name) === n) ?? slotFileName(n)
}

export function bytesToBase64(bytes) {
  let binary = ""
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

export function base64ToBytes(text) {
  const binary = atob(text)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

// --- the game's slot names (MAGIC.SET) ---
//
// The Load Game screen shows a name for each slot, kept in MAGIC.SET: eight names of 20 bytes
// from offset 0x40, zero padded (checked in four copies of the file; the game's own names stop
// at 18 characters). A save with no name there still loads, but shows up blank.

export const SET_FILE = "MAGIC.SET"
const NAME_START = 0x40
const NAME_SIZE = 20
const NAME_END = NAME_START + 8 * NAME_SIZE
const NAME_MAX = 18

export function slotLabel(slot) {
  return `Mirror Edit Slot ${slot}`
}

// The file name in `names` that is MAGIC.SET, whatever its case, or null.
export function findSetFile(names) {
  return [...names].find((name) => name.toUpperCase() === SET_FILE) ?? null
}

// MAGIC.SET with `label` as the name of `slot`, or null when nothing should change: the slot
// already has a name (the user's, or the game's, is never overwritten), the slot is not one of
// the eight, or the file is too short to be MAGIC.SET (we never invent one).
export function withSlotName(bytes, slot, label = slotLabel(slot)) {
  if (!Number.isInteger(slot) || slot < 1 || slot > 8) return null
  if (bytes.length < NAME_END) return null

  const at = NAME_START + (slot - 1) * NAME_SIZE
  if (bytes[at] !== 0) return null

  const copy = bytes.slice()
  copy.fill(0, at, at + NAME_SIZE)
  for (let i = 0; i < Math.min(label.length, NAME_MAX); i++) copy[at + i] = label.charCodeAt(i) & 0x7f
  return copy
}
