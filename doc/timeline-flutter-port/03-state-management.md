# State management

Source: `src/modules/projects/boards/timeline/store/timelineStore.ts` (1032 lines) and
`hooks/useTimelineStore.ts` (78 lines). This is the most business-logic-dense file in the feature —
read it alongside `04-domain-logic.md`, since every action here is really "validate with a pure
domain function, call the API, then reconcile local state."

## The store is a hand-rolled observable, one instance per project

```ts
function createTimelineStore(projectId: string): TimelineStore {
  let state = loadingState(projectId)
  const listeners = new Set<() => void>()
  function commit(next) { state = next; listeners.forEach(l => l()) }
  return {
    getSnapshot: () => state,
    subscribe: (listener) => { listeners.add(listener); return () => listeners.delete(listener) },
    getAlerts: () => detectTimelineAlerts({ ...state, today: state.demoToday }),
    hydrate, refreshMembers, setView, setZoom, setFilters,
    selectTask, selectMilestone, selectTimeline, toggleExpanded, setSelectedBaseline,
    createTimeline, updateTimeline, archiveTimeline, duplicateTimeline,
    createMilestone, updateMilestone, archiveMilestone,
    createTask, updateTask, updateTaskDates, archiveTask,
    addDependency, removeDependency,
    createBaseline, createProjectBaselines,
    addComment,
  }
}
```

`useTimelineStore(projectId)` (the React binding) keeps a module-level cache:

```ts
const stores = new Map<string, TimelineStore>()
function getStore(projectId) {
  let s = stores.get(projectId)
  if (!s) { s = createTimelineStore(projectId); stores.set(projectId, s); void s.hydrate() }
  return s
}
export function useTimelineStore(projectId: string) {
  const store = useMemo(() => getStore(projectId), [projectId])
  const state = useSyncExternalStore(store.subscribe, store.getSnapshot)
  const alerts = useMemo(() => store.getAlerts(), [state])
  return { state, alerts, actions: { /* every method above */ } }
}
```

There's also a `STORE_EPOCH` constant (`'2026-08-03-empty'`) checked on every `getStore` call — bump
it to force-clear all cached stores (used when the demo seed shape changes and old localStorage would
otherwise poison new sessions), plus an HMR dispose hook that clears the cache on hot-reload.

**Flutter equivalent**: a repository of `ChangeNotifier`/`Cubit` instances keyed by `projectId`,
created lazily and cached (e.g. in a `Map` inside a service locator, or via a keyed provider family in
Riverpod: `timelineStoreProvider.family<String>()`). `hydrate()` fires automatically on first access,
exactly like the `void s.hydrate()` here.

## `TimelineStoreState` shape

```ts
type TimelineStoreState = {
  projectId: string
  loadStatus: 'loading' | 'ready' | 'error'
  loadError: string | null
  members: TimelineMember[]
  timelines: ProjectTimeline[]
  milestones: ProjectMilestone[]
  tasks: ProjectTask[]
  dependencies: TaskDependency[]
  comments: TaskComment[]
  attachments: TaskAttachment[]
  baselines: TimelineBaseline[]
  activityLogs: ActivityLog[]
  demoRole: ProjectRole
  currentUserId: string
  demoToday: string            // frozen at '2026-03-15' — see 00-overview.md invariant #5
  view: TimelineViewMode        // 'gantt' | 'list' | 'baseline'
  zoom: GanttZoom                // 'day' | 'week' | 'month'
  filters: TimelineFilters       // always DEFAULT_FILTERS in practice today, see 01-data-model.md
  selectedTaskId: string | null
  selectedMilestoneId: string | null
  selectedTimelineId: string | null   // exactly one of these three is non-null when a drawer is open
  expandedIds: string[]                // tree-expand state, as an array (Set on the wire would need JSON handling)
  selectedBaselineId: string | null
}
```

## `hydrate()`

```
loading → fetchProjectTimelineBundle(projectId) → buildInitialState(bundle) → ready
                                                 ↘ on throw → error, loadError = e.message
```

`buildInitialState`:

