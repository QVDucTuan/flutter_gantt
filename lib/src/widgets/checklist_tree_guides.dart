import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/row_geometry.dart';
import 'below_header_clip.dart';
import 'controller.dart';
import 'controller_extension.dart';

/// Draws the tree connector guide lines for checklist rows (activities with
/// [GanttActivity.showCell] `false`, see `GanttActivityRow`'s checklist
/// branch) in the chart pane, as one continuous background layer — same
/// approach as `TreeGuidesOverlay` does for `ActivitiesList`, and for the
/// same reason: a line painted per-row, confined to that row's own height,
/// breaks across every row-padding gap between siblings.
///
/// Meant to be mounted by [Gantt] as a Stack layer alongside
/// `GanttGroupCapsules`/`DependencyArrows`, when `Gantt.showTreeGuides` is
/// set — renders nothing otherwise.
class ChecklistTreeGuides extends StatelessWidget {
  /// The activities to scan for checklist children.
  final List<GanttActivity> activities;

  /// The activities grid's own vertical [ScrollController] — this overlay
  /// is a sibling layer, not inside the grid's scrolling list, so this
  /// keeps it visually attached to the rows while they scroll.
  final ScrollController verticalScrollController;

  /// Whether the ISO week number row is shown (affects the header height
  /// this layer must be offset by, matching `ActivitiesGrid`).
  final bool showIsoWeek;

  /// Creates a [ChecklistTreeGuides] layer for the given [activities].
  const ChecklistTreeGuides({
    super.key,
    required this.activities,
    required this.verticalScrollController,
    this.showIsoWeek = false,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GanttController>();
    final theme = context.watch<GanttTheme>();
    final geometry = computeRowGeometry(
      activities,
      theme,
      isCollapsed: controller.isCollapsed,
    );
    final headerOffset = headerOffsetFor(theme, showIsoWeek);

    return IgnorePointer(
      child: BelowHeaderClip(
        top: headerOffset,
        child: ListenableBuilder(
          listenable: verticalScrollController,
          builder: (context, child) {
            // Read via `positions` (plural), not `offset`/`position` — those
            // assert exactly one attached view, which doesn't hold for the
            // one frame where the grid's ListView is mid-remount.
            final positions = verticalScrollController.positions;
            final offset =
                positions.length == 1 ? positions.single.pixels : 0.0;
            return Transform.translate(
              offset: Offset(0, headerOffset - offset),
              child: child,
            );
          },
          child: CustomPaint(
            painter: _ChecklistGuidesPainter(
              activities: activities,
              geometry: geometry,
              controller: controller,
              indentWidth: theme.treeIndentWidth,
              color: theme.treeGuideColor,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _ChecklistGuidesPainter extends CustomPainter {
  final List<GanttActivity> activities;
  final Map<String, GanttRowGeometry> geometry;
  final GanttController controller;
  final double indentWidth;
  final Color color;

  _ChecklistGuidesPainter({
    required this.activities,
    required this.geometry,
    required this.controller,
    required this.indentWidth,
    required this.color,
  });

  /// The same x offset `GanttActivityRow._buildChecklistRow` positions a
  /// checklist row at: its owning bar's (parent's) own date-based offset,
  /// shared by every sibling under that parent — not each child's own date,
  /// which would put siblings at different x positions (see the fix this
  /// mirrors on the chart side).
  double _spaceBeforeFor(GanttActivity anchor) =>
      controller.dayColumnWidth * controller.getCellDaysBefore(anchor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1;

    void walk(List<GanttActivity> items) {
      for (final activity in items) {
        final children = activity.children;
        if (children != null && children.isNotEmpty) {
          final checklistChildren = children.where((c) => !c.showCell).toList();
          if (checklistChildren.isNotEmpty) {
            final spaceBefore = _spaceBeforeFor(activity);
            var previousGeo = geometry[activity.key];
            for (final child in checklistChildren) {
              final childGeo = geometry[child.key];
              if (childGeo == null) continue;
              final depth = child.depth;
              final branchX =
                  spaceBefore + indentWidth * (depth - 1) + indentWidth / 2;
              // Elbow into this row's own checkbox/name.
              canvas.drawLine(
                Offset(branchX, childGeo.centerY),
                Offset(spaceBefore + indentWidth * depth, childGeo.centerY),
                paint,
              );
              // Rail from the previous row (the owning bar, or the
              // previous checklist sibling) straight down to this one.
              if (previousGeo != null) {
                canvas.drawLine(
                  Offset(branchX, previousGeo.centerY),
                  Offset(branchX, childGeo.centerY),
                  paint,
                );
              }
              previousGeo = childGeo;
            }
          }
        }
        if (children != null && children.isNotEmpty) walk(children);
      }
    }

    walk(activities);
  }

  // Always repaint — see TreeGuidesOverlay's identical note: `geometry`
  // (and thus collapsed state) isn't cheaply comparable between delegates,
  // and `activities` commonly keeps the same List reference regardless.
  @override
  bool shouldRepaint(covariant _ChecklistGuidesPainter oldDelegate) => true;
}
