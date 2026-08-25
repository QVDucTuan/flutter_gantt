# Toolbar / Footer integration (the bottom bar in the screenshot)

The Gantt/List/Baseline switch, the zoom control, the PDF-export button, the fullscreen button, and
the settings gear are **not rendered by the Timeline module itself**. They live in a single shared
page-level `Footer` component (`src/layout/Footer/index.tsx`) that every "listview-shaped" tab in the
app (Boards list, Timeline, others) can push content into via a React context. This indirection matters
for the port: in Flutter there is no equivalent of "a distant shared shell widget reads state pushed
from whichever screen is currently active" unless you build one (a bottom-bar `ValueNotifier`/provider
that any screen can write into) — see `11-flutter-porting-guide.md` for the recommended shape.

## The registration hook: `useTimelineFooterSettings`

`ProjectTimelineTab.tsx` calls this **on every render** with a fresh config object:

```ts
useTimelineFooterSettings({
  columns: footerColumns,              // derived from GANTT_COLUMN_OPTIONS + current visibility/center prefs
  strikeCompleted,                       // current value of the strikethrough preference
  onToggleColumn: (id) => { /* flips visible for that column in localStorage */ },
  onToggleCenter: (id) => { /* flips center for that column in localStorage */ },
  onToggleStrike: (on) => setCompletedStrikethrough(on),
  chrome: {
    view: state.view, zoom: state.zoom,
    viewOptions: [{ value:'gantt', label:'Gantt' }, { value:'list', label:'List' }, { value:'baseline', label:'Baseline' }],
    zoomOptions:  [{ value:'day', label:'Day' }, { value:'week', label:'Week' }, { value:'month', label:'Month' }],
    onViewChange: (v) => actions.setView(v), onZoomChange: (z) => actions.setZoom(z),
  },
  exportPdf: { disabled: pdfExporting || pdfPreviewOpen || (view !== 'gantt' && view !== 'list'), busy: pdfExporting || pdfPreviewBusy, onExport: () => void exportPdf() },
  fullscreen: { active: boardFullscreen, onToggle: toggleBoardFullscreen },
})
```

