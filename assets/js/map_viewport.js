// Pan/zoom container for the map canvas on the map pages (view mode).
//
// The canvas keeps rendering at its fixed resolution; this hook only applies
// a CSS transform, so zooming never re-renders. `image-rendering: pixelated`
// keeps tiles crisp, and MapCanvas's hover picking keeps working because it
// reads the transformed bounding rect.

const ZOOM_LEVELS = [0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4]
const DRAG_THRESHOLD_PX = 3
const MIN_VISIBLE_PX = 120

const MapViewport = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    this.zoomLabel = this.el.querySelector("[data-zoom-label]")
    this.scale = 1
    this.tx = 0
    this.ty = 0
    this.userZoomed = false
    this.drag = null

    this.canvas.style.transformOrigin = "0 0"
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

  onPointerDown(event) {
    if (event.button !== 0) return
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
    this.canvas.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`
    if (this.zoomLabel) this.zoomLabel.textContent = `${Math.round(this.scale * 100)}%`
  },
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

export {MapViewport}
