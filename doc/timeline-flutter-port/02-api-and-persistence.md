# API contract and persistence

Source: `src/modules/projects/boards/timeline/api/timelineApi.ts` (722 lines), plus
`src/shared/api/http.ts`, `src/shared/config/dataSource.ts`, `src/demo/boards/timeline/demoTimelineRepo.ts`
(persistence shape only — seed content not reproduced here), and the org-chart read boundary.

## Data-source gate

```ts
// src/shared/config/dataSource.ts
type DataSource = 'demo' | 'api'
getDataSource(): DataSource     // reads VITE_DATA_SOURCE, defaults to 'demo'
getApiBaseUrl(): string          // reads VITE_API_BASE_URL, defaults to 'http://localhost:8000'
```

Every single function in `timelineApi.ts` starts with the same branch:

```ts
if (getDataSource() === 'api') {
  return apiFetch<T>(url, init)   // real HTTP call
}
// ...otherwise operate on the in-memory/localStorage demo bundle and return a locally-built object
```

There is no partial mode — the whole feature is either fully "demo" or fully "api" for a given app
build. **In a Flutter port, this maps to a repository interface with two implementations** (a fake
in-memory one for previews/tests, a real HTTP one for production) selected once at composition root —
see `11-flutter-porting-guide.md`.

### HTTP helper

```ts
class ApiError extends Error { status: number }

async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  // GET https://{apiBaseUrl}{path}, Accept: application/json, spreads init
  // non-2xx -> throws ApiError(bodyText || statusText, status)
  // 204 -> returns undefined
  // else -> returns res.json()
}
```

## REST contract (target — what "api" mode calls)

Base path: `/api/projects/{projectId}/...` (project id URL-encoded).

| Concern | Method | Path | Request body | Response |
|---|---|---|---|---|
| Load everything | GET | `/timeline` | — | `ProjectTimelineBundle` (members are overwritten client-side afterward, see below) |
| Create Task (L0) | POST | `/timelines` | `CreateTimelineInput` | `ProjectTimeline` |
| Update Task | PATCH | `/timelines/{id}` | `UpdateTimelineInput` | `ProjectTimeline` |
| Archive Task | POST | `/timelines/{id}/archive` | — | `void` |
| Duplicate Task | POST | `/timelines/{id}/duplicate` | — | `DuplicateTimelineResult` |
| Create Subtask/Subitem | POST | `/tasks` | `CreateTaskInput` | `ProjectTask` |
| Update Subtask/Subitem | PATCH | `/tasks/{id}` | `UpdateTaskInput` | `ProjectTask` |
| Reschedule (drag) | PATCH | `/tasks/{id}/dates` | `{ startDate, dueDate }` | `ProjectTask` |
| Archive Subtask/Subitem | POST | `/tasks/{id}/archive` | — | `void` |
| Create Milestone | POST | `/milestones` | `CreateMilestoneInput` | `ProjectMilestone` |
| Update Milestone | PATCH | `/milestones/{id}` | `UpdateMilestoneInput` | `ProjectMilestone` |
| Archive Milestone | POST | `/milestones/{id}/archive` | — | `void` |
| Add dependency | POST | `/dependencies` | `{ sourceTaskId, targetTaskId, type, lagDays }` | `TaskDependency` |
| Remove dependency | DELETE | `/dependencies/{id}` | — | `void` |
| Create baseline | POST | `/baselines` | `{ timelineId, name, baselineDate }` | `TimelineBaseline` |
| Add comment | POST | `/tasks/{id}/comments` | `{ body }` | `TaskComment` |

```ts
type CreateTimelineInput = Pick<ProjectTimeline, 'name'|'description'|'startDate'|'endDate'|'ownerId'|'colorIndex'> & { colorHex?: string | null }
type UpdateTimelineInput = Partial<Pick<ProjectTimeline, 'name'|'description'|'startDate'|'endDate'|'ownerId'|'status'|'colorIndex'|'colorHex'>>

type CreateTaskInput = {
  timelineId: string; name: string; description: string; startDate: string; dueDate: string
  assigneeId: string | null; priority: TaskPriority; estimatedEffort: number
  milestoneId?: string | null; parentTaskId?: string | null; labels?: string[]
}
type UpdateTaskInput = Partial<Pick<ProjectTask,
  'name'|'description'|'assigneeId'|'priority'|'status'|'progressPercent'|'estimatedEffort'
  |'actualEffort'|'labels'|'milestoneId'|'parentTaskId'|'startDate'|'dueDate'>>

type CreateMilestoneInput = Pick<ProjectMilestone, 'timelineId'|'name'|'description'|'milestoneDate'|'ownerId'|'isCritical'> & { relatedTaskIds?: string[] }
type UpdateMilestoneInput = Partial<Pick<ProjectMilestone, 'name'|'description'|'milestoneDate'|'ownerId'|'isCritical'|'relatedTaskIds'>>

type DuplicateTimelineResult = { timeline: ProjectTimeline; milestones: ProjectMilestone[]; tasks: ProjectTask[]; dependencies: TaskDependency[] }
```

