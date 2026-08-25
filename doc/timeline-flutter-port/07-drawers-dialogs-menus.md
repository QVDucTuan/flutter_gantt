# Drawers, create dialogs, context menus, and small glyph components

## Shared drawer shell (`TaskDrawer.tsx` → `DrawerShell`)

Every edit surface (`TimelineDrawer`, `TaskDrawer`, `MilestoneDrawer`) is a right-side slide-in panel,
not a modal centered dialog:

- Fixed to the viewport, `justify-content: flex-end`, width `min(360px, 92vw)`.
- Full-height, white, left border, drop shadow (`-8px 0 32px rgba(0,0,0,0.1)`).
- Slide-in animation: starts `translateX(100%)`, animates to `translateX(0)` over 300ms
  (`ease-out`) on mount via a `requestAnimationFrame`-deferred state flip — not a CSS transition
  triggered by mount alone (avoids the "no transition on first paint" issue).
- A semi-transparent scrim (`rgba(15,23,42,0.2)`) behind it, itself fading in over 200ms, click-to-close.
- Header: a 36px rounded-square icon tile (icon = the L0/L1/L2 asset for `level`, or a custom
  `eyebrow` override for Milestone → "Mốc"), title = the entity's name, close (×) button top-right.
- Body: vertically stacked fields, scrollable if content overflows.
- Footer: "Đóng" (ghost button) + "Lưu" (primary button) — **but the Lưu button here is a no-op that
  just closes the drawer** (`onClick={onClose}`); every field inside already saves immediately
  on-change via its own `onUpdate(patch)` call. There is no separate "unsaved changes" concept — this
  is an always-live-editing panel, not a form with a submit step. `showSave` can suppress the button
  entirely (unused by any of the three drawers today, but present in the shell's API).
- Escape key closes it; body scroll is locked (`overflow: hidden`) while open.

### `TimelineDrawer` (editing a Task/L0)

Fields, each calling `onUpdate({ ...patch })` immediately on change:

- **Phụ trách** (owner) — a `FilterDropdown` over org-chart members, or an inline message ("Chưa có
  thành viên trên org chart. Thêm người ở tab Overview trước.") if the member list is empty. Disabled
  if the current role lacks `timeline.manage`.
- **Trạng thái** — `FilterDropdown` over `TIMELINE_STATUS_LABEL_VI` minus `'archived'` (archiving
  happens via the delete action, not this dropdown; `'archived'` status is mapped to/from
  `'cancelled'`'s slot for display purposes — the raw value sent on change is whichever key was
  clicked, never `'archived'` itself).
- **Bắt đầu / Kết thúc** — two `DatePicker`s side by side (`grid-cols-2`).
- **Màu thanh Gantt** — the `GanttColorPicker` (see below), pre-seeded from `colorHex ??
  ganttTaskBaseHex(colorIndex)`.
- **Tiến độ · N%** — a *disabled*, read-only range input showing the rollup value (never directly
  editable at this level — it's always `timelineProgressPercent(...)`).
- **Mô tả** — a 3-row textarea.
- **Subtask block** (only rendered if there's at least one Subtask, or if the "add subtask" action is
  available): a mini list — average-progress bar, then one row per Subtask (index badge, name,
  progress-% pill, optional delete button) — plus a "+" header button to add another Subtask.
- **Xóa Task** button (ghost, red) at the very bottom, only if `timeline.manage` is granted.

### `TaskDrawer` (editing a Subtask **or** a Subitem — branches on `taskWorkLevel`)

Writability: `can(role,'task.manage') OR (can(role,'task.update_assigned') AND task.assigneeId ===
currentUserId)` — same rule enforced server/store-side (`03-state-management.md`), duplicated here
purely to disable fields in the UI ahead of a failed API call.

**If it's a Subitem (level 2)** — a deliberately *smaller* field set:

- Tên (text input), Ưu tiên, Phụ trách (only enabled if full `task.manage`, not just
  `task.update_assigned` — an assigned member can update status/description but not reassign the item
  to someone else), Mô tả (2 rows), a `TaskDependenciesSection` (predecessors only — see below), then
  a single full-width "Check đã hoàn thành công việc" row (checkbox + label, toggles
  `completed ⇄ not_started`) instead of a progress slider — **a Subitem never gets a progress slider,
  only this binary toggle**, matching the binary `leafProgress` rule from `04-domain-logic.md`. "Xóa
  Subitem" button at the bottom if permitted.

**If it's a Subtask (level 1)**:

- Trạng thái (`FilterDropdown` over the full `TaskStatus`, glyph-leading, label colored via
  `statusPill(status).fg`), Ưu tiên, Phụ trách, Bắt đầu/Kết thúc (two `DatePicker`s), Mô tả (3 rows,
  fixed 85px height), `TaskDependenciesSection`.
- Then **either**: a `SubitemBlock` (if it has ≥1 Subitem, or the add-subitem action is available) —
  a mini checklist of its Subitems with a progress bar computed as `doneCount/total` (this is a
  *simple count*, distinct from the effort-weighted rollup used for the Subtask's own stored
  `progressPercent` — the drawer's mini progress bar and the store's real rollup can show slightly
  different numbers if effort weights aren't all equal; that's an existing, accepted inconsistency,
  not a bug to silently "fix" during the port unless asked) — **or**, only when it has zero Subitems,
  a live-editable progress range slider (`onChange` fires `onUpdate({ progressPercent })` on every
  drag tick).
- "Xóa Subtask" button at the bottom if permitted.

### `MilestoneDrawer`

Phụ trách, a read-only status line (`MILESTONE_STATUS_LABEL_VI[status]` — never directly editable,
same "always derived" rule as elsewhere), Ngày mốc (`DatePicker`), a read-only progress bar
(`milestoneProgressPercent`), Mô tả, then (if any) a bullet list of related tasks (`name · pct%`), and
a closing caption line: `Task: {parentTimelineName} · Owner: {memberName} [· Critical]`. No delete
button is wired here (the drawer has no `onDelete` prop at all) — milestones can only be archived from
elsewhere or not at all in the current UI.

## Create dialogs (`CreateDialogs.tsx`)

Unlike the edit drawers, these are **centered modal dialogs** (`role="dialog"`, `max-w-md`, scrim
`rgba(15,23,42,0.2)`) with an explicit "Lưu" that actually submits, and a "Đóng" that discards. All
share `DialogShell` (nearly identical chrome to `DrawerShell`'s header, but the whole component is
centered rather than slid in from the side).

`CreateDialogs` is a single dispatcher component taking a `kind: 'task'|'subtask'|'subitem'
|'milestone'|'baseline'|null` prop (`null` renders nothing). Submission flow for all five is the same
wrapper:

```ts
async function run(fn) {
  try { await fn(); onClose() }
  catch (e) { onError(e instanceof Error ? e.message : 'Lỗi') }   // surfaces into ProjectTimelineTab's AlertDialog
}
```

- **Task (L0)** dialog: Tên, Mô tả, Phụ trách (`OrgAssigneeField`, see below), Bắt đầu/Kết thúc (2
  date pickers, default `today` / `today+14`), and the `GanttColorPicker` — pre-seeded with
  `nextGanttColorIndex(existing active Task color indexes)` so a new Task gets a color no other
  active Task is currently using (until you wrap past 100 of them). Save disabled until name is
  non-empty, an owner is chosen, and at least one member option exists.
- **Subtask (L1)** dialog: locked to a specific parent Task (passed in as `defaultTl`, shown as a
  read-only "Task cha · {name}" eyebrow — there's no dropdown to change it). Tên, Mô tả, Phụ trách,
  Ưu tiên, Bắt đầu/Hạn — both date fields are **pre-clamped into the parent Task's window** on
  every change via `clampDateRangeToBounds` (mirroring the store's own clamp, just applied live in the
  form instead of waiting for a failed submit). Initial dates default to `today` (clamped into the
  parent's bounds) through the parent's end.
- **Subitem (L2)** dialog: if opened with a `defaultParentId` that resolves to a real Subtask, the
  parent is **locked** (same read-only eyebrow pattern); otherwise a `FilterDropdown` lets you pick
  any existing Subtask as the parent. Tên, Mô tả, Ưu tiên, Phụ trách. No date fields are shown at
  all — on save, dates are computed automatically as `[today, parent.dueDate]` then clamped into the
  parent Subtask's window (so a Subitem you create always defaults to "now until the Subtask is due,"
  clipped to fit).
- **Milestone** dialog: a `FilterDropdown` to pick which Task it attaches to (defaults to the first
  active Task, or whichever Task the dialog was opened in context of), Tên, Mô tả, Phụ trách, Ngày
  (single `DatePicker`). `isCritical` is always submitted as `false` — there is no UI control for it
  despite the field existing on the entity.
- **Baseline** dialog: a `FilterDropdown` to pick a Task, Tên (defaults to literal "Baseline mới"), no
  date field (`baselineDate` is always `todayIso()` on submit). This dialog creates exactly **one**
  `TimelineBaseline` row for one Task — it is a different, narrower action from the "Chốt baseline dự
  án" one-click button in `BaselineCompareView` (`createProjectBaselines`, which does every Task at
  once). Nothing in the current UI actually opens this single-Task dialog (no call site passes
  `kind: 'baseline'`) — it exists and works, but is presently unreachable from the app. Worth keeping
  for parity, but don't be surprised it has no trigger button.

### `OrgAssigneeField`

A thin wrapper used for every "Phụ trách" field across all create dialogs: if the member list (minus
any `'__none__'` sentinel) is empty, renders an inline warning message instead of a dropdown
("Chưa có thành viên trên org chart. Thêm người ở tab Overview trước."); otherwise a `FilterDropdown`
with `hideFilterIcon` (uses each member's own avatar as the leading icon instead, via
`timelineMemberFilterOptions`).

## `GanttColorPicker.tsx`

A native `<input type="color">` swatch (styled to fill a 36px rounded square, border color =
`ganttHexBorder(currentHex)`) plus a text `ControlInput` mirroring the hex value, live-synced both
ways. Typing a hex commits on blur or Enter (validated through `normalizeGanttHex`); picking via the
native swatch commits immediately on `onChange`. Below the input: three small preview swatches
labeled Task/Subtask/Subitem, each rendered via `ganttBarColors(colorIndex, depth, liveHex).fill` so
the user sees exactly how the L0/L1/L2 washes will look *before* saving. `onChange(nextIndex, nextHex)`
always passes both — the index is recomputed via `nearestGanttColorIndex(hex)` purely as a fallback
slot for later if the hex is ever cleared, not because the index is meaningfully "the" color anymore
once a custom hex is set.

## `GanttContextMenu.tsx`

A generic floating menu primitive (not Timeline-specific in its implementation, just the icon/badge
conventions are): fixed position clamped to stay inside the viewport (`min(desiredX, innerWidth -
menuWidth - 8px)`, same for Y), 220px wide, closes on outside click, Escape, or scroll (this last one
means the menu **cannot be scrolled past** — any scroll event anywhere closes it rather than letting
it follow). Each item: optional leading icon (with an optional colored `WorkLevelPlusBadge` corner
overlay for "add X" actions), label, optional muted subtext line (used to show which
task/timeline an "Add Subtask to {taskName}" item targets), optional `danger` styling (red text/icon,
used for delete items with a divider always placed above them), optional `disabled`.

Menu contents by right-click target (see `05-gantt-board-ui.md` for the trigger surfaces):

- **Task (Timeline) row**: Thêm Task Mới → Thêm Subtask → divider → Properties → divider → Xóa Task
  (each item present only if the corresponding handler/permission was provided).
- **Subtask row**: Thêm Subtask → Thêm Subitem → (divider) → Đánh dấu hoàn thành / Bỏ hoàn thành →
  divider → Properties → divider → Xóa Subtask.
- **Subitem row**: Đánh dấu hoàn thành / Bỏ hoàn thành → divider → Properties → divider → Xóa
  Subitem.

## `TaskDependenciesSection.tsx`

Embedded inside `TaskDrawer` for both Subtask and Subitem levels. Lists this task's **predecessors
only** (`state.dependencies.filter(d => d.targetTaskId === taskId)`) — there is no UI to view or add
*successors* (tasks that depend on this one) from this panel. Each predecessor row: a small icon,
the other task's label (`"{name} · {parentTimelineName}"`, or "Task đã xóa" if it no longer resolves),
and a remove (×) button if `dependency.manage` is granted. Below the list, if the caller supplied
`onAddDependency`: a `FilterDropdown` of candidate tasks (same-Task candidates listed before
other-Task candidates, already-linked-as-predecessor and self excluded) plus a "+" button that calls
`onAddDependency({ sourceTaskId: picked, targetTaskId: taskId, type: 'FS', lagDays: 0 })` — the UI
only ever creates Finish-to-Start dependencies with zero lag, even though the data model supports
`SS`/`FF`/`SF` and non-zero lag.

## Small glyph/badge components

- **`PriorityGlyph`**: renders one of four SVG icon assets (`priority-low/medium/high/urgent.svg`)
  sized via `width`/`height` attribute string-replacement on the raw SVG markup. `critical` priority
  uses the "urgent" asset.
- **`StatusGlyph`**: renders one of five pre-colored SVG dot assets, chosen via
  `statusIconName(status)` from `04-domain-logic.md`.
- **`WorkLevelPlusBadge`**: a small circular badge (default 12px, "+"-glyph inside, 1.5px ring in the
  host surface's background color) colored per `WORK_LEVEL_ADD_BADGE[level]`, absolutely positioned
  at an icon's bottom-right corner. Used everywhere an "add a child at level N" affordance needs to be
  visually distinguished from a plain "view/select level N" icon.
- **`TimelineFullscreenExitButton`** — covered in `05-gantt-board-ui.md`.
