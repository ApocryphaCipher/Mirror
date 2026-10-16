// The toast stack (STORY-062): messages from the server (`push_event "toast"`) in the bottom
// right corner. The newest is in front; the older ones show for a moment, then tuck behind it;
// pointing at the stack spreads them out and holds their timers. The stack lives outside the
// LiveView page, so a message survives the page changing under it. The logic is in toast.mjs.
import {add, dismiss, advance, layout, EXPAND_MS} from "./toast.mjs"

const TICK_MS = 250

export function installToasts() {
  const stack = document.createElement("div")
  stack.id = "toast-stack"
  stack.setAttribute("role", "region")
  stack.setAttribute("aria-label", "Notifications")
  stack.setAttribute("aria-live", "polite")
  document.body.appendChild(stack)

  let toasts = []
  let nextId = 1
  let hovering = false
  let expandedUntil = 0
  let timer = null
  const elements = new Map()

  const expanded = () => hovering || performance.now() < expandedUntil

  function build(toast) {
    const el = document.createElement("div")
    el.className = `mirror-toast mirror-toast-${toast.kind}`
    el.dataset.toastId = toast.id
    el.setAttribute("role", toast.kind === "error" ? "alert" : "status")

    const text = document.createElement("p")
    text.className = "mirror-toast-text"
    text.textContent = toast.text
    el.appendChild(text)

    if (toast.action === "undo") {
      const undo = document.createElement("button")
      undo.type = "button"
      undo.className = "mirror-toast-undo"
      undo.textContent = "Undo"
      undo.addEventListener("click", () => {
        // the page's own Undo button does the work, so there is one way to undo
        document.querySelector("#header-undo:not([disabled])")?.click()
        remove(toast.id)
      })
      el.appendChild(undo)
    }

    const close = document.createElement("button")
    close.type = "button"
    close.className = "mirror-toast-close"
    close.setAttribute("aria-label", "Dismiss")
    close.textContent = "×"
    close.addEventListener("click", () => remove(toast.id))
    el.appendChild(close)

    return el
  }

  function render() {
    for (const [id, el] of elements) {
      if (!toasts.some((t) => t.id === id)) {
        el.remove()
        elements.delete(id)
      }
    }
    for (const toast of toasts) {
      if (!elements.has(toast.id)) {
        const el = build(toast)
        elements.set(toast.id, el)
        stack.appendChild(el)
      }
    }

    // natural heights first (height auto), then place every toast
    for (const el of elements.values()) el.style.height = "auto"
    const heights = toasts.map((t) => elements.get(t.id).offsetHeight)
    const open = expanded()

    toasts.forEach((toast, i) => {
      const el = elements.get(toast.id)
      const spot = layout(i, heights, open)
      el.style.height = `${spot.height}px`
      el.style.transform = `translateY(${spot.y}px) scale(${spot.scale})`
      el.style.opacity = spot.opacity
      el.style.zIndex = String(100 - i)
      el.style.pointerEvents = spot.opacity === 0 ? "none" : "auto"
      el.classList.toggle("mirror-toast-tucked", !open && i > 0)
    })

    if (toasts.length === 0 && timer) {
      clearInterval(timer)
      timer = null
    }
  }

  function remove(id) {
    toasts = dismiss(toasts, id)
    render()
  }

  function tick() {
    const before = toasts.length
    toasts = advance(toasts, TICK_MS, hovering)
    // the stack folds up again once the moment is over
    if (toasts.length !== before || (!hovering && performance.now() >= expandedUntil)) render()
  }

  stack.addEventListener("mouseover", () => {
    if (!hovering) {
      hovering = true
      render()
    }
  })
  stack.addEventListener("mouseleave", () => {
    hovering = false
    expandedUntil = performance.now() + 300
    render()
  })

  window.addEventListener("phx:toast", ({detail}) => {
    if (!detail || !detail.text) return
    toasts = add(toasts, detail, nextId++)
    expandedUntil = performance.now() + EXPAND_MS
    render()
    if (!timer) timer = setInterval(tick, TICK_MS)
  })

  // for tests in a browser and for the console
  window.mirrorToasts = {count: () => toasts.length}
}
