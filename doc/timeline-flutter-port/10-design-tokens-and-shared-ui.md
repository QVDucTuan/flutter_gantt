# Design tokens and shared UI primitives

Timeline doesn't define its own visual language — it consumes the app-wide design tokens
(`src/styles/tokens.css`) and a handful of shared components (`src/shared/ui/*`). Reproducing these
faithfully is what will make a Flutter port actually *look* like the same product rather than just
behave the same.

## Color tokens (real hex values — `tokens.css`)

```css
/* Brand / actions */
--color-primary: #0d90d9;            --color-primary-hover: #0b7fbf;
--color-accent: #0d90d9;             /* = primary */
--color-button-primary: #008ecb;     --color-button-primary-hover: #007eb5;
--color-tab-active: #0f6abd;

/* Status */
--color-success: #00812d;   --color-success-bg: #deefe2;   --color-success-dot: #599d69;
--color-badge-success: #55a76a;
--color-info: #5392f9;      --color-info-bg: #e9f2ff;
--color-orange: #e8903d;    --color-orange-bg: #fff1e4;
--color-danger: #d64545;    --color-danger-bg: #fdecec;

/* Text roles */
--color-text-primary: #324f6a;   --color-text-secondary: #495569;   --color-text-muted: #96a3b8;
--color-text-subtle: #94a3ba;    --color-text-filter: #344153;       --color-text-table: #153b62;
--color-text-on-accent: #ffffff; --color-text-footer: #7a859c;

/* Surfaces */
--color-bg-app: #ffffff;   --color-bg-main: #fcfcfc;   --color-bg-toolbar: #fafafa;
--color-bg-elevated: #ffffff;  --color-bg-muted: #f3f3f3;  --color-bg-input: #ffffff;

/* Borders / icons */
--color-border: #ccd0de;   --color-border-card: #e6e7eb;   --color-control-border: #d0d5dd;
--color-icon: #6c707e;      --color-icon-muted: #5f6a8a;

/* Table */
--color-table-header-bg: #e9e9e9;   --color-row-alt: #f9f9f9;   --color-row-hover: #f5f5f5;
```

Note the **overdue mark used on Gantt bars** (`GANTT_OVERDUE_MARK`, `04-domain-logic.md`) is
`var(--color-primary)` = `#0d90d9` — a **blue** stripe, deliberately *not* orange/red, so it doesn't
read as an error state on an otherwise calm pastel bar.

## Layout / radius / spacing

```css
--border-width: 0.5px;    /* every hairline border in the app uses this, never a plain 1px Tailwind `border` */
--radius-sm: 4px;  --radius-md: 6px;  --radius-lg: 8px;  --radius-xl: 12px;
--header-height: 45px;  --footer-height: 32px;
--table-header-height: 55px;  --table-row-height: 45px;   /* generic DataTable defaults — Gantt's own ROW_H is a different constant, 40px, see 05 */
```

## Typography

```css
--font-sans: 'Montserrat', system-ui, sans-serif;
--fs-page-title: 17px;  --fs-title: 14px;  --fs-body: 12px;  --fs-body-lg: 13px;
--fs-caption: 10px;  --fs-overline: 10px;  --fs-micro: 8px;
--fw-regular: 400; --fw-medium: 500; --fw-semibold: 600; --fw-bold: 700; --fw-extrabold: 800;
--lh-tight: 1.2; --lh-snug: 1.25; --lh-normal: 1.35; --lh-relaxed: 1.45;
```

Almost everything inside Timeline renders at `12px` (`--fs-body`) with `font-weight: 400–600`
depending on hierarchy depth — there is no large-type moment anywhere in this feature except the
16-ish px drawer/dialog titles.

## Control classes (`design-system.css`) — exact specs for every input-like element

```css
.qv-control {              /* every FilterDropdown trigger, ControlInput, DateInput trigger, Button-adjacent field */
  height: 36px; padding: 0 10px;
  border: 0.5px solid #d0d5dd; border-radius: 8px;
  background: #ffffff; color: #344153;
  font: 500 12px/1.25 Montserrat, sans-serif;
}
.qv-control:hover  { background: rgba(0,0,0,0.02); }
.qv-control:disabled { opacity: 0.6; cursor: not-allowed; }

.qv-control-textarea { min-height: 72px; padding: 8px 10px; line-height: 1.4; resize: vertical; }

.qv-range {   /* the progress sliders in TimelineDrawer/TaskDrawer/MilestoneDrawer */
  height: 16px; --qv-range-fill: var(--color-success);   /* green fill by default */
  track: 3px tall, rounded-full, thumb 12px circle, white with a tinted ring border
}
```