Nothing calls the `archiveMilestone`/`removeDependency`/`addComment` REST paths speculatively — they
exist and are wired to store actions, ready for a real backend.

## Demo persistence ("demo" mode — the only mode this app ships running today)

- In-memory `Map<projectId, ProjectTimelineBundle>` + mirrored to `localStorage` under key
  `qv.demo.timeline.v3.{projectId}` (older `v1`/`v2` keys are recognized as "this is timeline demo
  data" for cleanup purposes but not read).
- Every write in `timelineApi.ts`'s demo branch: read the bundle, produce the new entity locally
  (`nextDemoId('tk'|'tl'|'ms'|'dep'|'bl'|'cmt', projectId)` → `` `${prefix}-${projectId}-${Date.now()}-${random}` ``),
  splice it into the bundle, call `replaceDemoTimelineBundle(projectId, nextBundle)` which persists to
  both the Map and localStorage, then return the new/updated entity — mirroring exactly what a real
  API response would look like.
- On load, `sanitizeTimelineBundleDates()` coerces every date field through `normalizeIsoDate` with
  fallbacks (`today` / `today+14`) and swaps start/end if inverted, so corrupted localStorage or a
  future looser API can never produce an unparseable Gantt range.
- Seed data comes from `src/demo/boards/timeline/seed.ts` (`createTimelineSeed`) — not reproduced
  here since it's just sample content, not behavior.

**A Flutter port does not need to reproduce this exact mechanism** unless the port also wants an
offline/demo mode. If it does, the pattern (local key-value store + synchronous same-shape mutation +
`Date.now()+random` id generation) is simple to redo with `SharedPreferences`/`Hive`/an in-memory map.

## Members are not Timeline's data — they come from the Org Chart, read-only

This is the one place Timeline reaches outside its own module for live data, and it's important to
get the direction right: **Timeline never writes org-chart data, and the org-chart feature knows
nothing about Timeline.**

```ts
// timelineApi.ts
async function fetchTimelineMembersFromOrg(projectId): Promise<TimelineMember[]> {
  const [chart, employees] = await Promise.all([
    fetchProjectOrgChart(projectId),        // org module's own API
    listEmployees().catch(() => []),         // company directory, tolerated to fail
  ])
  return timelineMembersFromOrgChart(chart, new Map(employees.map(e => [e.id, e])))
}
```

`fetchProjectTimelineBundle()` always overwrites whatever `members` the bundle/API returned with a
fresh call to this function — so the backend's own `members` field in a `GET /timeline` response is
effectively ignored today. `store.refreshMembers()` re-runs just this call (used whenever a
drawer/dialog opens, to catch org-chart edits made elsewhere in the app) and silently keeps the old
list if the org chart call fails.

### Mapping rules (`orgTimelineMembers.ts`)

- A org node counts as "assigned" only if it has a non-empty `name` or an `employeeId`
  (`isOrgMemberAssigned`) — empty skeleton slots are dropped entirely, so an unset org chart yields
  **zero** assignee options (every "Phụ trách" dropdown in Timeline shows an empty-state message
  instead, see `07-drawers-dialogs-menus.md`).
- Member id = `employeeId` if the node was picked from the company directory, else the org node's own
  id (`orgMemberAssigneeId`).
- Title/avatar prefer the company employee record over the org node's own freeform fields.
- Role text → `ProjectRole` (`mapOrgRoleToProjectRole`, case-insensitive substring match, first match
  wins in this order): contains "admin" → `project_admin`; "project manager" or exactly "pm" →
  `project_manager`; contains "team lead"/"site manager"/"leader" or exactly "sm" → `team_leader`;
  contains "view" → `viewer`; else → `member`.
- Sort: `project_manager` role first, then alphabetical by name (Vietnamese collation).
- `defaultTimelineAssigneeId(members, currentUserId)`: the current user if they're on the chart, else
  the first member in the sorted list, else `''` (used to pre-fill every "Phụ trách" field when
  opening a create dialog).

### Org-chart types Timeline depends on (read-only)

```ts
type ProjectOrgMemberNode = {
  id: string; employeeId: string | null; name: string; role: string
  email?: string; phone?: string; avatarUrl?: string; isRoot?: boolean
  toneId?: string; customColor?: string; position: { x: number; y: number }
}
type ProjectOrgChartData = { projectId: string; nodes: ProjectOrgMemberNode[]; edges: ProjectOrgEdge[]; updatedAt: string | null }
isOrgChartUnset(chart) // true if no nodes, or every node has empty name AND no employeeId
```

## Error and UX contract

- Every store action is `async` and can throw; every call site in `ProjectTimelineTab.tsx` /
  `GanttBoard.tsx` wraps the call in `try/catch` and routes the message into either a local `error`
  state shown via `AlertDialog`, or a per-dialog inline error callback. Errors are plain `Error`
  objects with **Vietnamese-language messages already formatted** — there's no error-code layer to
  translate.
- Domain validation (dates, uniqueness, nesting, permissions, dependency cycles) runs before any
  network call, in the store action itself, from the pure `domain/*` modules — see
  `04-domain-logic.md` and `03-state-management.md`.
