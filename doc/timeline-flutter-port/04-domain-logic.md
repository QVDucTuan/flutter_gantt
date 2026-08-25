# Domain logic (pure functions — the most directly portable part of this feature)

Everything in `src/modules/projects/boards/timeline/domain/*` takes plain data in and returns plain
data out — no React, no fetch, no DOM. This is the layer that translates almost verbatim into Dart.
Where a function is unit-tested (`domain/domain.test.ts`), the test cases are reproduced here as
worked examples so behavior can be checked against a Dart port without re-deriving it from scratch.

## `dates.ts` — ISO date discipline

All dates in this feature are `'YYYY-MM-DD'` strings, never `Date` objects, at rest.

```ts
isValidIsoDate(iso): boolean
  // regex /^\d{4}-\d{2}-\d{2}$/ AND a real calendar day
  // (rejects '2026-02-30' by round-tripping through `new Date(y, m-1, d)` and checking
  //  getFullYear/getMonth/getDate all match what was asked for)

normalizeIsoDate(raw): string | null      // trims to first 10 chars (handles a datetime prefix), validates
parseIsoDate(iso): Date                    // asserts valid, then `new Date(y, m-1, d)` (LOCAL date, no time zone shifting)
toIsoDate(date): string                    // pads back to 'YYYY-MM-DD'; throws if date.getTime() is NaN
todayIso(now = new Date()): string
addDays(iso, days): string                 // parseIsoDate → setDate(date + days) → toIsoDate
daysBetween(startIso, endIso): number      // Math.round((parse(end) - parse(start)) / 86_400_000)
formatDateVi(iso): string                  // 'dd/mm/yyyy', or '—' if invalid

assertValidIsoDate(iso, label='Ngày')                // throws `Error('${label} không hợp lệ (cần YYYY-MM-DD).')`
assertStartBeforeEnd(start, end, label='Thời gian')  // validates both, then throws if start > end
assertDateRangeWithinBounds(start, end, boundStart, boundEnd, label)
  // throws unless boundStart <= start <= end <= boundEnd

isTaskOverdue(dueDate, status, today=todayIso()): boolean
  // false if status is 'completed' or 'cancelled'; false if dueDate is invalid; else dueDate < today

expectedProgressPercent(start, end, today=todayIso()): number
  // linear schedule position, 0..100:
  //   start >= end            → today >= end ? 100 : 0
  //   today <= start          → 0
  //   today >= end            → 100
  //   else                    → round(daysBetween(start, today) / daysBetween(start, end) * 100)

clampPercent(n): number   // round then clamp to [0, 100]
```

### `clampDateRangeToBounds(startDate, dueDate, boundStart, boundEnd)` — used everywhere a child must
stay inside a parent's window

```
s = startDate; d = dueDate
if s < boundStart: s = boundStart
if s > boundEnd:   s = boundEnd
if d > boundEnd:   d = boundEnd
if d < boundStart: d = boundStart
if s > d:          // the clamp inverted the range entirely — collapse to the FULL bound window
  s = boundStart
  d = boundEnd
return { startDate: s, dueDate: d }
```

Note the order: `s` is clamped against both bound edges *before* `d` is touched, and the
"totally outside" fallback is the **whole parent window**, not a zero-length range at one edge — a
child that was scheduled entirely after its new (earlier) parent window doesn't collapse to a single
day, it re-spans the parent's full range.

## `ganttLayout.ts` — day ↔ pixel coordinate math

```ts
const DAY_WIDTH = { day: 36, week: 24, month: 10 }        // px per calendar day, by zoom level
const CHART_LABEL_LEAD_PX = 180                             // reserved space before the first bar for its name-pill
const ROW_H = 40          // px, every Gantt row (Task/Subtask/Subitem) is this tall
const AXIS_H = 48          // px, header height (month band 22px + day band 26px)
const COL = { key: 72, summary: 220, status: 56, priority: 65, startDate: 78, endDate: 78, assignee: 168 }
const TABLE_W = sum of COL values except `key` (key is defined but never rendered as a column)
```

