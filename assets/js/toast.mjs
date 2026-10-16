// The toast stack's logic (STORY-062), with no DOM in it so it can be tested in Node. toast.js
// draws what this works out.
//
// `toasts` is an array, newest first: index 0 is the front toast, the one at the bottom of the
// stack. A toast is {id, kind, text, action, remaining}; `remaining` is the time it has left.

export const MAX = 5
export const EXPAND_MS = 1000
export const GAP = 8
export const PEEK = 10
export const COLLAPSED_VISIBLE = 3

const TTL = {ok: 5000, info: 5000, error: 10000}

// How long a kind of toast stays, in ms.
export function ttl(kind) {
  return TTL[kind] ?? TTL.info
}

// A new toast goes to the front; the oldest fall off the back past MAX.
export function add(toasts, {kind, text, action}, id) {
  const toast = {id, kind: kind in TTL ? kind : "info", text: String(text), action: action ?? null}
  toast.remaining = ttl(toast.kind)
  return [toast, ...toasts].slice(0, MAX)
}

export function dismiss(toasts, id) {
  return toasts.filter((t) => t.id !== id)
}

// Time passes: each toast has less left, unless the pointer is over the stack, and the ones
// with none left go.
export function advance(toasts, elapsed, paused) {
  if (paused) return toasts
  return toasts
    .map((t) => ({...t, remaining: t.remaining - elapsed}))
    .filter((t) => t.remaining > 0)
}

// Where toast number `index` sits. `heights` are the toasts' own heights, newest first. The
// stack grows upward from the bottom corner. Expanded, every toast shows in full with a gap;
// collapsed, the older ones tuck behind the front one: a little higher, a little smaller, and
// out of sight past COLLAPSED_VISIBLE. `y` is a translateY in px (up is negative).
export function layout(index, heights, expanded) {
  if (expanded) {
    let y = 0
    for (let i = 0; i < index; i++) y -= heights[i] + GAP
    return {y, scale: 1, opacity: 1, height: heights[index]}
  }
  return {
    y: 0 - PEEK * index,
    scale: Math.max(0.8, 1 - 0.05 * index),
    opacity: index < COLLAPSED_VISIBLE ? 1 : 0,
    // an older toast is as tall as the front one while collapsed, so none sticks out above
    height: heights[0],
  }
}
