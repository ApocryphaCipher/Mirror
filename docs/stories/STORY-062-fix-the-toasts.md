# STORY-062: Fix the toast messages

**Parent:** none (UI; relates to [EPIC-012](../epics/EPIC-012-open-and-save-from-the-browser.md), whose Save shows one)
**Status:** open (2026-10-15)
**Size:** small to medium
**Raised by:** [Kevin](https://github.com/KevinAsbury), 2026-10-15

## The problems (Kevin)

- Toasts never go away; they stay until clicked.
- New toasts end up **under** old ones that have not faded.
- Stacking should be: the newest on top, the older ones slide down to make room for a moment, then everything collapses into a tidy stack.

## What we have now

Home-rolled, no third-party package. `MirrorWeb.CoreComponents.flash/1` (`lib/mirror_web/components/core_components.ex`) is Phoenix's generated flash component with daisyUI's `toast` class, and
`Layouts.flash_group/1` renders **one slot per kind** (info and error). So at most two toasts exist, each a fixed-position box in the same top-right corner (they overlap), a new message replaces the old one of its kind
(nothing stacks), and nothing ever hides it except a click. About 14 `put_flash` calls across the LiveViews, plus the map page's own inline notices (not toasts; leave them).

## The plan (a suggestion, Kevin to decide)

Keep it home-rolled: a small JS hook plus a little CSS (about 60 lines), no dependency (AGENTS.md section 4: none without Kevin's approval).

- **A queue, not two slots.** The server sends each message as an event (`push_event(socket, "toast", %{kind, text})`, via one helper, `MirrorWeb.Toast.push/3`), and the page keeps a list. `put_flash` calls move to the helper;
  a flash still on the page at load (a redirect carries one) is turned into a toast by the same hook.
- **Newest on top.** A new toast enters at the top; the ones below slide down to make room, then after a moment (about 1 s) the stack collapses so older toasts peek out underneath, smaller, and expand again while the pointer is over the stack.
- **Fade after a time:** info about 5 s, errors about 10 s, paused while the pointer is over the stack; a click dismisses one. A cap on the stack (say 5; the oldest go first).
- Respect "reduce motion" (no slide, just fade).
- It lives in the page layout and **must not shift the map** (AGENTS.md section 8): it is an overlay.

## Third-party options (not tried)

Hex has toast libraries for LiveView (for example `live_toast`) and there are JS toast libraries. None is used here. I have not tried them, so I do not know how they fit with this project's Tailwind 4 and daisyUI setup or how they behave on
the slide-then-collapse effect. A dependency also brings upgrades to track for a feature that is about 60 lines to write. *Recommendation:* home-rolled; look at a package only if the hook turns out harder than it looks.

## Definition of done

- Pure queue logic (add, expire, cap, order) in `assets/js/toast.mjs` with Node tests (`assets/test/`).
- A LiveView test that a `put_flash`-style event reaches the page as a toast event, and that a redirect's flash still shows.
- Checked in Chrome: toasts fade, newest on top, slide-then-collapse, hover expands, the map does not move.
