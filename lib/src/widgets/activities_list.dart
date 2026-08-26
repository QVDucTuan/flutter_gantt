import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../flutter_gantt.dart';
import '../utils/row_geometry.dart';
import 'tree_guides_overlay.dart';

/// Displays the list of activity names on the left side of the Gantt chart.
///
/// This widget shows activity titles, optional icons, and action buttons in a
/// scrollable list that synchronizes with the [ActivitiesGrid].
class ActivitiesList extends StatefulWidget {
  /// The list of [GanttActivity] items to display.
  ///
  /// Can contain hierarchical activities with parent-child relationships.
  final List<GanttActivity> activities;

  /// Optional [ScrollController] to synchronize scrolling with the grid view.
  final ScrollController? controller;

  /// Creates an [ActivitiesList] widget.
  ///
  /// [activities] must not be null and should contain at least one activity.
  /// [showIsoWeek] enables the ISO week-number row (default: `false`).
  const ActivitiesList({
    super.key,
    required this.activities,
    this.controller,
    this.showIsoWeek = false,
    this.showTreeGuides = false,
    this.columns,
    this.onActivitySecondaryTap,
    this.initialColumnWidths,
    this.onColumnWidthsChanged,
  });

  /// Whether to show the ISO week number row.
  ///
  /// If `true`, a row displaying ISO-8601 week numbers is shown
  /// between the month headers and the day cells.
  final bool showIsoWeek;

  /// Whether to draw tree connector guide lines (elbow/tee) alongside the
  /// indentation. See [GanttTreeIndent].
  final bool showTreeGuides;

  /// When set, replaces the default single name column with these columns
  /// (each rendered via its own `cellBuilder`) — e.g. to also show start/end
  /// dates or duration alongside the name. `null` (the default) keeps the
  /// original name-only layout unchanged.
  ///
  /// Unlike `GanttActivitiesTable`, rows here are never resortable — this
  /// list's row order must stay in lockstep with the chart rows beside it,
  /// so [GanttListColumn.sortValue] is ignored if set. Each column's
  /// resolved width starts from its [GanttListColumn.width]/[GanttListColumn.flex]
  /// but can be dragged wider/narrower from the header (see
  /// `_ColumnResizeHandle`) — dragging a boundary always moves width between
  /// the two columns it sits between, so the total stays put and the header
  /// and every row resize together.
  final List<GanttListColumn>? columns;

  /// Called when a row is right-clicked (or, on a trackpad, secondary-
  /// tapped) — with the activity under the pointer and the pointer's
  /// global position. The package has no concept of a context menu itself;
  /// this just reports "here's the activity, here's where to anchor
  /// whatever menu you build" (e.g. via `showMenu`), since what the menu
  /// contains is entirely business logic (different items depending on
  /// whether the activity is a top-level Task, a Subtask, or a leaf — that
  /// classification is left/right, not the package's).
  final void Function(GanttActivity activity, Offset globalPosition)?
  onActivitySecondaryTap;

  /// Restores column widths from a previous session — one ratio per
  /// [columns] entry (each `0.0`–`1.0`, only meaningful summed across the
  /// flex-based columns; an entry for a fixed-`width` column is ignored).
  /// Must match [columns] in length to take effect; a length mismatch (e.g.
  /// a column was added/removed since these were saved) falls back to
  /// resolving widths from [GanttListColumn.flex]/[GanttListColumn.width]
  /// as usual. The package doesn't persist this itself — pair with
  /// [onColumnWidthsChanged] and your own storage (`SharedPreferences`, a
  /// user-settings API, ...).
  final List<double>? initialColumnWidths;

  /// Called once a column-boundary drag finishes (on release, not on every
  /// pointer move mid-drag) with every column's current width ratio, in
  /// [columns] order — suitable for handing straight to your own storage
  /// and feeding back in as [initialColumnWidths] next time. `null` (the
  /// default) does nothing; the package itself never persists this.
  final void Function(List<double> ratios)? onColumnWidthsChanged;

