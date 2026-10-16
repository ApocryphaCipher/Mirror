// The save-slot bar's browser half (EPIC-012). The folder handle lives here; the server only
// ever sees a slot's bytes. Chrome and Edge only: the File System Access API.
import {
  filledSlots,
  existingSlotName,
  backupFileName,
  bytesToBase64,
  base64ToBytes,
} from "./save_slots.mjs"

const DB = "mirror"
const STORE = "handles"
const KEY = "gameFolder"

// IndexedDB keeps the folder handle between visits. Every call may fail (private windows,
// blocked storage), and the bar still works without it: the user just picks again.
function idb() {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open(DB, 1)
    open.onupgradeneeded = () => open.result.createObjectStore(STORE)
    open.onsuccess = () => resolve(open.result)
    open.onerror = () => reject(open.error)
  })
}

async function remember(handle) {
  try {
    const db = await idb()
    db.transaction(STORE, "readwrite").objectStore(STORE).put(handle, KEY)
  } catch (_) {}
}

async function recall() {
  try {
    const db = await idb()
    return await new Promise((resolve) => {
      const get = db.transaction(STORE).objectStore(STORE).get(KEY)
      get.onsuccess = () => resolve(get.result ?? null)
      get.onerror = () => resolve(null)
    })
  } catch (_) {
    return null
  }
}

const describe = (error) => (error && error.message) || String(error)

export const SaveSlots = {
  async mounted() {
    if (!window.showDirectoryPicker) {
      this.pushEvent("unsupported", {})
      return
    }

    this.dir = null

    this.el.addEventListener("click", (event) => {
      const action = event.target.closest("[data-action]")?.dataset.action
      if (action === "choose-folder") this.choose()
      if (action === "reconnect-folder") this.reconnect()
    })

    this.handleEvent("read_slot", ({slot}) => this.readSlot(slot))
    this.handleEvent("write_slot", (job) => this.writeSlot(job))

    // The game may have saved while this tab was in the background.
    window.addEventListener("focus", () => this.scan())

    const saved = await recall()
    if (saved) {
      this.dir = saved
      if ((await saved.queryPermission({mode: "readwrite"})) === "granted") {
        await this.scan()
      } else {
        this.pushEvent("needs_permission", {name: saved.name})
      }
    }
  },

  // Sticky: the bar survives page changes, so the hook can be re-attached after a reconnect.
  async reconnected() {
    if (this.dir) await this.scan()
  },

  async choose() {
    try {
      this.dir = await window.showDirectoryPicker({id: "mirror-game", mode: "readwrite"})
    } catch (_) {
      return // cancelled
    }
    await remember(this.dir)
    await this.scan()
  },

  async reconnect() {
    try {
      if ((await this.dir.requestPermission({mode: "readwrite"})) === "granted") {
        await this.scan()
      }
    } catch (error) {
      this.pushEvent("slot_error", {message: `Could not reconnect: ${describe(error)}`})
    }
  },

  async names() {
    const names = []
    for await (const [name, handle] of this.dir.entries()) {
      if (handle.kind === "file") names.push(name)
    }
    return names
  },

  async scan() {
    if (!this.dir) return
    try {
      if ((await this.dir.queryPermission({mode: "readwrite"})) !== "granted") {
        this.pushEvent("needs_permission", {name: this.dir.name})
        return
      }
      this.pushEvent("folder", {name: this.dir.name, slots: filledSlots(await this.names())})
    } catch (error) {
      this.pushEvent("slot_error", {message: `Could not read the folder: ${describe(error)}`})
    }
  },

  async readSlot(slot) {
    try {
      const name = existingSlotName(await this.names(), slot)
      const file = await (await this.dir.getFileHandle(name)).getFile()
      const bytes = new Uint8Array(await file.arrayBuffer())
      this.pushEvent("slot_bytes", {slot, data: bytesToBase64(bytes)})
    } catch (error) {
      this.pushEvent("slot_error", {message: `Could not read SAVE${slot}.GAM: ${describe(error)}`})
    }
  },

  // Backup first, and only if there is none yet: the first backup is the save as the game
  // wrote it, which is the one worth keeping. A failed backup stops the save. A writable
  // stream only replaces the file when it is closed, so a crash cannot leave half a save.
  async writeSlot({slot, data, backup}) {
    try {
      const names = await this.names()
      const name = existingSlotName(names, slot)

      if (backup && names.includes(name) && !names.includes(backupFileName(slot))) {
        const old = await (await this.dir.getFileHandle(name)).getFile()
        const copy = await (await this.dir.getFileHandle(backupFileName(slot), {create: true})).createWritable()
        await copy.write(await old.arrayBuffer())
        await copy.close()
      }

      const out = await (await this.dir.getFileHandle(name, {create: true})).createWritable()
      await out.write(base64ToBytes(data))
      await out.close()

      this.pushEvent("slot_written", {slot})
      await this.scan()
    } catch (error) {
      this.pushEvent("slot_error", {
        message: `Could not save SAVE${slot}.GAM, nothing was changed: ${describe(error)}`,
      })
    }
  },
}
