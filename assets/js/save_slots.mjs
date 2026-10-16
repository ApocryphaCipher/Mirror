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