  @override
  State<ActivitiesList> createState() => _ActivitiesListState();
}

class _ActivitiesListState extends State<ActivitiesList> {
  static const double _dividerWidth = 1.0;
  // Short centered tick, not a wall-to-wall divider — each data row draws
  // its own, matching QV's per-row style instead of one continuous line.
  static const double _columnDividerTickHeight = 20.0;

  // Column 0 (the tree/name column) always renders this chrome ahead of its
  // own cellBuilder content — see [_columnContent] and [_buildExpandToggle]
  // — none of it can shrink below these sizes, so they're the same literal
  // numbers used there, duplicated here only for computing a minimum.
  static const double _expandToggleWidth = 20.0;
  static const double _depthIconWidth = 16.0; // 12px icon + 4px trailing gap
  static const double _column0HorizontalPadding = 8.0; // horizontal: 4 * 2

  /// The deepest nesting level anywhere in [activities] (0 for a flat
  /// list), including collapsed subtrees — a row hidden today by a collapsed
  /// ancestor can still be revealed later without the column suddenly being
  /// too narrow for it.
  int _maxDepth(List<GanttActivity> activities) {
    var deepest = 0;
    for (final activity in activities) {
      if (activity.depth > deepest) deepest = activity.depth;
      final children = activity.children;
      if (children != null && children.isNotEmpty) {
        final childDeepest = _maxDepth(children);
        if (childDeepest > deepest) deepest = childDeepest;
      }
    }
    return deepest;
  }

  /// The narrowest column [index] can be resized to. For every column but
  /// the first this is just [GanttListColumn.minWidth]. Column 0 also has
  /// to fit [GanttTreeIndent] at the tree's own deepest level plus the
  /// fixed-size expand toggle and depth icon (see [_columnContent]) ahead
  /// of its content — none of that can shrink, so a flat [minWidth] alone
  /// (its default, 40.0, comfortably covers every *other* column) isn't
  /// enough once nesting goes any deeper than trivial: at depth 0 the
  /// chrome alone is already ~58px, more before any of the row's own text.
  /// Ignoring this is exactly what let column 0 get dragged narrower than
  /// its own content, overflowing every row's [Row] by however many pixels
  /// its indent exceeded the available space.
  double _effectiveMinWidth(int index, GanttTheme theme) {
    final column = widget.columns![index];
    if (index != 0) return column.minWidth;
    final deepestIndent =
        theme.treeIndentWidth * (_maxDepth(widget.activities) + 1);
    final chrome =
        deepestIndent +
        _expandToggleWidth +
        (theme.depthIconBuilder != null ? _depthIconWidth : 0) +
        _column0HorizontalPadding;
    return chrome > column.minWidth ? chrome : column.minWidth;
  }

  /// Each flex-based column's share of the *flexible* space (total width
  /// minus any fixed-`width` columns and the dividers between them) — always
  /// sums to 1.0 across the flex columns. Re-resolved into actual pixels on
  /// every build from whatever the current available width is (see
  /// [_resolveWidths]), so the ratio — not a stale pixel count — is what's
  /// preserved across window resizes or a column being added/removed. A
  /// fixed-`width` column has no entry here; it always renders at its own
  /// literal width regardless of available space.
  List<double>? _columnRatios;

  void _ensureColumnRatios(List<GanttListColumn> columns) {
    if (_columnRatios != null && _columnRatios!.length == columns.length) {
      return;
    }
    final restored = widget.initialColumnWidths;
    if (restored != null && restored.length == columns.length) {
      _columnRatios = List.of(restored);
      return;
    }
    final flexTotal = columns.fold<double>(
      0,
      (sum, c) => sum + (c.width == null ? (c.flex ?? 1) : 0),
    );
    _columnRatios = [
      for (final c in columns)
        c.width != null
            ? 0.0
            : (flexTotal > 0 ? (c.flex ?? 1) / flexTotal : 1 / columns.length),
    ];
  }

