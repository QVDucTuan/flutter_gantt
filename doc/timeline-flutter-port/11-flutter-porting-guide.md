# Flutter porting guide

This is a synthesis, not new information — everything here follows from files 01–10. Use it as a
starting checklist when scaffolding the Dart side; refer back to the numbered files for the exact
formula/rule whenever a "port as-is" item needs its actual algorithm.

## Ports almost verbatim into pure Dart (no framework decisions needed)

Everything in `04-domain-logic.md` is framework-free TypeScript already — the natural move is one
Dart file per source file, same function names, same signatures, same constants:

- `dates.dart` ← `dates.ts` (use `DateTime` internally if convenient, but keep the public API
  string-in/string-out `'YYYY-MM-DD'` like the original — a lot of other logic assumes that).
- `gantt_layout.dart` ← `ganttLayout.ts` (pure arithmetic; `ROW_H`, `AXIS_H`, `COL`, `DAY_WIDTH` are
  the pixel constants a `CustomPainter`/`Positioned` layout will need directly).
- `gantt_rows.dart` ← `ganttRows.ts` (tree-flattening + WBS + grouping — this is what feeds both the
  Gantt canvas and the List/Baseline tables, keep it as one shared function like the original).
- `gantt_bar_colors.dart` ← `ganttBarColors.ts` (the HSL math is standard; Dart's `HSLColor` class
  can replace the hand-rolled `hslToHex`, but keep the exact same tone table and hue band so colors
  match pixel-for-pixel against the existing product).
- `progress.dart` ← `progress.ts`, `permissions.dart` ← `permissions.ts`, `filter_tasks.dart` ←
  `filterTasks.ts`, `dependencies.dart` ← `dependencies.ts`, `unique_names.dart` ← `uniqueNames.ts`
  (Vietnamese `toLowerCase` — Dart's `toLowerCase()` handles Vietnamese diacritics fine, no special
  locale call needed, unlike the JS `toLocaleLowerCase('vi')`), `work_levels.dart` ← `workLevels.ts`.
- `alerts.dart` ← `alerts.ts` and `status_styles.dart` — **only port these if the Flutter app is also
  building an alerts/inbox surface**; per `04-domain-logic.md` neither has a consumer in the current
  product, and `statusStyles.ts` is dead code outright.

Unit tests in `domain/domain.test.ts` translate directly into `flutter_test` cases with the same
inputs/expected outputs — reuse them as the first tests for the Dart port so behavior parity is
checked mechanically instead of by eye.

## Needs a different mechanism, same observable behavior

| React concept | What it does | Flutter equivalent |
|---|---|---|
| Hand-rolled store (`subscribe`/`getSnapshot`) per `projectId`, cached in a `Map` | One observable "document" per project, created lazily on first access, surviving navigation away and back | A `ChangeNotifier`/`Cubit`/`Bloc` per project id, held in a keyed provider (Riverpod `family`, or a simple `Map<String, TimelineController>` in a service locator). Keep the same "create on first read, `hydrate()` immediately" pattern. |
| `useSyncExternalStore` for two tiny localStorage-backed prefs (column visibility, strikethrough) | Any widget can read/write a persisted preference and rebuild live when it changes, even from elsewhere | `SharedPreferences` + a small `ValueNotifier`/`ChangeNotifier` wrapper, or a Riverpod `StateProvider` backed by a persistence layer |
| Two independent "today" clocks (`state.demoToday` fixed, `todayIso()` real) | Demo data always shows overdue/at-risk items regardless of when you run the app, while the visual today-marker is always actually today | Decide up front: a **production** Flutter build talking to a real backend almost certainly wants `DateTime.now()` everywhere and should drop the frozen-clock concept entirely, unless a demo/offline mode is also being built, in which case reproduce the same split explicitly (name it something like `businessClock` vs `wallClock` so the intent is obvious in Dart, unlike the original's slightly confusing dual meaning of "today") |
| Context-registered Footer chrome (`useTimelineFooterSettings`) | A distant shared shell renders controls whose state/handlers are owned by whichever screen is currently active | A `ValueNotifier<TimelineFooterConfig?>` exposed by the app shell, written by the Timeline screen's `initState`/`build` and cleared in `dispose` — mirror the original's "only push a new value when a signature actually changed" guard to avoid needless shell rebuilds |
| `data-*` attributes + `document.querySelector` scroll-container surgery for PDF export | Rasterize the live DOM, tile it across N pages | Not applicable 1:1 — see the dedicated section below |
| React portals (`createPortal`) for dialogs/menus/tooltips to `document.body` | Escape a clipping/overflow ancestor, control stacking order | Flutter's `Overlay`/`showDialog`/`showMenu` already solve this natively — simpler here than the original, not harder |
| CSS `position: sticky` for frozen table columns/headers | Column(s) stay pinned while the rest scrolls horizontally | A `Stack` with the frozen columns as a fixed-width leading `Column` outside the horizontally-scrolling `ListView`/`Table`, or a package like `two_dimensional_scrollables`/`syncfusion` if a fully general frozen-pane table is wanted |

## The Gantt canvas itself: the one place to design fresh, not transcribe

`GanttBoard.tsx` is ~2500 lines of absolutely-positioned `<div>`s over a scrollable canvas, because
that's how you build this in the DOM. In Flutter, the equivalent is naturally a `CustomPainter` (for
the static grid/weekend-tint/dependency-arrows/group-capsule layers — items 1–5 in
`05-gantt-board-ui.md`'s z-order list) plus a `Stack` of positioned interactive widgets on top for the
bars themselves (so `GestureDetector`/`Draggable` can be used per-bar instead of hand-rolled pointer
math). Concretely:

- **Layer 1–3 (grid, today-line, dependency arrows)**: one `CustomPainter` drawing directly from
  `ganttLayout.dart`'s coordinate functions — this is the most direct translation in the whole UI
  layer, since it's already pure math in the source.
- **Layer 4–5 (group capsules)**: either painted in the same `CustomPainter` (simplest, since their
  geometry is also pure math from `buildTaskChartGroups`/`buildSubtaskChartGroups`) or as
  positioned `DecoratedBox`es in the `Stack` if you want them to participate in hit-testing/hover
  later.
- **Bars**: a `Positioned` widget per row inside a `Stack`, using a `GestureDetector`
  (`onPanStart`/`onPanUpdate`/`onPanEnd`) to reproduce `useChartBarGesture`'s three modes (move,
  resize-start, resize-end) — the exact delta math in `applyBarDragDelta` (`04`… actually `05`) ports
  directly: same three branches, same `dx`-in-pixels → `xToDate` conversion on release, same
  "only commit if the resulting date actually changed" guard.