The hook itself (in `ListviewPaginationContext.tsx`) doesn't just forward this into context state
naively — it keeps every callback in a `ref` (so re-registering doesn't matter for callback identity)
and only actually calls `setTimelineSettings(...)` inside a `useEffect` gated on a **stable signature
string** (`columns.map(c => `${id}:${visible}:${center}`).join('|')` plus the primitive scalar
values) — so the Footer doesn't re-render on every Timeline re-render, only when something that would
visibly change the Footer actually changed. **The registration is cleaned up
(`setTimelineSettings(null)`) on unmount** — leaving the Timeline tab makes all of these controls
disappear from the Footer.

Notice: **`view` is read from `state.view`, i.e. from the Zustand-less store**, not owned by the
Footer. The Footer is a pure display surface; every click it renders calls straight back into
`ProjectTimelineTab`'s own state/actions.

## What the Footer actually renders (`src/layout/Footer/index.tsx`)

Left side, always present (not Timeline-specific): a reload icon button, a live clock
(`HH:mm | dd/mm/yyyy`, re-rendered — note: **not on an interval**, it just reads `new Date()` at
render time, so it only updates when something else causes the Footer to re-render), and — only when
`VITE_DEV_MODE=testing` — a small orange "TEST" badge. **This "TEST" badge is exactly what's visible
in the reference screenshot's bottom-left corner**, confirming that screenshot was taken with the dev
testing flag on.

Right side, only while `timelineSettings` is registered (i.e. only while the Timeline tab is mounted):

1. **View switch** — a segmented control (`role="group"`), one button per `viewOptions` entry,
   active one highlighted (`--color-info-bg` background, `--color-info` text, bold).
2. *(Pagination would render here if registered — Timeline explicitly disables it in List/Baseline
   views via `useListviewPagination(null)`, so this slot is always empty for Timeline.)*
3. **Export-PDF icon button** — only if `exportPdf` was provided; disabled + tooltip "Chỉ xuất PDF ở
   chế độ Gantt hoặc List" when the current view is Baseline, or "Đang tạo file…" while busy.
4. **Fullscreen icon button** — only if `fullscreen` was provided; icon swaps between "expand" and
   "exit" glyphs based on `active`; the icon itself gets the accent color while active.
5. **Settings gear** — only if either `timelineSettings` or the generic `columnSettings` (registered
   independently by `DataTable`, used in List/Baseline views) is present. Clicking it opens a
   **centered modal dialog** (`role="dialog"`, `max-w` ~380–520px) — which dialog depends on which
   view is active:
   - **Gantt view** → the Timeline-specific settings dialog (see below).
   - **List/Baseline view** → the generic `DataTable` column-settings dialog (Show / Freeze / Center
     per column, plus a "Default" reset button) — this is the *same* dialog any other data table in
     the app uses, not Timeline-specific markup. See `10-design-tokens-and-shared-ui.md` for its
     exact layout, since it's a shared component.

   Only one of the two can show at once: the Gantt dialog condition is
   `open && showTimelineSettings && timelineSettings.chrome.view === 'gantt'`; the List dialog
   condition is `open && showListSettings && (!showTimelineSettings || timelineSettings.chrome.view === 'list')`.
   Switching views while the dialog is open does **not** auto-switch which dialog is shown — the
   `useEffect(() => { if (!showSettingsDialog) setOpen(false) }, ...)` only closes it if *neither*
   applies anymore.

### The Gantt settings dialog contents

Two sections:

1. **"Show/Hide cột"** — a 3-column table (Cột / Show / Center) listing exactly the 5
   `GANTT_COLUMN_OPTIONS` (Status, Priority, Start, End, Assignee — **never** Task Summary, which is
   always shown). Each row: a checkbox for `visible` and a checkbox for `center` (disabled + 40%
   opacity when the column isn't visible).
2. **"Hiệu ứng hiển thị"** → a single toggle row: "Gạch ngang khi hoàn thành" (strikethrough
   completed) with helper text "Tắt khi xuất bảng tiến độ / báo cáo."

Both sections write straight through to `localStorage` (see next section) — there is no separate
"Apply"/"Cancel"; every checkbox takes effect immediately, and the dialog's only button is "Đóng."

## Where the persisted prefs actually live (`src/shared/config/devMode.ts`)

```ts
type GanttOptionalCol = 'status' | 'priority' | 'startDate' | 'endDate' | 'assignee'
type GanttColumnPref = { visible: boolean; center: boolean }
type GanttColumnSettings = Record<GanttOptionalCol, GanttColumnPref>

DEFAULT_GANTT_COLS = {
  status:    { visible: true,  center: true  },
  priority:  { visible: true,  center: true  },
  startDate: { visible: false, center: true  },
  endDate:   { visible: false, center: true  },
  assignee:  { visible: true,  center: false },
}
```

Persisted as one JSON blob under `localStorage['qv.ui.ganttColumns']`; a legacy shape (`raw` boolean
per column, meaning visibility only) is still parsed for backward compatibility
(`parseColPref` treats a bare `true`/`false` as visibility-only, keeping the default's `center`).
`getGanttColumnSettings()` memoizes against the last-seen raw JSON string so repeated calls in the
same tick return the identical object reference (important for `useSyncExternalStore`'s reference-
equality check). A parallel single boolean, `localStorage['qv.ui.completedStrikethrough']` (default
**on** when absent), controls the strikethrough preference. Both use a simple `Set<() => void>`
listener registry + a `subscribe*()` export, consumed via `useSyncExternalStore` in
`useGanttColumnVisibility()`/`useCompletedStrikethrough()` — this is the same "observable module-level
value" pattern as the main store, just for two small UI prefs instead of the whole dataset. **These
two preferences are the only pieces of Timeline UI state that persist across a reload independent of
the demo/API data itself** — a fresh Flutter port should decide its own equivalent (e.g.
`SharedPreferences` keys `gantt_columns` / `strikethrough_completed`).

`resolveDevStartPath()` / `getDevStartPage()` in the same file are dev-only routing conveniences (a
`.env`-driven "which page does the app open on" setting) — not part of the Timeline feature itself,
skip porting.