  /// The flexible space actual columns compete over: [totalWidth] minus
  /// every fixed-`width` column and every divider between columns.
  double _flexSpace(List<GanttListColumn> columns, double totalWidth) {
    final fixedTotal = columns.fold<double>(
      0,
      (sum, c) => sum + (c.width ?? 0),
    );
    final dividersWidth = (columns.length - 1) * _dividerWidth;
    return (totalWidth - fixedTotal - dividersWidth).clamp(
      0.0,
      double.infinity,
    );
  }

  /// Resolves each column's actual pixel width for the current build, from
  /// its stored ratio (or its own fixed `width`) and [totalWidth].
  List<double> _resolveWidths(List<GanttListColumn> columns, double totalWidth) {
    final flexSpace = _flexSpace(columns, totalWidth);
    final ratios = _columnRatios!;
    return [
      for (var i = 0; i < columns.length; i++)
        columns[i].width ?? (flexSpace * ratios[i]),
    ];
  }

  /// Drags width between column [index] and the column right after it, so
  /// resizing one column always borrows/gives space to its neighbor instead
  /// of changing the row's total width. [flexSpace] is this build's current
  /// flexible space (see [_flexSpace]) — needed to convert the drag's pixel
  /// delta into a ratio delta, and to convert each column's own effective
  /// minimum (see [_effectiveMinWidth] — column 0's accounts for the tree's
  /// own deepest indent, not just its configured [GanttListColumn.minWidth])
  /// into an equivalent minimum ratio.
  ///
  /// The pair's combined ratio (`ratios[index] + ratios[next]`) never
  /// changes — only how it's split between them — so [index]'s valid range
  /// is clamped to `[its own minRatio, combined - next's minRatio]` in one
  /// step. That's deliberate: a plain `dx.clamp(minRatio, ...)` on [index]
  /// alone, followed by rejecting the whole update if [next] would end up
  /// under its min, "catches" correctly only while every pointer-move event
  /// carries a small delta — a single large one (a fast drag, or a
  /// synthetic big jump) would overshoot [next]'s min in one step and get
  /// rejected outright, freezing the handle short of the min instead of
  /// snapping to it. Deriving the range from the combined total instead
  /// means any delta, large or small, lands exactly at whichever column's
  /// min it would have crossed.
  void _resizeBoundary(int index, double dx, double flexSpace, GanttTheme theme) {
    final ratios = _columnRatios;
    if (ratios == null || flexSpace <= 0) return;
    final next = index + 1;
    if (next >= ratios.length) return;
    final columns = widget.columns!;
    // Fixed-width columns don't have a meaningful ratio to drag.
    if (columns[index].width != null || columns[next].width != null) {
      return;
    }
    final currentMinRatio = _effectiveMinWidth(index, theme) / flexSpace;
    final nextMinRatio = _effectiveMinWidth(next, theme) / flexSpace;
    final combined = ratios[index] + ratios[next];
    final maxCurrentRatio = combined - nextMinRatio;
    // Not enough combined space for both columns' minimums (e.g. the window
    // just got a lot narrower) — nothing sane to do until that changes.
    if (maxCurrentRatio < currentMinRatio) return;
    final ratioDelta = dx / flexSpace;
    final newCurrent = (ratios[index] + ratioDelta).clamp(
      currentMinRatio,
      maxCurrentRatio,
    );
    setState(() {
      ratios[index] = newCurrent;
      ratios[next] = combined - newCurrent;
    });
  }

  /// Reports the final ratios once a resize drag ends (see
  /// [ActivitiesList.onColumnWidthsChanged]) — not on every pointer move
  /// mid-drag, so a consumer persisting this doesn't write on every pixel.
  void _notifyColumnWidthsChanged() {
    final ratios = _columnRatios;
    if (ratios != null) {
      widget.onColumnWidthsChanged?.call(List.unmodifiable(ratios));
    }
  }

