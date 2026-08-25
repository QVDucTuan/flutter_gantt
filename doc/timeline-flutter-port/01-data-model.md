# Data model

Source: `src/modules/projects/boards/timeline/types.ts` (270 lines, fully reproduced/explained below).

## ⚠️ Read this first: UI names ≠ storage names

The UI calls the three hierarchy levels **Task / Subtask / Subitem**. Storage uses only two entity
types. Get this mapping wrong and every other document in this package will be misread:

| UI label (what the user sees) | Level | Storage entity | Distinguishing field |
|---|---|---|---|
| **Task** | L0 | `ProjectTimeline` | root of a hierarchy; owns `startDate`/`endDate` that bound its children |
| **Subtask** | L1 | `ProjectTask` | `parentTaskId == null`, `timelineId` = its Task's id |
| **Subitem** | L2 | `ProjectTask` | `parentTaskId` = the id of an L1 `ProjectTask` |

So "Subtask" and "Subitem" are the *same TypeScript type* (`ProjectTask`); only `parentTaskId`
tells them apart. A `ProjectTask` can never have `parentTaskId` pointing at another task that itself
has a `parentTaskId` — that would be a 4th level and is rejected by `assertCanNestUnder` (see
`04-domain-logic.md`).

`ProjectMilestone` is a fourth, separate entity: a diamond marker pinned to a date, attached to a
Task (`timelineId`) but **not part of the Task/Subtask/Subitem tree** — it never nests, never has
children, and is rendered only as a chart overlay on its parent Task's bar.

## Enums

```ts
type TaskStatus = 'not_started' | 'in_progress' | 'blocked' | 'completed' | 'cancelled'
type TaskPriority = 'low' | 'medium' | 'high' | 'critical'
type TimelineStatus = 'not_started' | 'in_progress' | 'completed' | 'cancelled' | 'archived'
type MilestoneStatus = 'pending' | 'at_risk' | 'completed' | 'missed'
type DependencyType = 'FS' | 'SS' | 'FF' | 'SF'   // only 'FS' (Finish-to-Start) is ever created by the UI today
type ProjectRole = 'project_admin' | 'project_manager' | 'team_leader' | 'member' | 'viewer'
type ActivityEntityType = 'Timeline' | 'Milestone' | 'Task' | 'Dependency' | 'Baseline'
type GanttZoom = 'day' | 'week' | 'month'
type TimelineViewMode = 'gantt' | 'list' | 'baseline'
```

`TimelineStatus` has one extra state (`'archived'`) that `TaskStatus` doesn't. When a Task's status
needs to be shown using Task-status UI (e.g. the shared status glyph in the Gantt left grid), it's
mapped: `archived → cancelled`, everything else passes through unchanged (see `mapTimelineStatus` —
duplicated verbatim in both `GanttBoard.tsx` and `TimelineListView.tsx`).

## Entities

### `TimelineMember` (assignee/owner option — **not owned by Timeline**, see `02-api-and-persistence.md`)

```ts
type TimelineMember = {
  id: string            // prefers company employeeId; falls back to the org-chart node id
  name: string
  email: string
  role: ProjectRole      // derived from the org-chart role text, see mapOrgRoleToProjectRole
  title?: string         // job title, from employee catalog or org node role text
  avatarUrl?: string
}
```

### `ProjectTimeline` (= UI "Task", L0)

```ts
type ProjectTimeline = {
  id: string
  projectId: string
  name: string
  description: string
  startDate: string       // ISO 'YYYY-MM-DD', bounds all child Subtasks/Subitems
  endDate: string
  ownerId: string          // a TimelineMember.id
  colorIndex: number       // 0..99 preset hue index — fallback when colorHex unset
  colorHex?: string | null // free-pick base hex; when set, L0/L1/L2 washes derive from ITS hue (see 04)
  status: TimelineStatus
  archived: boolean        // soft delete
  createdBy: string
  createdAt: string        // ISO datetime
  updatedAt: string
}
```

### `ProjectMilestone`

