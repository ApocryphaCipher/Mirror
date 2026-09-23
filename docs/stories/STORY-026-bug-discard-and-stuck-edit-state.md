# STORY-026 (bug): Discard does nothing; edits feel impossible to get rid of

**Parent:** [EPIC-006](../epics/EPIC-006-map-first-ui-and-edit-mode.md)
**Status:** fixed 2026-09-23.
- Discard is a two-step in-page confirmation ("Discard N changes? Yes,
  discard / Cancel"); no native dialog. It was the only `data-confirm` in
  the app.
- Esc leaves edit mode even from the tile box.
- A fresh load or reload always opens in view mode (option **b**); the
  draft is kept and shown by a view-mode notice ("N unsaved changes ·
  Review in edit mode · Discard").
- Found while fixing it: the edit toolbar and notice were in the page flow,
  so when their text re-wrapped (e.g. "1 tile" → "2 tiles changed") the map
  moved under a still pointer and clicks landed on a different tile. Both
  now float over the map.
- Not done: making Discard itself undoable (the in-page confirm made it
  unnecessary for now).
**Size:** small
**Reported by:** [Kevin](https://github.com/KevinAsbury), 2026-09-23: "Discard button does not work. I am
permanently stuck in an edit state with undo/redo and X tiles changed. I
can't exit the mode. Reloading does not clear the edit mode and the changed
tile state persists."

## What's actually happening (checked 2026-09-23)

1. **Discard is silently cancelled.** The button uses LiveView's
   `data-confirm`, which calls `window.confirm()`. **In the Claude desktop
   in-app browser, `confirm()` returns `false` in ~1 ms without showing a
   dialog** (probed directly), so the `discard_edits` event is never sent.
   Stubbing `confirm` shows the call is made:
   `"Discard 115 changed tiles?"`. Regular Chrome would show the dialog,
   but we shouldn't depend on native dialogs.
2. **Done works** (it patched back to `/arcanus` and the toolbar went
   away), but:
   - **Esc is ignored after typing a tile number.** The key handler skips
     events while an input has focus (`isTyping`), and the tile number box
     keeps focus after you type in it.
   - **Reload keeps edit mode** because `?edit=terrain` is in the URL. That
     was intentional, but it reads as "can't leave".
3. **Changed tiles survive reload by design.** They're a draft in the
   server session (ETS). But **outside edit mode nothing says so**, so the
   draft feels like a stuck state you can't see or clear. Today the only
   way out is to Load the save again.

## What to do

1. **Replace `data-confirm` with an in-page confirmation.** Either a
   two-step button (`Discard` → `Discard 115 tiles? Yes / Cancel`, which
   times out back to normal), or make Discard **undoable** and skip the
   confirmation entirely (push the pre-discard planes as one history
   entry). The undoable version is kinder and needs no dialog.
2. **Esc always leaves edit mode**, even from the tile input (blur it
   first). Keep Enter for applying the number.
3. **Make the draft visible in view mode**: a small banner or pill,
   "115 unsaved changes · Edit · Discard · Save as…", whenever the session
   differs from the file.
4. **Decide on reload semantics** (Kevin to confirm):
   - (a) keep the draft across reloads (current), now visible via item 3; or
   - (b) drop `?edit=` from the URL so a reload returns to view mode, still
     keeping the draft.
   Recommendation: (b) plus item 3. Edits aren't lost by accident, and you
   always land in the calm view.
5. **Audit other `data-confirm` uses** in the app for the same in-app
   browser problem.

## Definition of done

- In the in-app browser, Discard clears the changes (count → 0, the map
  redraws) without any native dialog.
- Esc exits edit mode from anywhere, including the tile box.
- With unsaved changes, view mode shows them and offers Discard / Save as.
- LiveView tests cover discard without a confirm and the view-mode banner.

## Workaround until fixed

Load the save again (header path box → **Load**). That resets the session
to the file.
