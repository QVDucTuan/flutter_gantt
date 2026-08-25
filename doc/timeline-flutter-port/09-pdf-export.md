# PDF export

Source: `src/modules/projects/boards/timeline/export/exportTimelinePdf.ts` (554 lines) +
`components/TimelinePrintShell.tsx` (the A4 cover chrome) + print-mode CSS in
`src/styles/globals.css`. This whole mechanism is inherently web/DOM-specific (it rasterizes live
HTML), so treat this file as "what behavior to reproduce," not "what code to port line-for-line" — a
Flutter implementation will use something like the `pdf`/`printing` packages and its own widget tree
instead of screenshotting a rendered page.

## ⚠️ Correction to an existing internal doc

`docs/timeline/USAGE.md` (already in this repo, not written by this pass) currently says PDF export
produces *"a 1-page A4 landscape PDF"* via a single `html-to-image` JPEG capture. **That is stale.**
The actual current code (verified by reading `exportTimelinePdf.ts` directly) does something more
capable: it **tiles the board into as many A4 pages as needed**, capturing each tile as a separate PNG
at 2× pixel density, so nothing is ever shrunk to illegibility and long timelines correctly span
multiple pages. Trust this document and the source over that older note.

## What triggers it

The Footer's export-PDF button (see `08-toolbar-and-footer.md`) is enabled only in **Gantt** or
**List** view (not Baseline — there's no print layout for the comparison table). Clicking it calls
`ProjectTimelineTab.exportPdf()`:

```
openTimelinePrintPreview({ rootEl: printRootRef.current, projectName: project.project })
  → returns { confirmPrint(): Promise<void>; cancel(): Promise<void> }
  → shows a full-screen preview overlay (ProjectTimelineTab's own JSX, not part of the export module)
  → "Tải PDF" button → confirmPrint() → downloads the file and closes the overlay
  → "Hủy" / Escape → cancel() → restores the live page without downloading anything
```

`printRootRef` points at a `TimelinePrintShell`-wrapped copy of the **exact same live DOM** currently
on screen (the real `GanttBoard` or the real `TimelineListView`, not a separate lightweight render) —
see the next section.

## `TimelinePrintShell` — the A4 cover sheet wrapped around the live board

A fixed cover layout (hidden on screen via CSS, shown only while a `qv-printing-timeline` class is on
`<html>`) containing:

- **Header**: company logo, a title (`"TIMELINE DỰ ÁN"` for Gantt, `"TIMELINE LIST"` for the List
  export — passed in as the `title` prop), the project name, an export-date block, and two info cards
  side by side — "Thông tin dự án" (Dự án / Phạm vi / Địa điểm / Thời gian, from the 4
  `printProjectRows` built in `ProjectTimelineTab`) and "Thông tin khách hàng" (end-user logo-or-
  initials + name + address).
- **Canvas slot** (`children`): this is where the live `GanttBoard`/`TimelineListView` gets rendered,
  marked with `data-qv-tl-print-board` on its root so the export pipeline can find and measure it.
- **Footer**: a fixed 3-column contact block (address / email / phone — these are the company's own
  hardcoded contact details, not project data: `52 Đường số 2, P. Bình An, TP. Thủ Đức, TP.HCM` /
  `info@quocviet.com.vn` / `(+84) 28 7300 6680`).

This exact header/footer content is duplicated inline inside `ProjectTimelineTab.tsx` itself for the
Gantt case (rather than reusing `TimelinePrintShell`) — a pre-existing minor duplication in the source,
not something to intentionally replicate as "two components doing the same thing" in a clean port;
one shared print-chrome widget is the right shape.

## The tiling algorithm (`exportTimelinePdf.ts`)

```ts
ORG_PRINT_SHEET = {
  widthPx:  round(297 / 25.4 * 96),   // A4 landscape width at 96 DPI  ≈ 1122px
  heightPx: round(210 / 25.4 * 96),   // A4 landscape height at 96 DPI ≈ 794px
}
TILE_PIXEL_RATIO = 2          // each captured tile is rasterized at 2× for crisp text
MAX_PDF_PAGES = 60             // hard cap; throws a Vietnamese error asking the user to narrow the range instead
```

1. **Preview** (`mode: 'fit'`): the whole board is measured, then CSS-scaled down (never up) to fit
   entirely inside one on-screen A4 frame — purely so the user can see an overview before committing;
   this scaled version is *not* what gets downloaded.
2. **Download** (`confirmPrint` → `downloadTiledTimelinePdf`, `mode: 'tile'`): the board is expanded
   back to its **full natural size** (every scroll container's `overflow` forced to `visible`, widths/
   heights measured from `scrollWidth`/`scrollHeight` rather than clipped `clientWidth`/`Height`) —
   i.e. it prints "everything," not just what was scrolled into view. Then:
   - `cols = ceil(boardWidth / oneA4BodyWidth)`, `rows = ceil(boardHeight / oneA4BodyHeight)`,
     `pages = cols * rows` (throws if `pages > 60`).
   - For each `(row, col)` tile: translate the board by `(-col*bodyWidth, -row*bodyHeight)` (panning
     a fixed-size A4 "window" over the oversized board, rather than re-laying-out anything per tile),
     wait a frame + 20ms for the browser to settle, capture a PNG at `TILE_PIXEL_RATIO`, and
     `pdf.addImage(...)` it onto its own `297mm × 210mm` landscape page.
   - Filename: `timeline-{slugified-project-name}.pdf` (accents stripped, lowercased, non-alnum →
     hyphens).
3. Before every capture: wait for every `<img>` in the tree to finish loading (or error) and for
   `document.fonts.ready`, so logos/avatars/custom fonts are never captured half-rendered.
4. A `filterCaptureChrome` predicate excludes a handful of interactive-only elements from the capture
   (the preview overlay itself, and any element carrying `data-qv-tl-fs-chrome` — i.e. the in-canvas
   fullscreen-exit button never appears in the exported PDF).
5. List-view export additionally "unlocks" every DataTable scroll wrapper (`expandListPrintBoard`) so
   every row contributes to the measured height, not just the ones currently scrolled into the
   viewport's clipped area.
6. On cancel or after a successful download, every inline style mutation made to the live DOM is
   explicitly reverted (`restoreSheet`) — the export never leaves the real on-screen board in a
   different state than before export was triggered.

## Print CSS gate

All of this is gated behind two classes toggled on `<html>`: `qv-printing-org` (shared with the Org
Chart feature's own print/export flow — the two features reuse the same A4-sheet CSS scaffolding) and
`qv-printing-timeline` (Timeline-specific overrides: forces `-webkit-print-color-adjust: exact` so
background tints/bar colors aren't dropped, un-clips `.truncate`/`.overflow-hidden` text so glyphs
don't get bottom-clipped under CSS `zoom`, hides the "+ Thêm Task" button, and unlocks the two DataTable
scroll wrappers for List export). None of this CSS needs to be ported — it exists purely to work
around browser rasterization quirks that don't apply to a native Flutter renderer.

## ⚠️ Dead code: `export/TimelinePrintSheet.tsx`

This file (`TimelinePrintSheet` component, ~530 lines, plus its own from-scratch lightweight
re-implementation of the Gantt chart specifically for print — smaller `ROW_H=26`, sparse day labels,
weekend bands, its own bar rendering) is **never imported by anything else in the codebase** (verified
by a whole-repo search for `TimelinePrintSheet`). It appears to be an earlier, alternate approach to
PDF export (build a separate, print-optimized DOM tree and print *that*) that was superseded by the
"capture the real live board" approach in `exportTimelinePdf.ts` + `TimelinePrintShell.tsx` described
above, but was never deleted. **Do not port this file's approach as if it were the active one** — the
tiled live-DOM-capture pipeline is what the running app actually does today. It's mentioned here only
so nobody re-reads that file later and assumes it's load-bearing.
