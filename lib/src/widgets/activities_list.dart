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

  @override
  State<ActivitiesList> createState() => _ActivitiesListState();
}

class _ActivitiesListState extends State<ActivitiesList> {
  static const double _minColumnWidth = 40.0;
  static const double _dividerWidth = 1.0;

  List<double>? _columnWidths;

  void _ensureColumnWidths(List<GanttListColumn> columns, double totalWidth) {
    if (_columnWidths != null && _columnWidths!.length == columns.length) {
      return;
    }
    final fixedTotal = columns.fold<double>(
      0,
      (sum, c) => sum + (c.width ?? 0),
    );
    final flexTotal = columns.fold<double>(
      0,
      (sum, c) => sum + (c.width == null ? (c.flex ?? 1) : 0),
    );
    final dividersWidth = (columns.length - 1) * _dividerWidth;
    final flexSpace = (totalWidth - fixedTotal - dividersWidth).clamp(
      0.0,
      double.infinity,
    );
    _columnWidths = [
      for (final c in columns)
        c.width ??
            (flexTotal > 0
                ? flexSpace * (c.flex ?? 1) / flexTotal
                : flexSpace / columns.length),
    ];
  }

  /// Drags width between column [index] and the column right after it, so
  /// resizing one column always borrows/gives space to its neighbor instead
  /// of changing the row's total width.
  void _resizeBoundary(int index, double dx) {
    final widths = _columnWidths;
    if (widths == null) return;
    final next = index + 1;
    if (next >= widths.length) return;
    final newCurrent = (widths[index] + dx).clamp(
      _minColumnWidth,
      double.infinity,
    );
    final actualDelta = newCurrent - widths[index];
    final newNext = widths[next] - actualDelta;
    if (newNext < _minColumnWidth) return;
    setState(() {
      widths[index] = newCurrent;
      widths[next] = newNext;
    });
  }

  /// Recursively builds widgets for activities and their children.
  List<Widget> getItems(
    BuildContext context,
    List<GanttActivity> activities,
    GanttTheme theme,
    GanttController controller, {
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
              child:
                  widget.columns != null
                      ? _buildColumnsRow(context, activities[index], controller)
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
                style: theme.textStyle(weight: _nameWeightForDepth(activity.depth)),
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
  ) {
    final theme = context.watch<GanttTheme>();
    final columns = widget.columns!;
    final widths = _columnWidths!;
    return Row(
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          SizedBox(
            width: widths[i],
            child: _columnContent(context, theme, controller, activity, i),
          ),
          if (i < columns.length - 1)
            Container(
              width: _dividerWidth,
              height: double.infinity,
              color: theme.dividerColor,
            ),
        ],
      ],
    );
  }

  Widget _buildHeaderRow(GanttTheme theme) {
    final columns = widget.columns!;
    final widths = _columnWidths!;
    final cells = <Widget>[];
    final handles = <Widget>[];
    var x = 0.0;
    for (var i = 0; i < columns.length; i++) {
      cells.add(
        SizedBox(
          width: widths[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              columns[i].header,
              style: theme.textStyle(weight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      x += widths[i];
      if (i < columns.length - 1) {
        cells.add(
          Container(
            width: _dividerWidth,
            height: double.infinity,
            color: theme.dividerColor,
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
              onDrag: (dx) => _resizeBoundary(boundaryIndex, dx),
            ),
          ),
        );
        x += _dividerWidth;
      }
    }
    return Stack(children: [Row(children: cells), ...handles]);
  }

  /// Matches QV's row-name weight scale: 600 at depth 0, 500 at depth 1,
  /// 400 at depth 2+.
  static FontWeight _nameWeightForDepth(int depth) => switch (depth) {
    0 => FontWeight.w600,
    1 => FontWeight.w500,
    _ => FontWeight.w400,
  };

  @override
  Widget build(BuildContext context) => Consumer<GanttTheme>(
    builder: (context, theme, child) {
      final ganttController = context.watch<GanttController>();
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = widget.columns;
          if (columns != null) {
            _ensureColumnWidths(columns, constraints.maxWidth);
          }
          return Column(
            children: [
              SizedBox(
                height: theme.headerHeight + (widget.showIsoWeek ? 10 : 0),
                child: columns != null ? _buildHeaderRow(theme) : null,
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
  const _ColumnResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  double? _lastX;

  // Raw pointer events, not a drag GestureDetector — see
  // _ActivityRowInteraction's note on why a gesture-arena wait would feel
  // delayed here too (this handle also sits above a scrollable list).
  void _onPointerDown(PointerDownEvent event) => _lastX = event.position.dx;

  void _onPointerMove(PointerMoveEvent event) {
    final last = _lastX;
    if (last == null) return;
    _lastX = event.position.dx;
    widget.onDrag(event.position.dx - last);
  }

  void _onPointerUp(PointerUpEvent event) => _lastX = null;

  void _onPointerCancel(PointerCancelEvent event) => _lastX = null;

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
  const _ActivityRowInteraction({required this.activity, required this.child});

  final GanttActivity activity;
  final Widget child;

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
