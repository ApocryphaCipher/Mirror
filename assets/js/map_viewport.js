// Pan/zoom container for the map canvas on the map pages (view mode).
//
// The canvas keeps rendering at its fixed resolution; this hook only applies
// a CSS transform, so zooming never re-renders. The transform goes on the
// `[data-map-stage]` wrapper when there is one, so the overlay canvas stacked
// over the terrain (map_overlays.js) moves with it. `image-rendering: pixelated`
// keeps tiles crisp, and MapCanvas's hover picking keeps working because it
// reads the transformed bounding rect.

const ZOOM_LEVELS = [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4]
const DRAG_THRESHOLD_PX = 3
const MIN_VISIBLE_PX = 120

const MapViewport = {
  mounted() {
    this.canvas = this.el.querySelector("#map-canvas") || this.el.querySelector("canvas")
    this.stage = this.el.querySelector("[data-map-stage]") || this.canvas
    this.zoomLabel = this.el.querySelector("[data-zoom-label]")
    this.scale = 1
    this.tx = 0
    this.ty = 0
    this.userZoomed = false
    this.drag = null
    this.editing = this.canvas.dataset.interaction === "edit"
    window.__mirrorSpaceHeld = false

    this.stage.style.transformOrigin = "0 0"
    this.stage.querySelectorAll("canvas").forEach(c => (c.style.imageRendering = "pixelated"))
    this.canvas.style.imageRendering = "pixelated"

    this.onResize = () => {
      this.fitHeight()
      if (this.userZoomed) {
        this.clampAndApply()
      } else {
        this.fit()
      }
    }
    window.addEventListener("resize", this.onResize)

    // Edit mode: Space held turns left-drag back into panning; Esc finishes.
    this.onKeyDown = event => {
      // Esc always finishes editing, even from the tile number box (STORY-026).
      if (event.key === "Escape" && this.editing) {
        if (isTyping(event)) event.target.blur()
        this.pushEvent("exit_edit", {})
        return
      }
      if (isTyping(event)) return
      if (event.code === "Space" && this.editing) {
        window.__mirrorSpaceHeld = true
        this.el.style.cursor = "grab"
        event.preventDefault()
      }
    }
    this.onKeyUp = event => {
      if (event.code !== "Space") return
      window.__mirrorSpaceHeld = false
      this.el.style.cursor = ""
    }
    window.addEventListener("keydown", this.onKeyDown)
    window.addEventListener("keyup", this.onKeyUp)

    this.handleEvent("edit_mode", payload => {
      this.editing = payload.mode === "edit"
    })

    this.el.addEventListener("wheel", event => this.onWheel(event), {passive: false})
    this.el.addEventListener("pointerdown", event => this.onPointerDown(event))
    this.el.addEventListener("pointermove", event => this.onPointerMove(event))
    this.el.addEventListener("pointerup", event => this.onPointerUp(event))
    this.el.addEventListener("pointercancel", event => this.onPointerUp(event))
    this.el.addEventListener("dblclick", () => this.fit())

    this.el.querySelectorAll("[data-zoom]").forEach(button => {
      button.addEventListener("pointerdown", event => event.stopPropagation())
      button.addEventListener("click", () => {
        const action = button.dataset.zoom
        if (action === "fit") return this.fit()
        this.zoomBy(action === "in" ? 1 : -1, this.viewportCenter())
      })
    })

    this.fitHeight()
    this.fit()
  },

  destroyed() {
    window.removeEventListener("resize", this.onResize)
    window.removeEventListener("keydown", this.onKeyDown)
    window.removeEventListener("keyup", this.onKeyUp)
    window.__mirrorSpaceHeld = false
  },

  // Fill the window below the viewport's top edge, whatever sits above it.
  fitHeight() {
    const top = this.el.getBoundingClientRect().top + window.scrollY
    this.el.style.height = `${Math.max(200, window.innerHeight - top)}px`
  },

  // CSS size MapCanvas gives the canvas (tiles × tile size). Read from the
  // data attributes rather than measured: this hook can mount before
  // MapCanvas has sized the canvas.
  mapSize() {
    const d = this.canvas.dataset
    const tile = parseInt(d.tileSize || "12", 10)
    return {
      width: parseInt(d.mapWidth || "60", 10) * tile,
      height: parseInt(d.mapHeight || "40", 10) * tile,
    }
  },

  viewportCenter() {
    return {x: this.el.clientWidth / 2, y: this.el.clientHeight / 2}
  },

  fit() {
    const {width, height} = this.mapSize()
    if (!width || !height) return
    this.scale = Math.min(this.el.clientWidth / width, this.el.clientHeight / height)
    this.tx = (this.el.clientWidth - width * this.scale) / 2
    this.ty = (this.el.clientHeight - height * this.scale) / 2
    this.userZoomed = false
    this.apply()
  },

  // Step to the next zoom level up/down, keeping the point under `anchor`
  // (viewport coordinates) fixed on screen.
  zoomBy(direction, anchor) {
    const next =
      direction > 0
        ? ZOOM_LEVELS.find(level => level > this.scale + 1e-3)
        : [...ZOOM_LEVELS].reverse().find(level => level < this.scale - 1e-3)
    if (!next) return

    const mapX = (anchor.x - this.tx) / this.scale
    const mapY = (anchor.y - this.ty) / this.scale
    this.scale = next
    this.tx = anchor.x - mapX * next
    this.ty = anchor.y - mapY * next
    this.userZoomed = true
    this.clampAndApply()
  },

  onWheel(event) {
    event.preventDefault()
    const rect = this.el.getBoundingClientRect()
    this.zoomBy(event.deltaY < 0 ? 1 : -1, {x: event.clientX - rect.left, y: event.clientY - rect.top})
  },

  // View mode: left-drag pans. Edit mode: left is the brush, so pan with
  // middle-drag or space+left-drag.
  onPointerDown(event) {
    const pans =
      event.button === 1 || (event.button === 0 && (!this.editing || window.__mirrorSpaceHeld))
    if (!pans) return
    event.preventDefault()
    this.drag = {x: event.clientX, y: event.clientY, tx: this.tx, ty: this.ty, moved: false}
    this.el.setPointerCapture(event.pointerId)
  },

  onPointerMove(event) {
    if (!this.drag) return
    const dx = event.clientX - this.drag.x
    const dy = event.clientY - this.drag.y
    if (!this.drag.moved && Math.hypot(dx, dy) < DRAG_THRESHOLD_PX) return
    this.drag.moved = true
    this.el.style.cursor = "grabbing"
    this.tx = this.drag.tx + dx
    this.ty = this.drag.ty + dy
    this.userZoomed = true
    this.clampAndApply()
  },

  onPointerUp(event) {
    if (!this.drag) return
    this.drag = null
    this.el.style.cursor = ""
    if (this.el.hasPointerCapture(event.pointerId)) this.el.releasePointerCapture(event.pointerId)
  },

  // Keep at least a strip of map on screen; centre an axis that fits.
  clampAndApply() {
    const {width, height} = this.mapSize()
    const vw = this.el.clientWidth
    const vh = this.el.clientHeight
    const w = width * this.scale
    const h = height * this.scale

    this.tx = w <= vw ? (vw - w) / 2 : clamp(this.tx, MIN_VISIBLE_PX - w, vw - MIN_VISIBLE_PX)
    this.ty = h <= vh ? (vh - h) / 2 : clamp(this.ty, MIN_VISIBLE_PX - h, vh - MIN_VISIBLE_PX)
    this.apply()
  },

  apply() {
    this.stage.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`
    if (this.zoomLabel) this.zoomLabel.textContent = `${Math.round(this.scale * 100)}%`
  },
}

function isTyping(event) {
  const tag = event.target?.tagName
  return tag === "INPUT" || tag === "TEXTAREA" || event.target?.isContentEditable
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

export {MapViewport}
