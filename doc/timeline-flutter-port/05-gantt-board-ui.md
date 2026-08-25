# The Gantt board (the view in the reference screenshot)

Source: `src/modules/projects/boards/timeline/components/GanttBoard.tsx` — 2463 lines, the largest
file in the feature. This is the component to study hardest for the port, since it's almost entirely
custom layout math and gesture handling rather than framework-provided widgets — which actually makes
it a *good* fit for Flutter's `CustomPainter`/`Stack`/`GestureDetector` model rather than a bad one.

## Overall structure

One rounded card (`border-radius: var(--radius-lg)` = 8px, 1px `--color-border-card` border, white
background) containing two horizontally-adjacent scroll regions that share vertical scroll:

```
┌───────────────────────────────┬──────────────────────────────────────────────┐
│ LEFT: work-item grid (fixed W) │ RIGHT: date chart (horizontally scrollable)   │
│  sticky header (AXIS_H=48px)   │  sticky header (AXIS_H=48px): month/day rows  │
│  one row per GanttRow (40px)   │  one row per GanttRow (40px), absolutely      │
│  own vertical scroll container │  positioned bars/groups on a relative canvas  │
└───────────────────────────────┴──────────────────────────────────────────────┘
```

The two vertical scrollers are synced manually in both directions (`sync('l'|'r')` copies
`scrollTop` from whichever side just scrolled onto the other) — **not** a single shared scroll
container. In Flutter, two `ScrollController`s with a `.jumpTo()` listener on each achieves the same
thing, or a single `CustomScrollView` with the grid and chart as two `SliverToBoxAdapter`s inside one
horizontally-split `Row` if a synced-controller approach feels fragile.

Right pane width = `max(measuredViewportWidth, dateToX(range.end, range) + dayWidth)` — i.e. the chart
canvas is exactly as wide as the date range requires, or the viewport width if that's wider (no dead
space, but also never narrower than the data needs).

## Left grid

Columns, left to right: **Task Summary** (fixed 220px, contains the tree), then any of **Status**
(56px) / **Priority** (65px) / **Start** (78px) / **End** (78px) / **Assignee** (168px) that are
currently visible per user prefs (see `08-toolbar-and-footer.md` for how visibility is toggled).
Column widths are independently drag-resizable (mouse down on a 6px hit-zone at the column's right
edge; `MIN_GRID_COLS` floors: summary 120, status 44, priority 44, startDate/endDate 64, assignee 80).

Each row, regardless of kind:

- **Tree indent + connector lines** (`TreeIndent`): a set of thin (`0.35`-scaled, i.e. sub-pixel)
  vertical rails per ancestor depth, using `treeGuides` from `04-domain-logic.md` to decide whether
  each ancestor rail runs the row's full height (more siblings below) or stops; the *immediate*
  parent's rail always draws a half-height stem plus a horizontal arm into the row's own icon,
  continuing downward only if `treeGuides[depth-1]` is true (tee `┣`) vs stopping (elbow `┗`).
  Indent step = `TREE_INDENT` = 14px per depth level, shared with `ganttRows.ts`.
- An expand/collapse chevron (only if the row has visible children), else an empty 16px spacer slot.
- A type icon: L0/L1/L2 icon asset selected by `depth` (or by `kind==='timeline'`).
- The name, **struck through** if it's a completed Task/Subtask/Subitem *and* the "strikethrough
  completed" preference is on (see `08-toolbar-and-footer.md`); font-weight 600 at depth 0, 500 at
  depth 1, 400 at depth 2+; completed items also get muted text color.