1. Normalize every date field through `normalizeIsoDate` with fallbacks (`today`, `start+14`); flip
   start/end if inverted (defensive — same sanitization the demo repo already does, done again here so
   an `api`-mode bundle gets the same protection).
2. `tasks = applyParentProgressRollup(sanitizedTasks)` — bottom-up rollup, see `04-domain-logic.md`.
3. `timelines = applyTimelineStatusRollup(sanitizedTimelines, tasks)`.
4. `milestones = sanitizedMilestones.map(ms => ({ ...ms, status: deriveMilestoneStatus(ms, tasks, '2026-03-15') }))`
   — note the literal `'2026-03-15'`, not `state.demoToday` (there is no state yet at this point; it's
   the same constant hardcoded a second time).
5. Defaults: `view='gantt'`, `zoom='week'`, `filters=DEFAULT_FILTERS`, no selection,
   `selectedBaselineId = baselines[0]?.id ?? null`.
6. `expandedIds = defaultExpandedIds(bundle)`: **every non-archived Task (Timeline) id, plus every
   non-archived Task/Subtask (`ProjectTask`) id** — i.e. the tree starts **fully expanded** down to
   Subitems on first load. (Milestones are never in `expandedIds` — they're not tree nodes.)

## Simple setters

`setView`, `setZoom`, `setFilters` (shallow-merges the patch into `state.filters`), `toggleExpanded`
(Set-based add/remove, re-serialized to array), `setSelectedBaseline` — all pure `patchState` calls,
no validation, no API call.

`selectTask` / `selectMilestone` / `selectTimeline` each set their own id and **null out the other
two** — selection is single-focus by construction, not by a UI-level check.

`refreshMembers()`: re-runs `fetchTimelineMembersFromOrg`; on failure, catches and does nothing
(keeps the previous member list rather than showing an error — a deliberate "org chart hiccup
shouldn't break the drawer you already have open" choice).

## Permission gate helper

```ts
function assertTaskManage(task?: ProjectTask) {
  if (task && state.demoRole === 'member') {
    assertCan(state.demoRole, 'task.update_assigned')          // throws if even this is missing
    if (task.assigneeId !== state.currentUserId) {
      throw new Error('Bạn chỉ có thể cập nhật task được giao cho mình.')
    }
    return
  }
  assertCan(state.demoRole, 'task.manage')                       // everyone else needs the broad permission
}
```

Used by `updateTask` and `updateTaskDates` — this is the one place where permission checking depends
on *data* (whether you're the assignee), not just role.

## Mutating actions, in full

Every action below follows the same shape unless noted: **permission check → domain validation →
`timelineApi.*` call → local reconciliation (`refreshDerived` + `appendActivity`) → `commit`.**
`refreshDerived(tasks, timelines?)` re-runs the same two rollups as `buildInitialState` steps 2–4 (plus
milestone status) on the current in-memory arrays, so every mutation keeps derived state consistent
without a full reload.

### `createTimeline(input)` — new Task (L0)

1. `assertCan(role, 'timeline.manage')`.
2. Normalize + validate `startDate`/`endDate` are valid ISO and `start <= end`.
3. `assertUniqueTimelineName(input.name, state.timelines)` — project-wide among non-archived Tasks.
4. `apiCreateTimeline(...)`.
5. Append activity log (`'created'`).
6. **Auto-expand the new Task's id** so it opens expanded (it has no children yet, but this keeps it
   consistent with "everything starts expanded").

### `updateTimeline(id, patch)` — edit a Task, **cascading date clamp**

1. Permission `timeline.manage`.
2. Resolve next `startDate`/`endDate` (patch value if present else existing), validate, `start <= end`.
3. If renaming, re-check uniqueness (excluding itself).
4. `apiUpdateTimeline(...)`.
5. **If dates changed**, for every direct Subtask of this Task (`timelineId` match, `parentTaskId ==
   null`, not archived):
   - `clampDateRangeToBounds(sub.start, sub.due, newTlStart, newTlEnd)` — **clamp only, no shift**. A
     Subtask that's still fully inside the new window is left completely untouched (no write at all,
     even if the Task moved around it).
   - If the clamped result differs from the Subtask's current dates: validate `start<=end`, persist
     via `apiUpdateTaskDates`, then repeat the exact same clamp-only pass **one level down** for that
     Subtask's own Subitems, against the *Subtask's new* window (not the Task's).
6. `refreshDerived` on the whole task list + the patched timeline.

> This is a **clamp cascade**, not a **shift cascade** — contrast with `updateTaskDates` below, which
> *does* shift children by the same delta. Getting this asymmetry backwards is the easiest way to
> silently change scheduling behavior in a port.

### `archiveTimeline(id)`

Permission `timeline.manage` → `apiArchiveTimeline` → locally set `archived: true, status:
'archived'`. Children are **not** archived automatically by this action (the UI's delete-confirm copy
warns "Subtask / Subitem liên quan sẽ bị ẩn" — hidden by the tree-visibility logic because their
parent is gone, not because they're individually archived).

### `duplicateTimeline(id)`

1. Permission `timeline.manage`.
2. Client-side pre-check: `assertUniqueTimelineName(`${source.name} (copy)`, state.timelines)` — fails
   fast before the network round-trip if a previous duplicate already used that exact name.
3. `apiDuplicateTimeline` does the actual deep copy server/demo-side: new ids for the Task, every
   descendant Task/Subtask/Subitem, and every dependency between them (dependencies pointing outside
   the copied subtree are dropped); the copy's Task status is `'not_started'`, and every copied
   `ProjectTask`'s status/progress/actualEffort/completedAt are reset to fresh values — only
   dates/assignee/priority/names carry over.
4. Merge results into state, `refreshDerived`.

### `createMilestone` / `updateMilestone` / `archiveMilestone`

Straightforward CRUD gated by `milestone.manage`. `updateMilestone` and any task-affecting action both
end by recomputing `status` via `deriveMilestoneStatus(milestone, tasks, state.demoToday)` — milestone
status is **always derived, never stored as user input** beyond its initial `'pending'`.

### `createTask(input)` — new Subtask or Subitem

1. Permission `task.manage`.
2. Resolve parent Task (must exist, not archived).
3. Validate `startDate <= dueDate`.
4. `assertCanNestUnder(input.parentTaskId, state.tasks)` — throws if you try to nest under something
   that already has a parent (blocks a 4th level).
5. `isSubitem = Boolean(input.parentTaskId)`.
6. **Clamp the new item's dates into its container's bounds**:
   - Subitem → clamp into its parent Subtask's `[startDate, dueDate]`.
   - Subtask → clamp into its Task's `[startDate, endDate]`.
7. `assertUniqueTaskNameAmongSiblings(...)` — see `04-domain-logic.md` for the exact sibling/parent-name
   scope rules.
8. `apiCreateTask(...)`.
9. Auto-expand: the new item's own id, its Task's id, and (if it's a Subitem) its parent Subtask's id
   — so the newly created row is immediately visible without the user manually expanding anything.
10. `refreshDerived`.

### `updateTask(id, patch)` — the busiest action

1. `assertTaskManage(existing)` (see the permission helper above).
2. If `parentTaskId` is changing, re-run `assertCanNestUnder` against the *other* tasks (excluding
   itself) — reparenting a Subtask into a Subitem, or vice versa, is validated the same way as create.
3. If `name` or `parentTaskId` is changing, re-run the uniqueness check against the *new* scope.
4. **Status/progress coupling** (computed before the API call, then sent together as one patch):
   - If the (possibly newly-reparented) item is a **Subitem**: `progressPercent` is entirely
     status-driven — `completed → 100`, anything else `→ 0`. There is no independent progress value for
     a Subitem; the UI never shows a slider for one (see `07-drawers-dialogs-menus.md`).
   - Else (**Subtask**): `status === 'completed' → progressPercent = 100`. Otherwise
     `progressPercent` passes through unchanged from the patch (or the existing value) — this is the
     manual slider value, *but only when the Subtask has no Subitem children*; when it does, the
     drawer UI never renders that slider and progress is fully rollup-driven instead (see below).
5. `apiUpdateTask(id, { ...patch, status, progressPercent, priority: patch.priority ?? existing.priority })`.
6. **Downward cascade** (the one exception to "children drive parents"): if this is a Subtask
   (`!isSubitem`) and its status is transitioning *into* `'completed'` from something else, loop over
   every non-archived Subitem child and force `apiUpdateTask(child.id, { status: 'completed',
   progressPercent: 100 })`. Un-completing a Subtask does **not** reverse this — children stay
   completed unless edited individually.
7. `refreshDerived` on the merged task list — this re-applies the normal upward rollup too, so after
   step 6 the Subtask's own rollup-computed progress/status will trivially agree with what was just
   force-set on its children.

### `updateTaskDates(id, dates)` — Gantt bar drag/resize, **shift-then-clamp cascade**

1. `assertTaskManage(existing)`.
2. Validate `startDate <= dueDate`.
3. Clamp the dragged item's own new dates into its container's bounds (parent Subtask's window if
   it's a Subitem; its Task's window if it's a Subtask) — same `clampDateRangeToBounds` used
   everywhere else.
4. `deltaStart = daysBetween(existing.startDate, clampedNewStartDate)`.
5. **Only if this item is a Subtask** (`!existing.parentTaskId`): for every non-archived Subitem
   child, compute a **rigid shift** (`addDays(child.start, deltaStart)`, `addDays(child.due,
   deltaStart)`) — the whole group moves together like one object — **then clamp that shifted result**
   into the Subtask's *new* window. If a shifted-then-clamped child ends up with the same dates it
   already had, skip the write entirely.
6. Persist the dragged item's own new dates first, then each changed child's.
7. `refreshDerived`.

> Compare step 5 here to `updateTimeline`'s cascade: dragging a **Subtask** bar **shifts** its
> Subitems by the same delta (they visually move with it, then get clipped if they'd overflow).
> Resizing/moving a **Task**'s date range via `updateTimeline` does **not** shift its Subtasks at all
> — it only clips the ones that no longer fit. Two different cascade strategies, by design, one level
> apart in the tree.

### `archiveTask(id)`

Permission `task.manage` → `apiArchiveTask` → set `archived: true` → `refreshDerived` (so if this was
the last active Subitem, its parent Subtask's rollup recalculates immediately).

### `addDependency` / `removeDependency`

Permission `dependency.manage`. `addDependency` resolves both tasks (must exist) then
`validateNewDependency(state.dependencies, source, target)` — throws on self-dependency or if adding
the edge would create a cycle (full DFS, see `04-domain-logic.md`) — **before** calling the API.

### `createBaseline(input)` / `createProjectBaselines()`

`createBaseline`: permission `baseline.manage`, Task must exist, one API call, select it as the active
baseline (`selectedBaselineId`).

`createProjectBaselines()`: the "Chốt baseline dự án" one-click action. Throws if there are zero
non-archived Tasks. Otherwise: `baselineDate = todayIso()` (real calendar today, **not**
`state.demoToday`), `name = `Baseline dự án · ${formatDateVi(baselineDate)}``, then loops
**sequentially** (`for...of` with `await` inside, not `Promise.all`) creating one baseline per Task
with that exact same `name`+`baselineDate` pair — this shared pair is what lets
`BaselineCompareView` regroup them into a single logical batch later. One activity-log entry is
appended for the whole batch (referencing the first created baseline's id, with a note of how many
Tasks were included), not one per Task.

### `addComment(taskId, body)`

Permission `comment.create`, task must exist, body must be non-empty after trim, one API call.

## Activity logging

`appendActivity(entityType, entityId, action, oldValue, newValue)` builds one `ActivityLog` (id via a
simple in-memory incrementing counter combined with `Date.now()`, not from the API); `withActivity`
merges a state patch together with `activityLogs: [...state.activityLogs, log]` in one `commit`. Every
mutating action above calls this — even though nothing currently renders `state.activityLogs`.
