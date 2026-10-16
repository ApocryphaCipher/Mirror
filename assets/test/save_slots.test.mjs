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
