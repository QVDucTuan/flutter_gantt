import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/datetime.dart';
import 'cell.dart';
import 'controller.dart';
import 'controller_extension.dart';
import 'selectable_bar_gesture.dart';
import 'tree_indent.dart';

/// A single row in the Gantt chart representing an activity.
///
/// This widget handles the display and interaction for a single activity,
/// including drag-to-move and resize functionality.
class GanttActivityRow extends StatefulWidget {
  /// The [GanttActivity] to display in this row.
  final GanttActivity activity;

  /// Creates a row for the specified activity.
  const GanttActivityRow({super.key, required this.activity});

  @override
  State<GanttActivityRow> createState() => _GanttActivityRowState();
}

class _GanttActivityRowState extends State<GanttActivityRow> {
  late GanttActivityCtrl _ctrl;
  double? _movementX;
  double? _movementStartX;
  double? _movementStartOffset;
  double? _movementEndX;
  double? _movementEndOffset;
  int? daysDelta;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  @override
  void didUpdateWidget(GanttActivityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity != widget.activity) {
      _ctrl.dispose();
      _createController();
      setState(() {});
    }
  }

  void _createController() {
    _ctrl = GanttActivityCtrl(
      controller: context.read<GanttController>(),
      activity: widget.activity,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: _ctrl,
    builder: (context, child) {
      final theme = context.watch<GanttTheme>();
      final isSelected =
          context.watch<GanttController>().selectedActivityKey ==
          widget.activity.key;
      // Full row width regardless of ambient constraints, so the highlight
      // spans the whole chart row — not just whatever width the bar/
      // checklist content itself happens to occupy.
      return SizedBox(
        width: double.infinity,
        height: theme.cellHeight,
        child: Container(
          color: isSelected ? theme.selectedRowColor : null,
          child: _buildContent(context),
        ),
      );
    },
  );

  /// Builds the row content based on activity visibility.
  Widget _buildContent(BuildContext context) {
    final activity = widget.activity;
    final ctrl = context.watch<GanttActivityCtrl>();

    if (!activity.showCell) return _buildChecklistRow(context, activity, ctrl);

    final theme = context.read<GanttTheme>();
    if (ctrl.cellVisible) {
      // Shrinks the bar within its (taller) row slot — see
      // GanttTheme.barVerticalPadding.
      final cell = Padding(
        padding: EdgeInsets.symmetric(vertical: theme.barVerticalPadding),
        child: _buildCell(context, activity, ctrl),
      );
      final controller = context.watch<GanttController>();
      if (controller.interactionMode == GanttInteractionMode.selectableDrag) {
        return SelectableBarGesture(activity: activity, ctrl: ctrl, cell: cell);
      }
      return _buildLongPressDragRow(activity, ctrl, theme, cell);
    }

    final isBefore = ctrl.showBefore;
    // Check text direction to handle RTL correctly
    final textDirection = Directionality.of(context);
    final isRTL = textDirection == TextDirection.rtl;
    // In RTL, invert the alignment: left becomes right and vice versa
    final alignment =
        isBefore
            ? (isRTL ? Alignment.centerRight : Alignment.centerLeft)
            : (isRTL ? Alignment.centerLeft : Alignment.centerRight);
    final icon = isBefore ? Icons.navigate_before : Icons.navigate_next;
    final children = <Widget>[
      Icon(icon),
      Flexible(
        child:
            activity.titleWidget ??
            Text(activity.title!, overflow: TextOverflow.ellipsis),
      ),
    ];

    return Align(
      alignment: alignment,
      child: Tooltip(
        message: '${activity.start.toLocal()} - ${activity.end.toLocal()}',
        child: InkWell(
          onTap:
              () => context.read<GanttController>().startDate = activity.start,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: isBefore ? children : children.reversed.toList(),
          ),
        ),
      ),
    );
  }

  /// Builds the in-chart content for an activity with [GanttActivity.showCell]
  /// `false` — a tree connector (linking it to its parent) followed by its
  /// [GanttActivity.titleWidget] (or a plain title fallback), instead of a
  /// date-bound bar. Used for activities that are conceptually a checklist
  /// item, not a scheduled span (e.g. a third-level "subitem" with just a
  /// name and a completion checkbox).
  ///
  /// Starts at the *parent's* space-before offset, not this activity's own —
  /// every sibling under the same parent then lines up at the same x
  /// (still inside the parent's group capsule, since a child's dates always
  /// fall inside its parent's), instead of drifting left/right relative to
  /// each other purely because their own start dates differ.
  ///
  /// Renders nothing (the row's own slot stays reserved — geometry, tree
  /// guides, and the linked list/chart scroll all still depend on it) once
  /// the parent's own bar drops below [GanttTheme.childrenPeekWidthThreshold]
  /// — this content would otherwise render at full size regardless of how
  /// narrow the parent's date span is, visually spilling out past its group
  /// capsule. [GanttCell] shows a hover icon on the parent's bar instead
  /// (see [Gantt.onPeekChildrenTap]); the activities list pane is
  /// unaffected either way, since it was never date-width-bound.
  ///
  /// Above that threshold, content is still bounded to the parent's own
  /// rendered width (not left free to span the rest of the canvas row) —
  /// otherwise a name too long to fit would keep overflowing past the
  /// group capsule instead of ellipsizing at its edge, the same visual
  /// spill the threshold above exists to prevent, just at a wider bar.
  Widget _buildChecklistRow(
    BuildContext context,
    GanttActivity activity,
    GanttActivityCtrl ctrl,
  ) {
    final theme = context.watch<GanttTheme>();
    final controller = context.watch<GanttController>();
    final parent = activity.parent;
    final parentWidth =
        parent == null
            ? null
            : controller.dayColumnWidth * controller.getCellDays(parent);
    if (parentWidth != null && parentWidth < theme.childrenPeekWidthThreshold) {
      return const SizedBox.shrink();
    }
    final spaceBefore =
        parent == null
            ? ctrl.spaceBefore
            : ctrl.dayColumnWidth * controller.getCellDaysBefore(parent);
    final content = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          // Reserves indent width only — actual guide lines are
          // painted by ChecklistTreeGuides instead, as one continuous
          // background layer (see its doc comment for why a per-row
          // painter can't do this).
          GanttTreeIndent(activity: activity, showGuides: false),
          Expanded(
            child:
                activity.titleWidget ??
                Text(
                  activity.listTitle ?? activity.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyle(
                    weight: theme.nameWeightForDepth?.call(activity.depth),
                  ),
                ),
          ),
        ],
      ),
    );
    return Row(
      children: [
        SizedBox(width: spaceBefore),
        parentWidth == null
            ? Expanded(child: content)
            : SizedBox(width: parentWidth, child: content),
      ],
    );
  }

  /// Builds the row's visual bar content — independent of which drag
  /// mechanism (see [GanttController.interactionMode]) wraps it.
  Widget _buildCell(
    BuildContext context,
    GanttActivity activity,
    GanttActivityCtrl ctrl,
  ) =>
      activity.builder != null
          ? activity.builder!(activity)
          : activity.cellBuilder != null
          ? Row(
            children: List<Widget>.generate(
              ctrl.cellVisibleDays,
              (index) => Expanded(
                child: activity.cellBuilder!(
                  context
                      .read<GanttController>()
                      .clampToGanttRange(activity.start)
                      .add(Duration(days: index)),
                ),
              ),
            ),
          )
          : Tooltip(
            message: activity.tooltip ?? '',
            child: GanttCell(activity: activity),
          );

  /// The default drag interaction: always-visible edge handles, ghost-
  /// feedback whole-bar drag via long-press. Used when
  /// [GanttController.interactionMode] is
  /// [GanttInteractionMode.longPressDrag] (the default) — see
  /// [SelectableBarGesture] for the alternative.
  Widget _buildLongPressDragRow(
    GanttActivity activity,
    GanttActivityCtrl ctrl,
    GanttTheme theme,
    Widget cell,
  ) {
    final Widget draggableEdge = MouseRegion(
      cursor: SystemMouseCursors.resizeRight,
      child: Container(
        color: Colors.white.withValues(alpha: .3),
        width: 4,
        height: theme.cellHeight / 1.5,
      ),
    );

    final cellContent = Stack(
      fit: StackFit.expand,
      children: [
        cell,
        Positioned(
          left: 0,
          bottom: 0,
          child: LongPressDraggable<GanttActivity>(
            delay: _ctrl.controller.dragStartDelay,
            feedback: draggableEdge,
            data: activity,
            axis: Axis.horizontal,
            child: draggableEdge,
            onDragStarted: () {
              _movementStartX = null;
              _movementStartOffset = null;
            },
            onDragUpdate: (details) {
              setState(() {
                _movementStartX ??= details.globalPosition.dx;
                final dxTotal = details.globalPosition.dx - _movementStartX!;
                final daysDeltaTemp = (dxTotal / _ctrl.dayColumnWidth).round();
                if (_ctrl.cellVisibleDays - daysDeltaTemp > 0 &&
                    (widget.activity.validStartMove(daysDeltaTemp) ||
                        (_ctrl.controller.allowParentIndependentDateMovement &&
                            widget.activity.validStartMoveIgnoringChildren(
                              daysDeltaTemp,
                            )))) {
                  daysDelta = daysDeltaTemp;
                }
                _movementStartOffset = _ctrl.dayColumnWidth * daysDelta!;
              });
            },
            onDragEnd: (_) {
              if (daysDelta != null && daysDelta != 0) {
                _ctrl.controller.onActivityChanged(
                  widget.activity,
                  start: widget.activity.start.addDays(daysDelta!),
                );
              }
              _movementStartX = null;
              _movementStartOffset = null;
            },
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: LongPressDraggable<GanttActivity>(
            delay: _ctrl.controller.dragStartDelay,
            feedback: draggableEdge,
            data: activity,
            axis: Axis.horizontal,
            child: draggableEdge,
            onDragStarted: () {
              _movementEndX = null;
              _movementEndOffset = null;
            },
            onDragUpdate: (details) {
              setState(() {
                _movementEndX ??= details.globalPosition.dx;
                final dxTotal = details.globalPosition.dx - _movementEndX!;
                final daysDeltaTemp = (dxTotal / _ctrl.dayColumnWidth).round();
                if (_ctrl.cellVisibleDays + daysDeltaTemp > 0 &&
                    (widget.activity.validEndMove(daysDeltaTemp) ||
                        (_ctrl.controller.allowParentIndependentDateMovement &&
                            widget.activity.validEndMoveIgnoringChildren(
                              daysDeltaTemp,
                            )))) {
                  daysDelta = daysDeltaTemp;
                }
                _movementEndOffset = _ctrl.dayColumnWidth * daysDelta!;
              });
            },
            onDragEnd: (_) {
              if (daysDelta != null && daysDelta != 0) {
                _ctrl.controller.onActivityChanged(
                  widget.activity,
                  end: widget.activity.end.addDays(daysDelta!),
                );
              }
              _movementEndX = null;
              _movementEndOffset = null;
            },
          ),
        ),
      ],
    );

    final dragCell = LongPressDraggable<GanttActivity>(
      delay: _ctrl.controller.dragStartDelay,
      data: activity,
      axis: Axis.horizontal,
      feedback: Material(
        elevation: 6,
        color: Colors.transparent,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: _ctrl),
            Provider.value(value: theme),
          ],
          builder:
              (context, child) => Opacity(
                opacity: 0.85,
                child: SizedBox(
                  width: ctrl.cellVisibleWidth,
                  height: theme.cellHeight,
                  child: cellContent,
                ),
              ),
        ),
      ),
      childWhenDragging: const SizedBox.shrink(),
      onDragStarted: () {
        _movementX = null;
      },
      onDragUpdate: (details) {
        _movementX ??= details.globalPosition.dx;
        final dxTotal = details.globalPosition.dx - _movementX!;
        final daysDeltaTemp = (dxTotal / _ctrl.dayColumnWidth).round();
        if (widget.activity.validMove(daysDeltaTemp) ||
            (_ctrl.controller.allowParentIndependentDateMovement &&
                widget.activity.validMoveToParent(daysDeltaTemp))) {
          daysDelta = daysDeltaTemp;
        }
      },
      onDragEnd: (_) {
        if (daysDelta != null && daysDelta != 0) {
          _ctrl.controller.onActivityChanged(
            widget.activity,
            start: widget.activity.start.addDays(daysDelta!),
            end: widget.activity.end.addDays(daysDelta!),
          );
        }
        _movementX = null;
      },
      child: cellContent,
    );

    return Row(
      children: [
        SizedBox(
          // Clamped, not the delta — dragging past the rendered edge
          // keeps tracking the pointer (the commit on drag-end still
          // uses the real, unclamped delta), it just can't draw past 0.
          width: (ctrl.spaceBefore + (_movementStartOffset ?? 0)).clamp(
            0.0,
            double.infinity,
          ),
          child: Container(),
        ),
        SizedBox(
          width:
              ctrl.cellVisibleWidth -
              (_movementStartOffset ?? 0) +
              (_movementEndOffset ?? 0),
          child: _ctrl.controller.enableDraggable ? dragCell : cell,
        ),
      ],
    );
  }
}
