import test from "node:test"
import assert from "node:assert/strict"
import {MAX, add, dismiss, advance, layout, ttl, GAP, PEEK} from "../js/toast.mjs"

const make = (n, kind = "ok") => {
  let toasts = []
  for (let i = 1; i <= n; i++) toasts = add(toasts, {kind, text: `t${i}`}, i)
  return toasts
}

test("a new toast goes to the front", () => {
  const toasts = make(3)
  assert.deepEqual(toasts.map((t) => t.text), ["t3", "t2", "t1"])
})

test("the oldest fall off past the cap", () => {
  const toasts = make(MAX + 2)
  assert.equal(toasts.length, MAX)
  assert.equal(toasts[0].text, `t${MAX + 2}`)
  assert.equal(toasts.at(-1).text, "t3")
})

test("an unknown kind is a plain info toast; text is always a string", () => {
  const [t] = add([], {kind: "weird", text: 42}, 1)
  assert.equal(t.kind, "info")
  assert.equal(t.text, "42")
  assert.equal(t.action, null)
})

test("errors stay longer than the rest", () => {
  assert.ok(ttl("error") > ttl("ok"))
  assert.equal(ttl("ok"), ttl("info"))
})

test("dismiss removes one toast and keeps the order", () => {
  assert.deepEqual(dismiss(make(3), 2).map((t) => t.text), ["t3", "t1"])
  assert.equal(dismiss(make(2), 99).length, 2)
})

test("time takes toasts away when theirs is up, and only then", () => {
  let toasts = add(make(1, "error"), {kind: "ok", text: "new"}, 9)
  toasts = advance(toasts, ttl("ok") - 1, false)
  assert.equal(toasts.length, 2)
  toasts = advance(toasts, 2, false)
  assert.deepEqual(toasts.map((t) => t.text), ["t1"]) // the ok one is gone, the error is not
  toasts = advance(toasts, ttl("error"), false)
  assert.deepEqual(toasts, [])
})

test("while the pointer is over the stack nothing expires", () => {
  const toasts = make(2)
  assert.deepEqual(advance(toasts, 10 ** 6, true), toasts)
})

test("advance does not change the toasts it is given", () => {
  const toasts = make(1)
  const copy = JSON.parse(JSON.stringify(toasts))
  advance(toasts, 100, false)
  assert.deepEqual(toasts, copy)
})

test("expanded: each older toast sits one toast and one gap higher than the one before", () => {
  const heights = [40, 60, 50]
  assert.equal(layout(0, heights, true).y, 0)
  assert.equal(layout(1, heights, true).y, -(40 + GAP))
  assert.equal(layout(2, heights, true).y, -(40 + GAP + 60 + GAP))
  assert.deepEqual([layout(2, heights, true).scale, layout(2, heights, true).opacity], [1, 1])
  assert.equal(layout(1, heights, true).height, 60)
})

test("collapsed: older toasts tuck behind the front one, smaller, and vanish past three", () => {
  const heights = [40, 60, 50, 30, 30]
  const l = (i) => layout(i, heights, false)
  assert.equal(l(0).y, 0)
  assert.equal(l(1).y, -PEEK)
  assert.ok(l(1).scale < 1 && l(2).scale < l(1).scale)
  assert.equal(l(2).opacity, 1)
  assert.equal(l(3).opacity, 0)
  // as tall as the front toast, so none sticks out above it
  for (let i = 0; i < 5; i++) assert.equal(l(i).height, 40)
})

test("the scale never gets silly", () => {
  assert.ok(layout(40, new Array(41).fill(10), false).scale >= 0.8)
})