```ts
computeGanttRange(dates: string[], zoom): { start, end, dayWidth }
  leadDays = ceil(180 / DAY_WIDTH[zoom])          // e.g. day zoom → 5 days, week → 8, month → 18
  if dates is empty (no non-archived Task at all):
    start = today - leadDays; end = today + 21     // anchor on real calendar today
  else:
    sorted = dates.sorted()
    start = sorted.first - leadDays
    end   = sorted.last + 14

extendGanttRangeToWidth(range, minWidthPx)
  // stretches range.end (never range.start) so the day-grid fills at least minWidthPx —
  // prevents a blank strip after the last tick when the viewport is wider than the natural range

dateToX(iso, range) = daysBetween(range.start, iso) * range.dayWidth
durationWidth(startIso, endIso, range) = max(daysBetween(start, end) + 1, 1) * range.dayWidth   // inclusive of both end days
xToDate(x, range) = addDays(range.start, round(x / range.dayWidth))
isWeekend(iso) / isSunday(iso)   // Sunday gets a slightly stronger tint than Saturday in the UI

buildMonthBands(range) → [{ label: "Jan '26", x, width }, ...]   // one band per calendar month touched by the range
buildDayTicks(range, zoom) → [{ iso, dayNum, x, weekend, sunday }, ...]
  // step = 1 day at zoom 'day'/'week', step = 2 days at zoom 'month' (sparser labels, same dayWidth-based x)
```

