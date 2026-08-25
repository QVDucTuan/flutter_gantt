# Timeline feature — full reference for a Flutter re-implementation

This folder is a complete, code-verified reference for the **Timeline** feature of the QV Agent Hub
web app (React + TypeScript). It exists so a coding agent working in a **different (Flutter/Dart)
codebase** can rebuild the same feature — same data model, same business rules, same interaction
behavior — without access to this React repository.

Everything in these files was extracted by reading the actual current source, not by memory or by
trusting older specs. Where the codebase already had docs (`docs/timeline/*.md`) that disagreed with
the real code, this package follows the **code**, and the discrepancy is called out explicitly (see
`09-pdf-export.md` for one confirmed example).

## What the feature is

"Timeline" is a per-project Gantt/List/Baseline planning view, reached at
`/boards/{projectId}?tab=Timeline`. It has three interchangeable views over the same data:

- **Gantt** — a two-pane board: a left work-item grid (tree of Task → Subtask → Subitem) and a right
  scrollable date chart with draggable schedule bars. This is the view shown by default and the one
  in the reference screenshot (toolbar segmented control "Gantt | List | Baseline" bottom-right,
  today marker, colored bars, tree rows on the left).
- **List** — the same tree flattened into a sortable/resizable data table.
- **Baseline** — compares a frozen snapshot ("baseline") of dates/progress against current actual
  values, grouped by the date+name the snapshot batch was taken.

A right-side drawer opens for editing a single Task/Subtask/Subitem/Milestone. Small centered dialogs
handle creation. A project-detail-page **Footer** (shared chrome, not part of this module) hosts the
view switch, zoom, PDF export, fullscreen and settings controls — see `08-toolbar-and-footer.md`.

## Source tech stack (context for translating decisions, not to be copied)

- React 19 + TypeScript, Tailwind CSS v4 utility classes + CSS custom properties for theming.
- **No external state library.** The store is a hand-rolled observable (`subscribe`/`getSnapshot`,
  consumed via `useSyncExternalStore`) — one instance per `projectId`, cached in a module-level `Map`.
  This maps cleanly to a `ChangeNotifier`/`Cubit`/`Bloc` keyed by project id in Flutter.
  See `03-state-management.md`.
- Persistence is gated by an env flag (`demo` in-memory+localStorage vs `api` REST) behind one
  module, `timelineApi.ts` — the *only* place allowed to talk to the network or the demo store. See
  `02-api-and-persistence.md`.
- PDF export rasterizes the live DOM (`html-to-image`) and tiles it into a multi-page A4 landscape
  PDF (`jspdf`). This is inherently web-specific; `09-pdf-export.md` describes the *behavior* to
  reproduce (what gets exported, page count logic, A4 dimensions) rather than the DOM hacks.

## Reading order

| # | File | Covers |
|---|------|--------|
| 01 | `01-data-model.md` | Every entity/enum/type, and the **critical UI-name vs storage-name mapping** (read this first — "Task" in the UI is not what you think it is in storage) |
| 02 | `02-api-and-persistence.md` | REST contract, demo persistence, org-chart member integration boundary |
| 03 | `03-state-management.md` | Store shape, every action's exact business logic, cascading side effects |
| 04 | `04-domain-logic.md` | All pure functions: date math, Gantt coordinate math, tree/WBS building, color algorithm, progress rollups, permissions, filters, dependency-cycle detection, name-uniqueness rules, alerts |
| 05 | `05-gantt-board-ui.md` | The Gantt board component in full: layout, header, row rendering, drag/resize gestures, grouping capsules, dependency arrows, context menus |
| 06 | `06-list-and-baseline-views.md` | The List and Baseline views (both built on the shared `DataTable`) |
| 07 | `07-drawers-dialogs-menus.md` | The edit drawers, create dialogs, color picker, dependency editor, context menus, small glyph components |
| 08 | `08-toolbar-and-footer.md` | How the Gantt/List/Baseline switch, zoom, PDF button, fullscreen button and settings dialog are wired into the shared page Footer |
| 09 | `09-pdf-export.md` | The tiled-PDF export pipeline and print CSS; notes one piece of **dead code** |
| 10 | `10-design-tokens-and-shared-ui.md` | Every color/spacing/typography token in hex/px, and the shared UI primitives Timeline depends on |
| 11 | `11-flutter-porting-guide.md` | Synthesis: what ports 1:1 as pure Dart, what needs a different mechanism in Flutter, and a parity checklist |

## File map (source of truth this package was built from)

All paths are relative to the React repo root `qv_agent_hub/`.

