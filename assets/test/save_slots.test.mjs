import test from "node:test"
import assert from "node:assert/strict"
import {
  slotNumber,
  filledSlots,
  slotFileName,
  backupFileName,
  existingSlotName,
  bytesToBase64,
  base64ToBytes,
} from "../js/save_slots.mjs"

test("slotNumber accepts SAVE1.GAM to SAVE9.GAM in any case and nothing else", () => {
  assert.equal(slotNumber("SAVE1.GAM"), 1)
  assert.equal(slotNumber("save9.gam"), 9)
  assert.equal(slotNumber("Save4.Gam"), 4)
  for (const name of ["SAVE0.GAM", "SAVE10.GAM", "SAVE1.GAM.mirror-backup", "SAVE1.GAM.bak", "MAGIC.SET", "xSAVE1.GAM", "", null, undefined]) {
    assert.equal(slotNumber(name), null, String(name))
  }
})

test("filledSlots lists each slot once, sorted, ignoring other files", () => {
  const names = ["SAVE3.GAM", "MAGIC.SET", "save1.gam", "SAVE3.GAM", "SAVE9.GAM", "SAVE2.GAM.mirror-backup", "WIZARDS.LBX"]
  assert.deepEqual(filledSlots(names), [1, 3, 9])
  assert.deepEqual(filledSlots([]), [])
})

test("file names", () => {
  assert.equal(slotFileName(5), "SAVE5.GAM")
  assert.equal(backupFileName(5), "SAVE5.GAM.mirror-backup")
})

test("existingSlotName keeps the case already in the folder", () => {
  assert.equal(existingSlotName(["save3.gam", "MAGIC.SET"], 3), "save3.gam")
  assert.equal(existingSlotName(["MAGIC.SET"], 3), "SAVE3.GAM")
})

test("base64 round trip, including a size past one chunk", () => {
  const bytes = new Uint8Array(123_300)
  for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 31 + 7) & 0xff
  assert.deepEqual(base64ToBytes(bytesToBase64(bytes)), bytes)
  assert.equal(bytesToBase64(new Uint8Array([72, 105])), "SGk=")
})

import {slotLabel, findSetFile, withSlotName} from "../js/save_slots.mjs"

// a MAGIC.SET-shaped file: 466 bytes, a settings header, then eight 20-byte names
function magicSet(names) {
  const bytes = new Uint8Array(466)
  bytes.fill(1, 0, 0x40)
  names.forEach((name, k) => {
    for (let i = 0; i < name.length; i++) bytes[0x40 + k * 20 + i] = name.charCodeAt(i)
  })
  return bytes
}

const nameAt = (bytes, slot) => {
  const at = 0x40 + (slot - 1) * 20
  const end = bytes.indexOf(0, at)
  return String.fromCharCode(...bytes.subarray(at, end))
}

test("the label fits the game's 18 characters for every slot", () => {
  for (let slot = 1; slot <= 8; slot++) assert.ok(slotLabel(slot).length <= 18)
  assert.equal(slotLabel(3), "Mirror Edit Slot 3")
})

test("findSetFile ignores case and other files", () => {
  assert.equal(findSetFile(["SAVE1.GAM", "magic.set"]), "magic.set")
  assert.equal(findSetFile(["SAVE1.GAM", "MAGIC.SET.mirror-backup"]), null)
})

test("a blank slot name gets the label and nothing else changes", () => {
  const before = magicSet(["Jafar - Hacker", "Jafar - Player"])
  const after = withSlotName(before, 3)
  assert.equal(nameAt(after, 3), "Mirror Edit Slot 3")
  assert.equal(after.length, before.length)
  const changed = [...after].flatMap((b, i) => (b !== before[i] ? [i] : []))
  assert.ok(changed.every((i) => i >= 0x68 && i < 0x7c), "only slot 3's 20 bytes differ")
  assert.equal(nameAt(after, 1), "Jafar - Hacker")
})

test("a slot that already has a name is left alone", () => {
  assert.equal(withSlotName(magicSet(["Jafar - Hacker"]), 1), null)
  assert.equal(withSlotName(magicSet(["x", "y", "SAVE 3"]), 3), null)
})

test("the autosave, a bad slot, and a file too short to be MAGIC.SET change nothing", () => {
  const blank = magicSet([])
  for (const slot of [0, 9, 2.5, "3", null]) assert.equal(withSlotName(blank, slot), null, String(slot))
  assert.equal(withSlotName(new Uint8Array(100), 3), null)
  assert.equal(withSlotName(new Uint8Array(0), 3), null)
})

test("the input is not modified", () => {
  const before = magicSet([])
  const copy = before.slice()
  withSlotName(before, 2)
  assert.deepEqual(before, copy)
})