- **The floating date tooltip while dragging**: an `Overlay` entry positioned from the pointer's
  global position, same offset convention (+14px x / −10px y) is fine to keep or restyle.
- **Left grid + right chart kept in vertical scroll sync**: two `ScrollController`s with a listener on
  each calling `.jumpTo()` on the other (guard against feedback loops with a re-entrancy flag) is the
  direct equivalent of the original's manual `sync('l'|'r')`.

## PDF export: redesign the mechanism, keep the specification

Don't try to "screenshot the widget tree" in Flutter the way the web version rasterizes the DOM —
Flutter has first-class tools for this that produce better output:

- Build the report as its own **widget tree** (using the `pdf` package's `pw.Widget`s, or render an
  actual Flutter `Widget` subtree to canvas via `RepaintBoundary.toImage` per page if reusing the
  on-screen Gantt painter directly is preferred) rather than trying to reuse the exact interactive
  Gantt widget.
- Keep the **specification** from `09-pdf-export.md`: A4 **landscape**, tile a long Gantt board across
  multiple pages rather than shrinking everything onto one, cap the page count with a clear user-facing
  error past some sane maximum (60 was the original's cap — tune to taste), and preserve the same
  cover-sheet content (project info card, end-user card, company contact footer) since that's product
  content, not implementation detail.
- Do **not** resurrect the abandoned `TimelinePrintSheet.tsx` approach (a separate lightweight
  from-scratch chart just for print) as if it were the "real" spec — the multi-page tiling behavior
  described in `09-pdf-export.md` is what the shipped product actually does.

## Behavior parity checklist

Use this as a literal checklist while implementing, since these are the rules most likely to get
silently dropped or subtly changed during a rewrite:

- [ ] 3-level cap enforced (`assertCanNestUnder`) — a Subitem can never gain children.
- [ ] Name uniqueness scoped correctly: Task names unique project-wide; Subtask names unique among
      siblings under the same Task **and** distinct from the Task's own name; Subitem names unique
      among siblings under the same Subtask **and** distinct from that Subtask's own name.
- [ ] Editing a Task's dates **clamps** (never shifts) out-of-bounds Subtasks/Subitems into the new
      window; dragging a Subtask's bar **shifts** its Subitems by the same delta, then clamps.
- [ ] Manually completing a Subtask force-completes all its Subitems; the reverse (un-completing) does
      not cascade.
- [ ] A Subitem's progress is always exactly 0 or 100, driven solely by its status — never a free
      slider.
- [ ] A Subtask's progress slider only appears in the edit UI when it has zero Subitems; otherwise
      progress is fully rollup-driven and read-only there.
- [ ] Rollups exclude `cancelled` children entirely (they neither drag the average down nor count
      toward "any activity").
- [ ] `member` role can only edit tasks assigned to them; every other write permission is role-only.
- [ ] Selecting a Task/Subtask/Subitem/Milestone is mutually exclusive — only one drawer open at a
      time.
- [ ] Bar colors always derive from `ganttBarColors(colorIndex, depth, colorHex)` — never a second,
      independently-invented color mapping.
- [ ] Overdue is shown as a small accent stripe/marker, never a full bar recolor.
- [ ] Dependency creation rejects self-loops and anything that would create a cycle, checked
      client-side before any write.
- [ ] "One project baseline" = one snapshot row per active Task sharing a batch date+name; the compare
      view groups them back by that pair.
