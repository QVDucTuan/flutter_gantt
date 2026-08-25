# List and Baseline views

Both are thin adapters over the shared `DataTable` primitive (see
`10-design-tokens-and-shared-ui.md`) plus the same `buildGanttRows()` tree used by the Gantt board —
so the row order, WBS numbers, and expand/collapse state are always identical across all three views;
only the presentation differs.

`src/modules/projects/boards/timeline/components/ListAndBaseline.tsx` is a one-line deprecated
re-export of `BaselineCompareView` — ignore it, import the real component directly.

## `TimelineListView.tsx`

Purpose: the same Task→Subtask→Subitem tree as the Gantt board, but as a flat sortable table — no
date chart.

- Builds rows via `buildGanttRows({ timelines: state.timelines, milestones: state.milestones, tasks,
  expandedIds, visibleTaskIds, keyPrefix: 'LIST' })`, then filters out any `'milestone'`-kind rows
  (never produced anyway, see `04-domain-logic.md`) purely for type narrowing.
- Calls `useListviewPagination(null)` on mount — explicitly opts this view **out** of the shared
  Footer's pagination slot and the `DataTable`'s enter-animation-on-append behavior (a comment in the
  source notes the spring/lazy-append animation "was janky on expand/collapse" for a tree table).
- Columns (all `sortable: false` — this table is browsed in tree order, not resorted):

  | id | header | width | notes |
  |---|---|---|---|
  | `wbs` | # | 56 | the `row.wbs` string, e.g. "1.2.1" |
  | `name` | Công việc | 340 | indent spacer (`depth * TREE_INDENT`) + expand chevron (if it has visible children) + type icon + name; overdue tasks render in orange; completed tasks get a strikethrough; cancelled tasks render at 55% opacity |
  | `level` | Cấp | 88 | a colored pill: Task/Subtask/Subitem, colored via `WORK_LEVEL_ADD_BADGE` |
  | `assignee` | Phụ trách | 160 | avatar + name, or "—" if unset; Task rows show their `ownerId`, task rows show `assigneeId`, milestone rows (never present) would show nothing |
  | `priority` | Ưu tiên | 110 | glyph + label; "—" for Task/Timeline rows (they have no priority) |
  | `status` | Trạng thái | 140 | for a Task row, its `TimelineStatus` mapped through `mapTimelineStatus` (archived→cancelled); for a Subtask/Subitem row, its own status, with the label swapped to "Trễ hạn" (and orange color) when overdue |
  | `start` | Bắt đầu | 110 | Task's `startDate` or task's `startDate`; centered |
  | `due` | Kết thúc | 110 | Task's `endDate` or task's `dueDate`; orange if overdue |
  | `progress` | % | 72 | task's `progressPercent`; "—" for Task/Timeline rows |

- Row click → `onSelectTimeline`/`onSelectTask` (opens the same drawers as the Gantt board).
- Wrapped in a `PageCard` with no toolbar, inside a fullscreen-target div (same
  `useTimelineFullscreenTarget` pattern as the Gantt board).

## `BaselineCompareView.tsx`

Purpose: compare a frozen snapshot of dates/progress against the live values, one **batch** at a time.

### Batching

Recall from `01-data-model.md`: a "project baseline" is really one `TimelineBaseline` row per Task,
all sharing the same `(baselineDate, name)`. This view reconstructs the batch:

```ts
batchKey(b) = `${b.baselineDate}::${b.name}`
groupBatches(baselines) → sorted by baselineDate descending, each = { key, name, baselineDate, baselines: TimelineBaseline[] }
```

The active batch is whichever one contains `state.selectedBaselineId`, or the most recent batch if
none is selected (or if the selected id's batch no longer exists).

### Empty state

If there are zero baselines at all: a centered `PageCard` with copy ("Chưa có baseline… Một lần chốt
toàn bộ Task trong dự án — sau đó so sánh hạn và tiến độ với thực tế.") and a "Chốt baseline dự án"
button wired to `onCreateProject` (→ `store.createProjectBaselines()`), shown only if that permission
is available. Local `busy`/`error` state wraps the async call.

### Filled state

- Scope: only the Tasks + Subtasks/Subitems referenced by the active batch's snapshots (a Task is
  included if its id is a key in `timelineIds`; a Subtask/Subitem is included if either its own id or
  its `parentTaskId` appears among the snapshot's task ids — so a Subitem is kept even if only its
  parent Subtask was individually snapshotted).
- Rows built via the same `buildGanttRows` (with everything in that scope force-expanded,
  `keyPrefix: 'BL'`), milestone rows filtered out.
- A `FilterDropdown` labeled "Baseline" lets the user switch between batches (options show name +
  `dd/mm/yyyy · N Task` as the subtitle).
- A summary strip of 3 colored count chips computed by walking every snapshot task in the batch and
  comparing `daysBetween(snapshotDue, actualDue)`: **Trễ** (late, `d > 0`, orange), **Đúng hạn** (on
  time, `d === 0`, muted), **Sớm** (early, `d < 0`, green). A task whose actual record no longer
  exists is skipped entirely (not counted in any bucket).
- A "Chốt lại" (re-snapshot) button, same handler as the empty-state button, always available if the
  permission is present (even when baselines already exist).
- Columns:

  | id | header | notes |
  |---|---|---|
  | `wbs` | # | |
  | `name` | Công việc | indent + type icon + name |
  | `level` | Cấp | colored pill |
  | `blDue` | Baseline hạn | the snapshot's due date (`timelineEndDate` for a Task row, matching task snapshot's `dueDate` for a Subtask/Subitem row) |
  | `actualDue` | Thực tế hạn | the CURRENT live due date (falls back to "—" if the entity was archived since); colored orange if variance > 0 |
  | `variance` | Lệch (ngày) | `daysBetween(blDue, actualDue)`, rendered as `+N`/`N`/"—"; orange if positive, green if negative, muted if zero or unavailable |
  | `blPct` | % Baseline | snapshot's `progressPercent` (Task rows always show "—" — a Task snapshot doesn't carry a percent, only its Subtasks do) |
  | `actualPct` | % Thực tế | current live `progressPercent` |

- Row click → same `onSelectTimeline`/`onSelectTask` drawers.