```ts
type ProjectMilestone = {
  id: string
  projectId: string
  timelineId: string          // parent Task — chart-overlay only, not a tree node
  name: string
  description: string
  milestoneDate: string       // single date, not a range
  ownerId: string
  status: MilestoneStatus      // recomputed client-side via deriveMilestoneStatus after every load/mutation
  relatedTaskIds: string[]     // ProjectTask ids this milestone tracks, for its own progress %
  isCritical: boolean
  archived: boolean
  createdBy: string
  createdAt: string
  updatedAt: string
}
```

### `ProjectTask` (= UI "Subtask" when `parentTaskId == null`, or "Subitem" when it is set)

```ts
type ProjectTask = {
  id: string
  projectId: string
  timelineId: string            // always the top-level Task, even for a Subitem (denormalized)
  milestoneId: string | null    // only meaningful for Subtasks; a Subitem's is typically null
  parentTaskId: string | null   // null = Subtask (L1); set = Subitem (L2), value = parent Subtask's id
  name: string
  description: string
  assigneeId: string | null
  reporterId: string
  startDate: string
  dueDate: string                // NOTE: field is `dueDate`, not `endDate` (Timeline uses `endDate`)
  estimatedEffort: number         // used as the rollup weight; treated as max(1, value) — 0/negative never zeroes a weight
  actualEffort: number
  priority: TaskPriority
  status: TaskStatus
  progressPercent: number         // 0..100; for a Subitem this is always exactly 0 or 100 (see 03/04)
  labels: string[]
  archived: boolean
  createdBy: string
  createdAt: string
  updatedAt: string
  completedAt: string | null      // set on transition into 'completed', cleared on transition out
}
```

### `TaskDependency`

```ts
type TaskDependency = {
  id: string
  projectId: string
  sourceTaskId: string   // predecessor
  targetTaskId: string   // successor (the one that "depends on" source)
  type: DependencyType    // UI only ever creates 'FS'
  lagDays: number          // UI only ever creates 0
  createdBy: string
  createdAt: string
}
```

### `TaskComment` / `TaskAttachment`

```ts
type TaskComment = { id: string; taskId: string; projectId: string; body: string; createdBy: string; createdAt: string }
type TaskAttachment = { id: string; taskId: string; projectId: string; fileName: string; fileSize: number; mimeType: string; url: string; createdBy: string; createdAt: string }
```

`TaskComment` has a working create path (`addComment`) but no read/list UI was found anywhere in the
Timeline module — it's write-only from the UI's perspective today. `TaskAttachment` has no create/read
path at all; it exists only as a type and an empty array slot in the bundle.

### Baseline snapshot

```ts
type BaselineSnapshot = {
  timelineStartDate: string
  timelineEndDate: string
  tasks: { taskId: string; startDate: string; dueDate: string; status: TaskStatus; progressPercent: number }[]
  milestones: { milestoneId: string; milestoneDate: string; status: MilestoneStatus }[]
}

type TimelineBaseline = {
  id: string
  projectId: string
  timelineId: string       // one baseline row per Task (per ProjectTimeline)
  name: string
  baselineDate: string      // the day it was taken
  snapshot: BaselineSnapshot // immutable point-in-time copy
  createdBy: string
  createdAt: string
}
```

"One project baseline" in the UI is really **N baseline rows, one per non-archived Task**, that all
share the same `(baselineDate, name)` pair. `BaselineCompareView` groups rows back into a batch by
that composite key — see `06-list-and-baseline-views.md`.

### `ActivityLog`

```ts
type ActivityLog = {
  id: string
  projectId: string
  entityType: ActivityEntityType
  entityId: string
  action: string           // free-form verb: 'created' | 'updated' | 'archived' | 'dates_changed' | 'duplicated' | 'comment_added' | 'removed'
  oldValue: string | null
  newValue: string | null
  changedBy: string
  changedAt: string
}
```

Every mutating store action appends one of these (see `03-state-management.md`). **No viewer UI for
this log exists in the Timeline module** — it's collected but not displayed today.

### `TimelineAlert`

```ts
type TimelineAlertKind =
  | 'task_overdue' | 'task_due_soon' | 'milestone_due_soon' | 'milestone_overdue'
  | 'task_blocked' | 'dependency_at_risk' | 'timeline_at_risk' | 'progress_behind'

type TimelineAlert = {
  id: string
  kind: TimelineAlertKind
  severity: 'info' | 'warning' | 'critical'
  entityType: ActivityEntityType | 'Project'
  entityId: string
  message: string   // pre-formatted Vietnamese sentence, e.g. `"${task.name}" quá hạn`
}
```