## Shared components Timeline depends on

All were read in full; behavior notes below are the parts that matter for parity (visual chrome is
straightforward to redo natively in Flutter and isn't worth transcribing pixel-by-pixel here).

- **`Button`** (`variant: 'primary'|'secondary'|'ghost'`) — primary = solid `--color-button-primary`
  fill, white text, 36px tall, 8px radius; ghost = transparent, muted text; `leftIcon="plus"` is a
  magic string that renders a bundled plus-icon SVG.
- **`ConfirmDialog`** / **`AlertDialog`** — centered modal, portaled to `document.body`, scrim
  `rgba(15,23,42,0.2)`, Escape-to-cancel (only `ConfirmDialog`, and only while not `busy`), body-scroll
  lock while open. `ConfirmDialog`'s `danger` prop swaps the confirm button to red
  (`--color-danger`). **These are the app's replacement for `window.confirm`/`window.alert` — never
  use a native browser dialog anywhere in this feature**, and the Flutter port should likewise use its
  own dialog widgets rather than a platform alert, for the same reason (styling consistency + testability).
- **`MemberAvatar`** — circular photo, falls back to a 2-letter initials chip
  (`firstWord[0]+lastWord[0]`, or first 2 chars of a single-word name) on a colored background
  (defaults to `--color-primary`, overridable) if the image URL is empty *or* fails to load
  (`onError` flips a `broken` flag permanently for that instance — it doesn't retry).
- **`FilterDropdown`** — a custom combobox (not a native `<select>`): button trigger + a
  `document.body`-portaled floating listbox positioned via `getBoundingClientRect` math that flips
  above the trigger if there isn't enough room below. Supports a leading icon/glyph per option
  (used everywhere Timeline shows a priority/status glyph inline in a dropdown), an optional subtitle
  line per option (used for member job titles), and an `embedLabel` flag that switches the trigger
  text between `"Label: value"` and just `"value"` (Timeline almost always sets `embedLabel={false}`
  and puts the label in a separate `<Field>` above it instead).
- **`DatePicker`** — a custom calendar popover (not the native date input in most places — though
  `.qv-control-date` CSS exists for a native fallback pattern elsewhere in the app, Timeline's
  `DateInput` wrapper always uses this custom one). Monday-first week grid, "Hôm nay" (jump-to-today)
  and optional "Xóa" (clear) footer actions. Value/`onChange` are always plain `'YYYY-MM-DD'` strings.
- **`PageCard`** — the plain white rounded-card (`--radius-xl`, `--color-border-card` border) wrapper
  used around the List/Baseline `DataTable`s and various empty states; supports an optional toolbar
  slot (unused by Timeline) and footer slot.
- **`Pagination`** — has a `compact` mode meant for the Footer, but Timeline never actually surfaces
  it (`useListviewPagination(null)` in both List and Baseline views) — documented for completeness
  only, not otherwise relevant.
- **`DataTable`** (`src/shared/ui/DataTable/index.tsx`, 893 lines) — the table engine behind both
  `TimelineListView` and `BaselineCompareView`. Relevant behavior:
  - Column resize (drag a 6px hit-zone at each header's right edge), row-height resize (drag a
    1.5px-tall hit-zone at the bottom of each row's first cell), both persisted per-`storageKey`
    to `localStorage` (`qv.listview.layout.v1:{storageKey}` — Timeline uses keys
    `'timeline.list.v6'` and `'timeline.baseline.v5'`).
  - "Freeze panes" semantics: freezing column N sticks it *and every visible column to its left*
    (Excel-style), implemented via `position: sticky` with computed `left` offsets — not just the one
    column.
  - Optional client-side sort (`sortValue` per column) — **every Timeline column sets
    `sortable: false`**, so this path is present in the shared component but unused by Timeline
    specifically; rows are always shown in tree order.
  - Registers its own column-visibility/freeze/center settings into the same Footer settings-gear
    slot via `useListviewColumnSettings` — this is the dialog described in `08-toolbar-and-footer.md`
    for List/Baseline view.
  - Supports an infinite-scroll append mode with a spring-scroll-to-page helper
    (`springScrollTo`, ease-out-cubic, 520ms) — **not used by Timeline** (both call sites render the
    full row set at once; the tree is rarely more than a few hundred rows).
  - Dashed-divider mode (`getRowDivider`) reuses the exact same dotted-line visual as the Gantt
    chart's day-grid hairlines — **not used by Timeline's own tables today**, but worth knowing the
    visual vocabulary is shared if a future List-view tweak wants tree-style dashed separators.