- Then whichever optional columns are visible: a status glyph, a priority glyph (only shown for
  depth ≥ 1 — a Task/Timeline row never shows its own priority, it doesn't have one), start/end dates
  formatted `dd/mm/yyyy`, an assignee chip (avatar + name, or a muted "Unassigned" placeholder).

Clicking anywhere on a row (that isn't the chevron) sets `highlightedRowId` — a **click-only, chart+grid
shared row highlight** that is completely separate from opening the edit drawer (drawer opens only via
right-click → Properties, or via the on-bar "properties" button that appears once a bar is selected in
the chart — see below). Right-clicking a row opens the context menu appropriate to its kind (see
`07-drawers-dialogs-menus.md`).

Empty state (zero rows): centered message "Chưa có task nào trên timeline. Thêm Task đầu tiên để bắt
đầu lập kế hoạch." plus a "+ Thêm Task" button, shown only if an `onAddTask` handler was provided
(i.e. only if the current role can create Tasks).

The "+" button in the Task Summary column header (only rendered if `onAddTask` is provided) opens the
create-Task dialog; it's an icon button with a small colored "+" badge overlay (`WorkLevelPlusBadge`
level 0).

## Right chart header

- **Month band row** (22px): one label per calendar month touched by the range, e.g. `"Aug '26"`;
  label is hidden (but the cell still occupies space) if the band is narrower than 52px.
- **Day band row** (26px): day-of-month numbers, weekend columns tinted (`rgba(9,30,66,0.02)`
  Saturday / `0.035` Sunday in the header, `0.015`/`0.028` in the body — Sunday always slightly
  stronger).
- **"Today" badge**: a small blue pill labeled "Today" pinned above the day column matching real
  calendar today, shown only if today falls inside the current visible range (`todayInRange`).

## Right chart body, back-to-front z-order

1. Day-grid weekend tint bands + a dotted vertical hairline on the right edge of every day cell
   (`repeating-linear-gradient`, 2px dash / 3px gap, using the same dotted style also used by
   `DataTable`'s dashed-divider mode — see `10-design-tokens-and-shared-ui.md`).
2. The vertical "Today" line (1px, primary blue), full height, only if today is in range.
3. SVG dependency arrows (see below).
4. Task-group outline capsules (`buildTaskChartGroups`) — a thin, unfilled, rounded (8px) outline
   around a Task's full visible subtree, only drawn when it has ≥1 visible child row. Padding: 8px
   horizontal beyond the Task's own bar span, 2px vertical inset from top, flush with the bottom of
   the last child row.
5. Subtask-group tinted capsules (`buildSubtaskChartGroups`) — a rounded (12px) filled wash (14%
   opacity of the Subtask's own bar color) with a matching 22%-opacity 1px ring, wrapping a Subtask +
   its Subitems. Same 8px horizontal padding convention as above.
6. A full-width flat highlight band (`rgba(237,242,246,0.5)`) behind whichever row is currently
   `highlightedRowId`.
7. The actual bars/rows, per kind — see next section. (`zIndex: 2`, so always above the wash/highlight
   layers but below floating chrome like the drag tooltip, which uses a React portal to `document.body`
   with `zIndex: 200`.)

### Row rendering by kind

- **`kind: 'timeline'`** (a Task/L0 row): one draggable bar (see gesture section) spanning
  `[startDate, endDate]`, filled via `ganttBarColors(colorIndex, 0, colorHex).fill`, progress strip
  width = `timelineProgressPercent(timeline, tasks)`%. A translucent name label ("inner task" labels)
  for each direct Subtask is drawn *inside* the bar itself, positioned/sized proportionally to that
  Subtask's own date span clipped to the bar's width — purely decorative, not interactive. Any
  Milestone belonging to this Task is drawn as a small diamond-icon button positioned at its date's
  x-coordinate, vertically centered in the row; its glyph color auto-switches between the bar's
  on-bar text color (if the milestone sits visually on top of the bar) and a fixed green (`#00A851`,
  otherwise) with a matching drop-shadow halo for contrast either way. Clicking it selects the
  milestone (opens `MilestoneDrawer`) without triggering the row/bar's own click handlers.
- **`kind: 'milestone'`**: dead branch, returns `null` (see `04-domain-logic.md` — `buildGanttRows`
  never actually produces this kind).
- **`kind: 'task'`, depth ≥ 2 (a Subitem)**: rendered as `SubitemChartTodo`, **not a date bar** — a
  small nested "to-do" row: a tree elbow/tee connector reaching left into its parent Subtask's group,
  a checkbox (checked = completed, click toggles via `onMarkDone`), and the name clamped to 3 lines
  (`-webkit-line-clamp`) inside a width capped to stay within the Subtask's group capsule. Text gets a
  strikethrough only if completed *and* the strikethrough preference is on. This row **cannot be
  dragged** — Subitems have no independent schedule bar, only a status.
- **`kind: 'task'`, depth 1 (a Subtask)**: a `DraggableBar` — same visual bar mechanics as a Task bar,
  colored via `ganttBarColors(colorIndex, 1, colorHex)` (depth 1 = a bit deeper/richer than its
  parent Task's own bar), progress strip = the Subtask's own (rollup-or-manual) `progressPercent`.
  If overdue, an inset left-edge stripe in `GANTT_OVERDUE_MARK` is added to the box-shadow — the fill
  color itself never changes for overdue. Cancelled Subtasks render at 45% opacity.

### Dependency arrows

One `<svg>` layer, one polyline per `TaskDependency` whose both endpoints currently have a visible
row: an elbowed path from the source task's due-date x (plus one day-width) at its row's vertical
center, out horizontally to a midpoint, down/up to the target row's vertical center, then horizontally
into the target task's start-date x — classic "orthogonal connector," arrowhead marker at the end,
`#97a0af` stroke, 1.25px width.

## The drag/resize gesture (`useChartBarGesture`)

This is the trickiest interactive behavior to reproduce faithfully. Applies to Task bars and Subtask
bars (not Subitem to-do rows, not read-only bars).

- **Pointer-events based**, not mouse-events — works for touch too, using `setPointerCapture`-style
  global listeners added on `pointerdown`, removed on `pointerup`/`pointercancel`.
- **Three modes**: `'move'` (grab anywhere on the bar body), `'resize-start'` (drag the left circular
  handle), `'resize-end'` (drag the right circular handle). Handles are 14px circles, only rendered
  once the bar is `selected` (see below) or mid-drag.
- **Move has a 4px dead-zone**: a plain click (down+up with <4px of horizontal movement) does *not*
  count as a drag — it toggles selection instead (see next bullet). Resize handles have no dead-zone;
  any handle drag counts as active immediately (`beginHandleDrag` starts `active: true` right away).
- **Selection vs. drag are the same click**: mouse-down on the bar body remembers whether it was
  already selected (`wasSelected`); if the subsequent pointer-up never crossed the dead-zone, it
  either selects (if it wasn't already) or **deselects** (if it was) — i.e. clicking a selected bar's
  body with no drag closes its handles again. Selection state is lifted to the parent (`GanttBoard`'s
  `chartFocusBarId`), so only one bar's handles are visible at a time. Clicking anywhere outside all
  bars (a `pointerdown` listener on `document` checking `closest('[data-chart-bar="id"]')`) also
  clears the current selection.
- **Live drag delta math** (`applyBarDragDelta(mode, originalLeft, originalWidth, deltaX, dayWidthPx)`):
  - `move`: `left = max(0, originalLeft + dx)`, width unchanged (bar can't be dragged to a negative x,
    but there's no explicit snapping — `dx` is raw pixels, only converted to whole days at commit
    time via `xToDate`, so the bar visually follows the cursor continuously during the drag and only
    "snaps" to day boundaries once released).
  - `resize-end`: `left` unchanged, `width = max(dayWidthPx, originalWidth + dx)` — can't shrink below
    one day.
  - `resize-start`: keeps the *right* edge fixed (`right = originalLeft + originalWidth`), computes a
    new width from `right - max(0, originalLeft + dx)` (floored at one day), then `left = right -
    newWidth`.
- **Commit on pointer-up**: convert the live pixel `left`/`width` back to ISO dates via
  `xToDate(left, range)` and `xToDate(left + width - dayWidth, range)`, swap start/end if the drag
  inverted them, and only call `onCommit(start, due)` if the resulting dates actually differ from
  what the bar started with. `onCommit` is wired to `store.updateTaskDates` (for a Subtask) or
  `store.updateTimeline` (for a Task) — see `03-state-management.md` for the cascading side effects
  each of those triggers.
- **Floating date tooltip** while `dragActive`: a small pill (`ChartBarDateTip`, portaled to
  `document.body`, `position: fixed`, offset +14px/-10px from the pointer) showing `start → due` in
  `dd/mm/yyyy`, with whichever end is *not* being dragged shown at 45% opacity to emphasize which
  edge is actively moving.
- A small circular "Properties" button (20px, floats 18px above the bar's top-left-ish center) appears
  alongside the resize handles once a bar is selected — clicking it opens that item's edit drawer
  without needing a right-click.

## Fullscreen

`useTimelineFullscreenTarget(boardRef)` merges an externally-passed ref (from `ProjectTimelineTab`,
targeting a wrapper div shared across all three views) with a locally-owned ref, so whichever view is
currently mounted becomes the element that gets `element.requestFullscreen()`'d. `GanttBoard` itself
renders a small `TimelineFullscreenExitButton` (bottom-right, 20px square, only visible while
`document.fullscreenElement === targetRef.current`) as an in-canvas affordance, in addition to the
Footer's own fullscreen toggle button (see `08-toolbar-and-footer.md`). Switching away from the
current view (`state.view` changes) force-exits fullscreen via an effect in `ProjectTimelineTab`, so
the Footer's fullscreen-active indicator can never go stale.

## Column visibility & the "strikethrough completed" preference

Both read live from `localStorage`-backed hooks (`useGanttColumnVisibility`,
`useCompletedStrikethrough`, see `08-toolbar-and-footer.md` for where they're toggled) via
`useSyncExternalStore`, so a change anywhere (including in another browser tab) re-renders the board
immediately.