Computed by `store.getAlerts()` → `detectTimelineAlerts()` (see `04-domain-logic.md`). **Also has no
consumer UI today** — `useTimelineStore` returns `alerts` but `ProjectTimelineTab.tsx` never reads it.
An existing internal doc (`docs/timeline/USAGE.md`) confirms this was deliberately pulled out pending
a future "Inbox" feature.

### Filters

```ts
type TimelineFilters = {
  timelineId: string | 'all'
  assigneeId: string | 'all'
  status: TaskStatus | 'all'
  priority: TaskPriority | 'all'
  milestoneId: string | 'all'
  overdueOnly: boolean
  blockedOnly: boolean
  search: string
  dateFrom: string | null
  dateTo: string | null
}

const DEFAULT_FILTERS: TimelineFilters = {
  timelineId: 'all', assigneeId: 'all', status: 'all', priority: 'all', milestoneId: 'all',
  overdueOnly: false, blockedOnly: false, search: '', dateFrom: null, dateTo: null,
}
```

The store exposes `setFilters`, and `ProjectTimelineTab` does call `filterTasks(state.tasks,
state.filters, state.demoToday)` every render — but **nothing in the UI ever calls `setFilters`**, so
in practice filters always equal `DEFAULT_FILTERS` and the only visible effect of the filter pass is
dropping archived tasks (see `04-domain-logic.md` for the full predicate, in case a filter bar is
added back later).

### The load bundle

```ts
type ProjectTimelineBundle = {
  projectId: string
  members: TimelineMember[]           // NOT persisted by Timeline — always re-derived from org chart, see 02
  timelines: ProjectTimeline[]
  milestones: ProjectMilestone[]
  tasks: ProjectTask[]
  dependencies: TaskDependency[]
  comments: TaskComment[]
  attachments: TaskAttachment[]
  baselines: TimelineBaseline[]
  activityLogs: ActivityLog[]
  demoRole: ProjectRole                // which permission role the demo session acts as
  currentUserId: string
}
```

## Vietnamese labels (verbatim — reuse these strings if the Flutter UI stays Vietnamese)

```ts
STATUS_LABEL_VI = {
  not_started: 'Chưa bắt đầu', in_progress: 'Đang làm', blocked: 'Bị chặn',
  completed: 'Hoàn thành', cancelled: 'Đã hủy',
}
PRIORITY_LABEL_VI = { low: 'Thấp', medium: 'Trung bình', high: 'Cao', critical: 'Khẩn cấp' }
TIMELINE_STATUS_LABEL_VI = {
  not_started: 'Chưa bắt đầu', in_progress: 'Đang làm', completed: 'Hoàn thành',
  cancelled: 'Đã hủy', archived: 'Đã lưu trữ',
}
MILESTONE_STATUS_LABEL_VI = { pending: 'Chưa đạt', at_risk: 'Rủi ro', completed: 'Đã đạt', missed: 'Trễ mốc' }
WORK_LEVEL_LABEL_VI = { 0: 'Task', 1: 'Subtask', 2: 'Subitem' }   // domain/workLevels.ts
```

## The parent `Project` entity (for context only — owned by a sibling module)

Timeline's tab is hosted inside a project detail page. The project itself
(`src/modules/projects/boards/types.ts`) is:

```ts
type ProjectStatus = 'done' | 'in_progress'
type ProjectRow = {
  id: string
  endUser: string
  endUserImageUrl?: string | null
  endUserAddress?: string | null
  project: string        // display name, shown as page title
  scope: string           // shown as page subtitle
  location: string
  status: ProjectStatus
  valueUsd: string
  valueVnd: string
  year: number
  startDate: string       // display string e.g. "15/03/2026", NOT the same format as Timeline's ISO dates
  endDate: string
}
```

`ProjectTimelineTab` receives one `project: ProjectRow` prop and uses `project.id` as the
`projectId` key for the store, plus `project.project/scope/location/startDate/endDate/endUser*` for
the PDF cover sheet (see `09-pdf-export.md`).