**Which dates feed `computeGanttRange`**: every visible Subtask/Subitem's start+due, every non-archived
Milestone's date, and every non-archived Task's start+end (`GanttBoard`'s `allDates` memo) — but only
when at least one non-archived Task exists; otherwise the array is forced empty so an all-milestone,
no-task board still anchors on today instead of on stray milestone dates.

**Auto-scroll-to-today** (`GanttBoard`'s `useLayoutEffect` keyed on a signature of every
timeline/task/milestone id + zoom): whenever entities are created/removed or zoom changes and the
chart pane has a measured width, scroll so that either today (if inside the range) or the single
most-recent date across all entities (if today is outside the range) sits at `25%` of the viewport
width from the left. This runs once per "entity set" change, not on every render/scroll.

## `ganttRows.ts` — flattening the tree, WBS numbers, chart grouping

```ts
type GanttRow =
  | { kind: 'timeline'; id; timeline: ProjectTimeline; depth: 0; wbs: string; treeGuides: boolean[]; colorIndex; colorHex; rowIndex }
  | { kind: 'milestone'; id; milestone: ProjectMilestone; depth; wbs; treeGuides; colorIndex; colorHex; rowIndex }   // built but never emitted — see below
  | { kind: 'task'; id; task: ProjectTask; depth: 1 | 2; wbs: string; treeGuides: boolean[]; colorIndex; colorHex; rowIndex }

const TREE_INDENT = 14   // px per depth level — MUST match the indent GanttBoard's TreeIndent paints
```

`buildGanttRows({ timelines, milestones, tasks, expandedIds, visibleTaskIds, keyPrefix })`:

1. For each non-archived Task, push its own row (`depth: 0`, `wbs = "${index+1}"`).
2. **Milestones are never pushed as rows** — the `'milestone'` row kind exists in the type for
   completeness but `buildGanttRows` never constructs one (milestones render only as chart overlays,
   see `05-gantt-board-ui.md`); `GanttBoard`'s own row-rendering switch has a
   `if (row.kind === 'milestone') return null` branch that is dead code kept "for type completeness."
3. If the Task's id isn't in `expandedIds`, stop (no children rendered).
4. Recursively walk: direct Subtasks of this Task (`parentTaskId == null`, not archived, in
   `visibleTaskIds`), **sorted by `startDate` ascending** (string comparison — this is why an invalid
   non-ISO startDate would sort unpredictably; upstream code guarantees ISO strings). For each,
   `wbs = "${parentWbs}.${indexAmongSiblings+1}"`. Recursion stops hard at `depth >= 2` (no
   grandchildren of a Subtask are ever walked, even if data has them) and also stops if the current
   node's own id isn't expanded.
5. `treeGuides: boolean[]` has one entry per ancestor depth; `treeGuides[i] = true` means "the
   ancestor at depth i still has more siblings below this branch" — this is exactly what decides
   whether the tree-line renderer draws a full vertical rail (more siblings below) or stops with an
   elbow (`┗`) vs continues with a tee (`┣`) at the branch point.
6. `rowIndex` is assigned as a final pass, 1-based, over the fully flattened array (used for
   print-sheet numbering only, not for React `key`s).

### Chart-only grouping (drawn as background capsules, computed by scanning the already-flattened rows)

```ts
buildTaskChartGroups(rows) → TaskChartGroup[]   // { id, name, startRow, rowCount, startDate, endDate }
  // for each 'timeline' row: count how many following rows belong to it (stop at the next 'timeline'
  // row); only emit a group if rowCount > 1 (i.e. it has at least one visible child) — this is the
  // thin unfilled outline capsule wrapping a Task + all its visible descendants

buildSubtaskChartGroups(rows) → SubtaskChartGroup[]   // adds colorIndex/colorHex
  // for each depth-1 'task' row: count immediately-following depth-2 'task' rows whose
  // parentTaskId equals this row's id (stops at the first row that breaks that condition); only
  // emit a group if that count > 0 — this is the tinted capsule wrapping a Subtask + its Subitems.
  // NOTE: the group's dates are the SUBTASK's own startDate/dueDate, not a span across children.
```

## `ganttBarColors.ts` — the one and only source of bar colors

```ts
GANTT_TASK_COLOR_COUNT = 100                 // 100 preset "families", indexed 0..99
HUE_MIN = 95; HUE_MAX = 320                    // soft green → teal → blue → violet → soft rose band
GANTT_OVERDUE_MARK = 'var(--color-primary)'    // #0d90d9 — a left-edge inset stripe, NEVER a fill recolor
GANTT_PROGRESS_OPACITY = 1                       // the progress-fill strip is fully solid, no multiply/fade

GANTT_BAR_TONE = {
  0: { fillS: 62, fillL: 64, progressS: 68, progressL: 52 },   // L0 Task
  1: { fillS: 56, fillL: 62, progressS: 62, progressL: 50 },   // L1 Subtask — deepest of the three (stack header)
  2: { fillS: 58, fillL: 78, progressS: 62, progressL: 66 },   // L2 Subitem — lightest, still vivid
}

hueForIndex(index) = HUE_MIN + (index mod 100) / 100 * (HUE_MAX - HUE_MIN)
hslToHex(h, s, l): string   // standard HSL→RGB→hex, s/l given 0..100
```

```ts
ganttBarColors(colorIndex: number, depth: 0|1|2, colorHex?: string|null): { fill: string; progress: string }
```

- **If `colorHex` is unset** (the common preset path): `hue = hueForIndex(colorIndex)`, then
  `fill = hsl(hue, tone.fillS, tone.fillL)`, `progress = hsl(hue, tone.progressS, tone.progressL)` —
  straight lookup from `GANTT_BAR_TONE[depth]`.
- **If `colorHex` is set** (user free-picked a hex on the Task): parse it to `{h, s, l}`.
  - Depth 0: `fill = colorHex` verbatim (the picker preview must exactly match the bar). `progress =
    hsl(h, clamp(max(s, tone.progressS), ≤85), clamp(l-8, [28,58]))` — same hue, pushed a bit
    darker/more saturated for the progress strip.
  - Depth 1/2: **do not reuse `colorHex` directly** — lighten it: `subL = clamp(l+6, ≥48, ≤72)`,
    `itemL = clamp(l+22, ≥subL+12, ≤84)`; `fillL = depth===1 ? subL : itemL`; `fillS = max(22, s *
    (depth===1 ? 0.85 : 0.72))`; `fill = hsl(h, fillS, fillL)`; `progress = hsl(h, min(80, fillS+6),
    max(34, fillL-10))`. This is what guarantees a Subitem always reads visually lighter than its
    Subtask even when the user picked an arbitrary custom hex.

```ts
normalizeGanttHex(value): string|null      // accepts with/without '#', 3-digit shorthand expands to 6, lowercases
nearestGanttColorIndex(hex): number         // maps a hex's hue back to the nearest 0..99 preset index (for the fallback slot when a custom color is later cleared)
ganttTaskBaseHex(index): string              // preset L0 fill for index i — used to seed the color picker
listGanttTaskBases(): string[]               // all 100 preset hexes in order
ganttBarAvatarBg(fillHex): string             // same hue, s+12 (≤72), l-22 (≥38) — a visibly darker chip behind the assignee avatar on a bar
ganttHexBorder(fillHex): string                // same hue, s+10 (≤78), l-24 (≥28) — darker outline tone
relativeLuminance(hex): number                 // WCAG relative luminance formula, sRGB→linear→0.2126R+0.7152G+0.0722B
onBarTextColor(fillHex): string                 // luminance > 0.55 → 'var(--color-text-table)' (dark navy), else '#ffffff'
nextGanttColorIndex(usedIndexes: Iterable<number>): number   // first index 0..99 not already in use by an active Task; if all 100 are used, wraps to `usedCount mod 100`
```

## `ganttRows.ts` extras: status/priority display metadata

```ts
statusPill(status) → { label: 'IN PROGRESS'|'DONE'|'BLOCKED'|'CANCELLED'|'TO DO', bg, fg }
  // in_progress → orange (#F2892E family) · completed → green (#55A76A) · blocked → grey (#A6A6A6)
  // cancelled → red (#D63316) · default (not_started) → blue (#4682FA)
  // ACTIVE — used by TaskDrawer's status FilterDropdown for the option label color.

statusIconName(status) → 'status-created'|'status-inprogress'|'status-blocked'|'status-finish'|'status-canceled'
  // ACTIVE — maps 1:1 to an svg icon asset name, consumed by StatusGlyph.tsx

priorityMeta(priority) → { label, icon: '⇧⇧'|'⇧'|'='|'⇩', color }
  // ⚠️ DEAD as far as live UI goes — its only consumer is the unused TimelinePrintSheet.tsx (see
  // 09-pdf-export.md). Live priority rendering uses PriorityGlyph.tsx (an svg icon) + PRIORITY_LABEL_VI
  // instead. Fine to skip porting unless a text-glyph priority indicator is wanted somewhere new.

initials(name) → up to 2 uppercase letters (first+last word initial, or first 2 chars of a single word)
  // ⚠️ Also only consumed by the unused TimelinePrintSheet.tsx. MemberAvatar.tsx has its OWN
  // separate, functionally-identical `initials()` for live use — port that one, not this one.
```

## `progress.ts` — the rollup engine

```ts
weight(task) = max(task.estimatedEffort, 1)     // effort-weighted average; 0 or negative effort never zeroes a weight
eligible(status) = status !== 'cancelled'          // cancelled items are EXCLUDED from every rollup below

leafProgress(task):
  completed → 100
  cancelled → 0
  parentTaskId set (it's a Subitem) and not completed/cancelled → 0   // binary: only 100 or 0, ever
  else → clampPercent(task.progressPercent)                              // a Subtask's own manual value

childHasActivity(task): boolean
  cancelled → false
  status !== 'not_started' → true
  else (not_started) → true only if it's a top-level task (`!parentTaskId`) AND its own progressPercent > 0
  // i.e. a Subitem that's simply 'not_started' never counts as "active", by definition (its progress can only be 0 or 100)

deriveStatusFromChildren(children): 'not_started'|'in_progress'|'completed'
  list = children.filter(not archived AND eligible)
  if list is empty → 'not_started'
  if every child is 'completed' → 'completed'
  if any child has activity → 'in_progress'
  else → 'not_started'

computeParentProgress(parent, children): number
  list = children.filter(not archived AND eligible)
  if list is empty → leafProgress(parent)                 // no children at all → parent's own value stands
  else → clampPercent( Σ(leafProgress(c) * weight(c)) / Σ(weight(c)) )
```

```ts
applyParentProgressRollup(tasks): ProjectTask[]
  // groups tasks by parentTaskId (Subitems grouped under their Subtask)
  // for a task with NO children: if status==='completed', force progressPercent=100 (else unchanged)
  // for a task WITH children:
  //   if task.status === 'cancelled': keep status, but still recompute progressPercent via rollup
  //   else: progressPercent = computeParentProgress(...); status = deriveStatusFromChildren(...)
  //         if derived status is 'completed' → also force progressPercent=100 and set
  //           completedAt = existing.completedAt ?? now()  (never overwrites an existing completedAt)
  //         else → progressPercent = rollup value, status = derived value, completedAt = null
```

```ts
applyTimelineStatusRollup(timelines, tasks): ProjectTimeline[]
  // skip (return unchanged) if a Task is archived, or already 'cancelled'/'archived'
  // roots = that Task's direct Subtasks, not archived, eligible
  // if no roots → unchanged (a Task with zero Subtasks keeps whatever status it was set to manually)
  // else → status = deriveStatusFromChildren(roots); if unchanged, skip the write (no gratuitous updatedAt bump)
```

```ts
milestoneProgressPercent(milestone, tasks): number
  related = tasks matching milestone.relatedTaskIds, not archived, eligible
  if none → milestone.status === 'completed' ? 100 : 0
  else → clampPercent( completedCount / related.length * 100 )    // simple count-based %, NOT effort-weighted

timelineProgressPercent(timeline, tasks): number       // effort-weighted average of leafProgress across direct Subtasks (same formula shape as computeParentProgress)
projectProgressPercent(timelines, tasks): number         // effort-weighted average of timelineProgressPercent across every active (non-archived, non-cancelled) Task, weighted by the SUM of that Task's Subtasks' effort (falls back to weight 1 if a Task has zero Subtasks, so it still counts once)

deriveMilestoneStatus(milestone, tasks, today): MilestoneStatus
  related = tasks matching relatedTaskIds, not archived, eligible
  if related.length > 0 AND every related task is 'completed' → 'completed'
  else if milestone.milestoneDate < today AND milestone.status !== 'completed' → 'missed'
  else if milestone.milestoneDate <= today AND some related task is 'blocked' or 'in_progress' → 'at_risk'
  else → milestone.status === 'completed' ? 'pending' : milestone.status    // otherwise keep current value
```

## `permissions.ts` — role matrix

```ts
type TimelinePermission =
  | 'timeline.manage' | 'milestone.manage' | 'task.manage' | 'task.update_assigned'
  | 'dependency.manage' | 'baseline.manage' | 'comment.create' | 'attachment.create' | 'view'

MATRIX = {
  project_admin:   ALL,
  project_manager: ALL,
  team_leader:     [task.manage, task.update_assigned, dependency.manage, comment.create, attachment.create, view],
  member:          [task.update_assigned, comment.create, attachment.create, view],
  viewer:          [view],
}
can(role, permission): boolean
assertCan(role, permission): void   // throws Error('Bạn không có quyền thực hiện thao tác này.')
```

Only `project_admin`/`project_manager` can manage Timelines/Milestones/Baselines or archive a Task at
all. `team_leader` can fully manage Subtasks/Subitems and dependencies but not Timelines/Milestones.
`member` can only update a task **assigned to them** (enforced in the store, see
`03-state-management.md`'s `assertTaskManage`), not create/delete anything, not manage dependencies.
`viewer` can only look.

## `filterTasks.ts`

```ts
filterTasks(tasks, filters, today): ProjectTask[]
  excludes archived tasks unconditionally, then applies (all must pass, AND):
    timelineId/assigneeId/status/priority/milestoneId — exact match unless filter value is 'all'
    overdueOnly    — keep only if isTaskOverdue(task.dueDate, task.status, today)
    blockedOnly    — keep only if task.status === 'blocked'
    dateFrom       — drop if task.dueDate < dateFrom      (i.e. task ends before the window starts)
    dateTo         — drop if task.startDate > dateTo       (i.e. task starts after the window ends)
                     → together these two are an OVERLAP filter, not a containment filter
    search (case-insensitive substring, only if non-empty after trim)
      — matches name OR description OR any entry in labels
```

⚠️ **No UI currently calls `setFilters`** — confirmed by searching the whole module for callers; only
the store/hook/types/this file reference filters at all. `ProjectTimelineTab` still runs this filter
every render with whatever `state.filters` is (always `DEFAULT_FILTERS`), so today it functions purely
as the archived-task exclusion pass. Keep the logic if a filter bar is added to the Flutter version;
otherwise this is optional to port.

## `dependencies.ts` — cycle guard

```ts
wouldCreateCycle(dependencies, sourceTaskId, targetTaskId): boolean
  if source === target → true immediately
  build adjacency (source → [targets]) from existing dependencies PLUS the proposed new edge
  standard DFS cycle detection with visiting/visited marker sets, run from every node

validateNewDependency(dependencies, source, target): void
  throws 'Task không thể phụ thuộc vào chính nó.' if source === target
  throws 'Không cho phép dependency vòng lặp.' if wouldCreateCycle(...)
```

## `uniqueNames.ts` — sibling name uniqueness

```ts
normalizeSiblingName(name) = name.trim().replace(/\s+/g, ' ').toLocaleLowerCase('vi')   // Vietnamese-aware case fold

assertUniqueTimelineName(name, timelines, excludeId?)
  // scope: ALL non-archived Tasks in the project (Tasks live at project root, so "same folder" = whole project)
  // throws 'Đã có Task trùng tên trong dự án.' (name interpolated from WORK_LEVEL_LABEL_VI[0])

assertUniqueTaskNameAmongSiblings(name, tasks, { timelineId, parentTaskId, excludeId?, parentTimeline?, parentSubtask? })
  // 1. throws if trimmed name is empty (message differs for Subtask vs Subitem)
  // 2. if creating/renaming a SUBTASK (parentTaskId is null) and parentTimeline is provided:
  //      throws 'Subtask không được trùng tên với Task cha.' if it matches the parent Task's own name
  // 3. if creating/renaming a SUBITEM (parentTaskId is set) and parentSubtask is provided:
  //      throws 'Subitem không được trùng tên với Subtask cha.' if it matches the parent Subtask's own name
  // 4. siblings = other non-archived tasks with the SAME (timelineId, parentTaskId==null) for a Subtask,
  //               or the SAME parentTaskId for a Subitem — excludeId is skipped
  // 5. throws 'Đã có Subitem trùng tên trong Subtask này.' / 'Đã có Subtask trùng tên trong Task này.'
  //      if any sibling's normalized name matches
```

Two different Tasks CAN have Subtasks with the same name (scope is per-parent, not per-project) — only
the parent-name collision (step 2/3) and the true-sibling collision (step 5) are checked.

## `workLevels.ts`

```ts
type WorkLevel = 0 | 1 | 2
taskWorkLevel(task, tasks): 1 | 2       // 1 if parentTaskId is null, else 2 (even for a data-invalid "orphan" nesting, treated as 2 for display purposes — but see assertCanNestUnder, which the STORE uses to prevent that state from being created in the first place)
isSubitem(task) = task.parentTaskId != null
isSubtask(task) = task.parentTaskId == null

assertCanNestUnder(parentTaskId, tasks): void
  // no-op if parentTaskId is null/undefined (creating a Subtask, always allowed structurally)
  // throws 'Không tìm thấy subtask cha.' if the referenced parent doesn't exist / is archived
  // throws 'Subitem không thể có con. Tối đa 3 cấp (Task → Subtask → Subitem).' if that parent ITSELF has a parentTaskId
  //   → this is the entire enforcement of the 3-level cap

WORK_LEVEL_LABEL_VI = { 0: 'Task', 1: 'Subtask', 2: 'Subitem' }
WORK_LEVEL_ADD_BADGE = { 0: 'var(--color-button-primary)' /* #008ecb blue */, 1: '#00bcd4' /* cyan */, 2: 'var(--color-orange)' /* #e8903d */ }
  // the small colored "+" badge overlaid on the level-0/1/2 tree icon wherever an "add" action is shown
```

## `alerts.ts` — `detectTimelineAlerts(input)`

⚠️ Fully implemented and unit-tested, but **has no rendering consumer anywhere in the Timeline module
today** (confirmed: `state.alerts`/`getAlerts` are only referenced inside the store/hook themselves).
Port this only if the Flutter app is also adding an alerts/inbox surface; otherwise it's safe to skip.

Rules, evaluated over non-archived timelines/milestones/tasks, against a `today` string (the store
passes `state.demoToday`):

| Kind | Trigger | Severity |
|---|---|---|
| `task_overdue` | `isTaskOverdue(task.dueDate, task.status, today)` | critical |
| `task_due_soon` | not overdue, not completed/cancelled, `dueDate === today+1` | warning |
| `task_due_soon` | …`dueDate === today+3` | info |
| `task_due_soon` | …`dueDate === today+7` | info |
| `task_blocked` | `status === 'blocked'` | warning |
| `milestone_overdue` | milestone not completed, `milestoneDate < today` | critical |
| `milestone_due_soon` | `milestoneDate === today+1` or `+3` | warning |
| `milestone_due_soon` | `milestoneDate === today+7` | info |
| `dependency_at_risk` | source task is overdue AND target task isn't completed/cancelled | warning, attributed to the **dependency**, message names the target |
| `timeline_at_risk` | Task's `endDate < today` and Task status isn't `'completed'` | critical |
| `progress_behind` (per Task) | `timelineProgressPercent(tl) + 10 < expectedProgressPercent(tl.start, tl.end, today)` AND `tl.status === 'in_progress'` | warning |
| `progress_behind` (whole project, id `'project-behind'`, singular) | `projectProgressPercent(...) + 15 < expectedProgressPercent(minStart, maxEnd, today)` across ALL timelines | warning |

For `task_due_soon` and `milestone_due_soon`, the check is an **exact match on a specific day-offset**
(`dueDate === addDays(today, 1)`), evaluated in the order 1 → 3 → 7 with the first match winning — a
task due in exactly 1 day is never *also* flagged as "due in 3 days."

## `statusStyles.ts` — ⚠️ entirely dead code

```ts
statusBarColor(status, overdue): string
  // overdue && not completed/cancelled → orange
  // else: completed→success green, in_progress→primary blue, blocked→grey #a6a6a6, cancelled→red #d63316, default→info blue
```

Confirmed by a whole-module search: **nothing imports this file.** `GanttBoard` colors bars via
`ganttBarColors()` + the separate `GANTT_OVERDUE_MARK` inset stripe instead. Do not port this — it
would be a second, inconsistent color system if reintroduced.