  /// Recursively builds widgets for activities and their children.
  List<Widget> getItems(
    BuildContext context,
    List<GanttActivity> activities,
    GanttTheme theme,
    GanttController controller,
    List<double>? widths, {
    int nested = 0,
  }) => List.generate(
    activities.length,
    (index) => Padding(
      padding: EdgeInsets.only(
        top: rowTopPadding(
          theme,
          nested,
          previousSibling: index > 0 ? activities[index - 1] : null,
          current: activities[index],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: theme.cellHeight,
            child: _ActivityRowInteraction(
              activity: activities[index],
              onSecondaryTap: widget.onActivitySecondaryTap,
              child:
                  widths != null
                      ? _buildColumnsRow(
                        context,
                        activities[index],
                        controller,
                        widths,
                      )
                      : _buildNameRow(theme, activities[index], controller),
            ),
          ),
          if (activities[index].children?.isNotEmpty == true &&
              !controller.isCollapsed(activities[index].key))
            ...getItems(
              context,
              activities[index].children!,
              theme,
              controller,
              widths,
              nested: nested + 1,
            ),
        ],
      ),
    ),
  );

  /// The chevron toggling [GanttController.isCollapsed] for [activity], or
  /// an empty spacer of the same width for a leaf activity — so every row's
  /// depth icon/name still line up vertically regardless of which rows have
  /// children.
  Widget _buildExpandToggle(
    GanttTheme theme,
    GanttController controller,
    GanttActivity activity,
  ) {
    final hasChildren = activity.children?.isNotEmpty == true;
    if (!hasChildren) return const SizedBox(width: 20, height: 20);
    final collapsed = controller.isCollapsed(activity.key);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // Raw pointer event, not InkWell/GestureDetector.onTap — see
      // _ActivityRowInteraction for why (gesture-arena wait feels delayed
      // inside a scrollable list).
      child: Listener(
        onPointerDown: (_) => controller.toggleCollapsed(activity.key),
        child: SizedBox(
          width: 20,
          height: 20,
          child: Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 18,
            color: theme.textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildNameRow(
    GanttTheme theme,
    GanttActivity activity,
    GanttController controller,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // Reserves indent width only — actual guide lines are painted by
      // TreeGuidesOverlay instead, as one continuous background layer (see
      // its doc comment for why a per-row painter can't do this).
      GanttTreeIndent(activity: activity, showGuides: false),
      _buildExpandToggle(theme, controller, activity),
      if (theme.depthIconBuilder?.call(activity.depth) case final icon?)
        Padding(padding: const EdgeInsets.only(right: 4), child: icon),
      if (activity.iconTitle != null)
        Padding(padding: EdgeInsets.only(right: 4), child: activity.iconTitle!),
      Expanded(
        child:
            activity.listTitleWidget ??
            activity.titleWidget ??
            Tooltip(
              message: activity.tooltip ?? '',
              child: Text(
                activity.listTitle ?? activity.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyle(weight: ganttNameWeightForDepth(activity.depth)),
              ),
            ),
      ),
      if (activity.actions?.isNotEmpty == true)
        Row(
          children:
              activity.actions!.map((e) {
                final child = IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: e.onTap,
                  icon: Icon(e.icon, size: theme.cellHeight * 0.8),
                );
                return e.tooltip != null
                    ? Tooltip(message: e.tooltip, child: child)
                    : child;
              }).toList(),
        ),
    ],
  );

  Widget _columnContent(
    BuildContext context,
    GanttTheme theme,
    GanttController controller,
    GanttActivity activity,
    int index,
  ) {
    final columns = widget.columns!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child:
          index == 0
              ? Row(
                children: [
                  GanttTreeIndent(activity: activity, showGuides: false),
                  _buildExpandToggle(theme, controller, activity),
                  if (theme.depthIconBuilder?.call(activity.depth)
                      case final icon?)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: icon,
                    ),
                  Expanded(
                    child: columns[index].cellBuilder(context, activity),
                  ),
                ],
              )
              : columns[index].cellBuilder(context, activity),
    );
  }

  Widget _buildColumnsRow(
    BuildContext context,
    GanttActivity activity,
    GanttController controller,
    List<double> widths,
  ) {
    final theme = context.watch<GanttTheme>();
    final columns = widget.columns!;
    return Row(
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          SizedBox(
            width: widths[i],
            child: _columnContent(context, theme, controller, activity, i),
          ),
          if (i < columns.length - 1)
            Center(
              child: Container(
                width: _dividerWidth,
                // A short tick centered on the row, not a wall-to-wall
                // line — every row draws its own, so consecutive rows read
                // as one continuous rail when they're flush, but a gap
                // between rows (a group boundary, say) breaks it exactly
                // there instead of a single line cutting across the gap.
                height: _columnDividerTickHeight,
                color: theme.dividerColor,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildHeaderRow(
    GanttTheme theme,
    List<double> widths,
    double flexSpace,
  ) {
    final columns = widget.columns!;
    final cells = <Widget>[];
    final handles = <Widget>[];
    var x = 0.0;
    for (var i = 0; i < columns.length; i++) {
      // Only the first column (the tree/name column every row indents
      // under) gets the depth-0 icon — it's the one column whose data rows
      // already carry a depth icon (see [_columnContent]), so the header
      // echoes it instead of showing a bare label.
      final headerIcon = i == 0 ? theme.depthIconBuilder?.call(0) : null;
      cells.add(
        SizedBox(
          width: widths[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (headerIcon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: headerIcon,
                  ),
                Expanded(
                  child: Text(
                    columns[i].header,
                    // A couple points larger than a cell's own text —
                    // visually sets the column titles apart from the rows
                    // underneath.
                    style: theme.textStyle(
                      size: theme.fontSize + 2,
                      weight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      x += widths[i];
      if (i < columns.length - 1) {
        cells.add(
          Center(
            child: Container(
              width: _dividerWidth,
              height: _columnDividerTickHeight,
              color: theme.dividerColor,
            ),
          ),
        );
        // A wider invisible hit area floats on top of the divider (not part
        // of the Row's own layout), so grabbing it doesn't need pixel-
        // perfect precision — the divider itself stays 1px, identical to
        // the one every data row below draws, so columns still line up.
        final boundaryIndex = i;
        handles.add(
          Positioned(
            left: x - 4,
            top: 0,
            bottom: 0,
            width: 8,
            child: _ColumnResizeHandle(
              onDrag: (dx) => _resizeBoundary(boundaryIndex, dx, flexSpace, theme),
              onDragEnd: _notifyColumnWidthsChanged,
            ),
          ),
        );
        x += _dividerWidth;
      }
    }
    return Stack(children: [Row(children: cells), ...handles]);
  }

  @override
  Widget build(BuildContext context) => Consumer<GanttTheme>(
    builder: (context, theme, child) {
      final ganttController = context.watch<GanttController>();
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = widget.columns;
          List<double>? widths;
          double flexSpace = 0;
          if (columns != null) {
            _ensureColumnRatios(columns);
            widths = _resolveWidths(columns, constraints.maxWidth);
            flexSpace = _flexSpace(columns, constraints.maxWidth);
          }
          return Column(
            children: [
              SizedBox(
                // The 1px divider right below (only drawn when `columns` is
                // set) is a separate sibling, not an overlay like the
                // matching divider on the calendar side (see Gantt.build) —
                // so without this -1, the two together would total
                // `headerHeight + 1`, pushing this pane's rows a pixel
                // below where the calendar's bars actually start.
                height:
                    theme.headerHeight +
                    (widget.showIsoWeek ? 10 : 0) -
                    (columns != null ? 1 : 0),
                child:
                    widths != null
                        ? _buildHeaderRow(theme, widths, flexSpace)
                        : null,
              ),
              if (columns != null)
                Container(height: 1, color: theme.dividerColor),
              Expanded(
                child: Stack(
                  children: [
                    if (widget.showTreeGuides)
                      Positioned.fill(
                        child: TreeGuidesOverlay(
                          activities: widget.activities,
                          verticalScrollController: widget.controller,
                        ),
                      ),
                    ListView(
                      controller: widget.controller,
                      children: getItems(
                        context,
                        widget.activities,
                        theme,
                        ganttController,
                        widths,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// The draggable region between two header columns: hovering shows a resize
/// cursor and dragging reports the horizontal delta via [onDrag]. Only
/// mounted in the header row — hovering/dragging a column's own data cells
/// never resizes anything.
class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({required this.onDrag, this.onDragEnd});

  final ValueChanged<double> onDrag;

  /// Fired once on release, only if the pointer actually moved (so a plain
  /// click on the handle without dragging doesn't fire it).
  final VoidCallback? onDragEnd;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  double? _lastX;
  bool _dragged = false;

  // Raw pointer events, not a drag GestureDetector — see
  // _ActivityRowInteraction's note on why a gesture-arena wait would feel
  // delayed here too (this handle also sits above a scrollable list).
  void _onPointerDown(PointerDownEvent event) {
    _lastX = event.position.dx;
    _dragged = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final last = _lastX;
    if (last == null) return;
    _lastX = event.position.dx;
    _dragged = true;
    widget.onDrag(event.position.dx - last);
  }

  void _onPointerUp(PointerUpEvent event) {
    _lastX = null;
    if (_dragged) {
      _dragged = false;
      widget.onDragEnd?.call();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _lastX = null;
    _dragged = false;
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: const SizedBox.expand(),
    ),
  );
}

/// Wraps a single activities-list row with hover and click-to-select
/// feedback: a faint tint on hover (list pane only — the chart pane has no
/// equivalent, since hovering the chart is about the bar underneath, not
/// the row), and clicking toggles [GanttController.selectedActivityKey],
/// which both this row and its matching chart-pane row (see
/// `GanttActivityRow`) then highlight, so it's clear which row is selected
/// from either side.
class _ActivityRowInteraction extends StatefulWidget {
  const _ActivityRowInteraction({
    required this.activity,
    required this.child,
    this.onSecondaryTap,
  });

  final GanttActivity activity;
  final Widget child;
  final void Function(GanttActivity activity, Offset globalPosition)?
  onSecondaryTap;

  @override
  State<_ActivityRowInteraction> createState() =>
      _ActivityRowInteractionState();
}

class _ActivityRowInteractionState extends State<_ActivityRowInteraction> {
  bool _hovered = false;
  Offset? _pointerDownPosition;

  // Raw pointer events, not GestureDetector.onTap — a tap recognizer has to
  // sit in the gesture arena and wait to see whether the gesture turns into
  // a drag before it can declare a plain tap, which is very perceptible
  // here since this row lives inside a scrollable ListView (competing with
  // its own pan recognizer). Same fix already used for bar selection in
  // SelectableBarGesture.
  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryMouseButton != 0) {
      widget.onSecondaryTap?.call(widget.activity, event.position);
      return;
    }
    _pointerDownPosition = event.position;
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _pointerDownPosition;
    _pointerDownPosition = null;
    if (start == null || (event.position - start).distance > 6) return;
    final controller = context.read<GanttController>();
    final isSelected = controller.selectedActivityKey == widget.activity.key;
    controller.selectedActivityKey = isSelected ? null : widget.activity.key;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<GanttTheme>();
    final controller = context.watch<GanttController>();
    final isSelected = controller.selectedActivityKey == widget.activity.key;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        child: Container(
          width: double.infinity,
          color:
              isSelected
                  ? theme.selectedRowColor
                  : (_hovered ? theme.hoverRowColor : null),
          child: widget.child,
        ),
      ),
    );
  }
}
