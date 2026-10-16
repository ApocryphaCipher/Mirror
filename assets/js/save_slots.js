// The save slots' browser half (EPIC-012). The folder handle lives here; the server only
// ever sees a slot's bytes. Chrome and Edge only: the File System Access API.
import {
  filledSlots,
  existingSlotName,
  backupFileName,
  findSetFile,
  withSlotName,
  slotLabel,
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

// The folder belongs to the tab, not to a page: every page that shows slots mounts its own
// hook, and they all use the same handle (and the last scan, so the squares are not grey
// while the next one is read).
let dir = null
let lastScan = null

export const SaveSlots = {
  async mounted() {
    if (!window.showDirectoryPicker) {
      this.pushEvent("slots:unsupported", {})
      return
    }

    this.onClick = (event) => {
      const action = event.target.closest("[data-action]")?.dataset.action
      if (action === "choose-folder") this.choose()
      if (action === "reconnect-folder") this.reconnect()
    }
    this.el.addEventListener("click", this.onClick)

    // The game may have saved while this tab was in the background.
    this.onFocus = () => this.scan()
    window.addEventListener("focus", this.onFocus)

    this.handleEvent("slots:read", ({slot}) => this.readSlot(slot))
    this.handleEvent("slots:write", (job) => this.writeSlot(job))

    if (lastScan) this.pushEvent("slots:folder", lastScan)

    if (!dir) dir = await recall()
    if (dir) {
      if ((await dir.queryPermission({mode: "readwrite"})) === "granted") {
        await this.scan()
      } else {
        this.pushEvent("slots:needs_permission", {name: dir.name})
      }
    }
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
    window.removeEventListener("focus", this.onFocus)
  },

  async choose() {
    try {
      dir = await window.showDirectoryPicker({id: "mirror-game", mode: "readwrite"})
    } catch (_) {
      return // cancelled
    }
    await remember(dir)
    await this.scan()
  },

  async reconnect() {
    try {
      if ((await dir.requestPermission({mode: "readwrite"})) === "granted") {
        await this.scan()
      }
    } catch (error) {
      this.pushEvent("slots:error", {message: `Could not reconnect: ${describe(error)}`})
    }
  },

  async names() {
    const names = []
    for await (const [name, handle] of dir.entries()) {
      if (handle.kind === "file") names.push(name)
    }
    return names
  },

  async scan() {
    if (!dir) return
    try {
      if ((await dir.queryPermission({mode: "readwrite"})) !== "granted") {
        lastScan = null
        this.pushEvent("slots:needs_permission", {name: dir.name})
        return
      }
      lastScan = {name: dir.name, slots: filledSlots(await this.names())}
      this.pushEvent("slots:folder", lastScan)
    } catch (error) {
      this.pushEvent("slots:error", {message: `Could not read the folder: ${describe(error)}`})
    }
  },

  async readSlot(slot) {
    try {
      const name = existingSlotName(await this.names(), slot)
      const file = await (await dir.getFileHandle(name)).getFile()
      const bytes = new Uint8Array(await file.arrayBuffer())
      this.pushEvent("slots:bytes", {slot, data: bytesToBase64(bytes)})
    } catch (error) {
      this.pushEvent("slots:error", {message: `Could not read SAVE${slot}.GAM: ${describe(error)}`})
    }
  },

  // Give the slot a name in the game's list (MAGIC.SET) when it has none, so the Load Game
  // screen does not show it blank. The save is already written, so a problem here is not an
  // error: it just returns null and the slot loads, blank, as before. Returns the name given.
  async nameSlot(slot, names) {
    try {
      const setName = findSetFile(names)
      if (!setName) return null

      const handle = await dir.getFileHandle(setName)
      const bytes = new Uint8Array(await (await handle.getFile()).arrayBuffer())
      const updated = withSlotName(bytes, slot)
      if (!updated) return null

      // the same rule as for saves: the first backup is the file as the game wrote it
      if (!names.includes(`${setName}.mirror-backup`)) {
        const copy = await (await dir.getFileHandle(`${setName}.mirror-backup`, {create: true})).createWritable()
        await copy.write(bytes)
        await copy.close()
      }

      const out = await handle.createWritable()
      await out.write(updated)
      await out.close()
      return slotLabel(slot)
    } catch (_) {
      return null
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
        const old = await (await dir.getFileHandle(name)).getFile()
        const copy = await (await dir.getFileHandle(backupFileName(slot), {create: true})).createWritable()
        await copy.write(await old.arrayBuffer())
        await copy.close()
      }

      const out = await (await dir.getFileHandle(name, {create: true})).createWritable()
      await out.write(base64ToBytes(data))
      await out.close()

      const named = await this.nameSlot(slot, names)

      this.pushEvent("slots:written", {slot, named})
      await this.scan()
    } catch (error) {
      this.pushEvent("slots:error", {
        message: `Could not save SAVE${slot}.GAM, nothing was changed: ${describe(error)}`,
      })
    }
  },
}