```
src/modules/projects/boards/timeline/
├── ProjectTimelineTab.tsx          — tab shell: view switch, toolbar wiring, drawers/dialogs host
├── types.ts                        — all entity types, enums, VI labels, DEFAULT_FILTERS
├── api/timelineApi.ts              — REST contract + demo fallback, one function per mutation
├── store/timelineStore.ts          — the observable store: state + every business action
├── hooks/useTimelineStore.ts       — per-project store cache + React binding
├── domain/                         — pure, framework-free logic (see 04-domain-logic.md)
│   ├── dates.ts                    — ISO date parsing/formatting/validation, clamping
│   ├── ganttLayout.ts              — day↔pixel coordinate math, month/day tick building
│   ├── ganttRows.ts                — tree flattening, WBS numbers, chart grouping, status/priority meta
│   ├── ganttBarColors.ts           — the HSL-based bar color algorithm (source of truth for all bar colors)
│   ├── progress.ts                 — child→parent progress/status rollup formulas
│   ├── permissions.ts              — role → permission matrix
│   ├── filterTasks.ts              — task filter predicate (see note: currently has no UI trigger)
│   ├── dependencies.ts             — dependency cycle detection
│   ├── uniqueNames.ts              — sibling name-uniqueness validation
│   ├── workLevels.ts               — 3-level hierarchy helpers + level labels/colors
│   ├── alerts.ts                   — overdue/at-risk/behind-schedule alert detection (see note: not rendered anywhere currently)
│   └── statusStyles.ts             — DEAD CODE, not imported anywhere (see 04-domain-logic.md)
├── components/
│   ├── GanttBoard.tsx               — the Gantt chart (biggest file, ~2460 lines) — see 05
│   ├── TimelineListView.tsx         — List view — see 06
│   ├── BaselineCompareView.tsx      — Baseline view — see 06
│   ├── ListAndBaseline.tsx          — deprecated re-export shim, ignore
│   ├── TaskDrawer.tsx               — TimelineDrawer / TaskDrawer / MilestoneDrawer — see 07
│   ├── CreateDialogs.tsx            — 4 creation dialogs (Task/Subtask/Subitem/Milestone/Baseline) — see 07
│   ├── TaskDependenciesSection.tsx  — predecessor list editor inside TaskDrawer — see 07
│   ├── GanttColorPicker.tsx         — free-hex color picker — see 07
│   ├── GanttContextMenu.tsx         — generic right-click menu primitive — see 07
│   ├── PriorityGlyph.tsx / StatusGlyph.tsx / WorkLevelPlusBadge.tsx — small icon components — see 07
│   ├── TimelineFullscreenExitButton.tsx — fullscreen target ref + exit button — see 05/08
│   └── TimelinePrintShell.tsx       — A4 cover chrome wrapper used for PDF capture — see 09
├── export/
│   ├── exportTimelinePdf.ts         — the real, active PDF export pipeline — see 09
│   └── TimelinePrintSheet.tsx       — DEAD CODE, not imported anywhere — see 09
```

Direct dependencies outside the module that were also read in full and are documented here because
Timeline's on-screen behavior depends on them:

```
src/layout/ListviewPaginationContext.tsx   — Footer registration hooks (useTimelineFooterSettings, useListviewPagination, useListviewColumnSettings)
src/layout/Footer/index.tsx                — renders the bottom bar + the two settings dialogs
src/shared/config/devMode.ts               — GANTT_COLUMN_OPTIONS, column-visibility persistence, dev/testing mode gate
src/shared/config/useCompletedStrikethrough.ts / useGanttColumnVisibility.ts / dataSource.ts
src/shared/ui/{ConfirmDialog,AlertDialog,MemberAvatar,Button,PageCard,Pagination,FilterDropdown,DatePicker,DataTable}
src/shared/api/http.ts                     — apiFetch/ApiError
src/shared/lib/{listviewLayoutStore,springScroll}.ts
src/modules/projects/boards/types.ts       — ProjectRow (the parent Project entity)
src/modules/projects/boards/org/domain/{orgTimelineMembers,timelineMemberFilterOptions}.ts — org-chart → assignee-list mapping
src/modules/projects/boards/org/api/orgChartApi.ts — fetchProjectOrgChart / listEmployees (read-only from Timeline's POV)
src/styles/{tokens.css,design-system.css}  — every color/spacing/type token and control class Timeline uses
```

Not documented in depth (outside scope — Timeline only *reads* from these as a black box): the Org
Chart feature's own editing UI, Documents tab, Site Report tab, and the page chrome
(`ProjectDetailHeader`/`ProjectDetailFrame`) that hosts the tab bar seen in the screenshot.

## Architectural invariants to preserve

These are rules the original implementation enforces strictly. Breaking them silently changes
product behavior, so a Flutter port should keep them unless the user asks otherwise:

1. **Hierarchy is capped at exactly 3 levels**: Task (L0) → Subtask (L1) → Subitem (L2). A Subitem can
   never have children; the domain layer throws if you try (`assertCanNestUnder`).
2. **One persistence boundary.** All reads/writes go through `timelineApi.ts`. Nothing else touches
   the network or the demo store directly. The store applies API results; it never invents data.
3. **Domain validation always runs client-side before the network call** (dates, name uniqueness,
   nesting depth, dependency cycles, permissions) — the API is expected to re-validate, but the UI
   fails fast with a Vietnamese-language error message either way.
4. **Bar/wash colors always go through `ganttBarColors()`.** No component picks a hex directly; this
   is enforced by project convention (see `.cursor/rules/qv-gantt-bar-colors.mdc`) as well as by
   habit in the code.
5. **Two independent "today" values are used on purpose**: a frozen `state.demoToday` (hardcoded to
   `2026-03-15`) drives all *business* logic (overdue flags, alerts, milestone status), while the
   Gantt chart's visual "Today" marker/line uses the real calendar date (`todayIso()`). This exists so
   the demo seed always shows overdue/blocked items regardless of when you run the app. A production
   Flutter build talking to a real backend should most likely use real "now" everywhere — see
   `11-flutter-porting-guide.md`.
6. **Selection is single-focus**: selecting a Task, Subtask/Subitem, or Milestone clears the other two
   selection ids. Only one drawer can be open at a time.
7. **Rollups are one-directional except one explicit override**: children's status/progress normally
   roll *up* into the parent (Subitem→Subtask→Timeline). The one exception is manually marking a
   Subtask complete, which cascades *down* and force-completes all its Subitems — see
   `03-state-management.md` → `updateTask`.
