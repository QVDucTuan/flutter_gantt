import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/row_geometry.dart';
import 'controller.dart';

/// Draws every tree connector guide line for [activities] in one pass, in
/// absolute row coordinates (via [computeRowGeometry]) rather than one
/// [CustomPaint] per row confined to that row's own height.
///
/// A per-row painter can only draw within its own row box, so a rail linking
/// two rows that aren't adjacent — e.g. a Subtask to its next Subtask
/// sibling, when the first Subtask has children of its own in between —
/// breaks across every row-padding gap and every intervening descendant row.
/// This overlay instead draws each connector as a single line straight from
/// one row's center to the next, so it reads as one continuous stroke
/// regardless of what (or how much) sits between them.
///
/// Meant to be mounted as a background layer behind `ActivitiesList`'s
/// `ListView` — the list's own rows still reserve indentation width via
/// `GanttTreeIndent(showGuides: false)`, they just don't paint the lines
/// themselves anymore.
class TreeGuidesOverlay extends StatelessWidget {
  /// The root activities to draw guides for.
  final List<GanttActivity> activities;

  /// `ActivitiesList`'s own vertical [ScrollController] — this overlay isn't
  /// inside the scrolling `ListView` itself, so it tracks the same offset
  /// to stay visually attached to the rows while they scroll.
  final ScrollController? verticalScrollController;

  /// Creates a [TreeGuidesOverlay] for the given [activities].
  const TreeGuidesOverlay({
    super.key,
    required this.activities,
    this.verticalScrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<GanttTheme>();
    final ganttController = context.watch<GanttController>();
    final geometry = computeRowGeometry(
      activities,
      theme,
      isCollapsed: ganttController.isCollapsed,
    );

    final painter = CustomPaint(
      painter: _TreeGuidesPainter(
        activities: activities,
        geometry: geometry,
        indentWidth: theme.treeIndentWidth,
        color: theme.treeGuideColor,
        isCollapsed: ganttController.isCollapsed,
      ),
      size: Size.infinite,
    );

    final controller = verticalScrollController;
    if (controller == null) {
      return IgnorePointer(child: ClipRect(child: painter));
    }

    return IgnorePointer(
      child: ClipRect(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            // Read via `positions` (plural), not `offset`/`position` — those
            // assert exactly one attached view, which doesn't hold for the
            // one frame where the list's ListView is mid-remount.
            final positions = controller.positions;
            final offset =
                positions.length == 1 ? positions.single.pixels : 0.0;
            return Transform.translate(
              offset: Offset(0, -offset),
              child: child,
            );
          },
          child: painter,
        ),
      ),
    );
  }
}

class _TreeGuidesPainter extends CustomPainter {
  final List<GanttActivity> activities;
  final Map<String, GanttRowGeometry> geometry;
  final double indentWidth;
  final Color color;
  final bool Function(String key) isCollapsed;

  _TreeGuidesPainter({
    required this.activities,
    required this.geometry,
    required this.indentWidth,
    required this.color,
    required this.isCollapsed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1;

    void walk(List<GanttActivity> items) {
      for (final activity in items) {
        final geo = geometry[activity.key];
        if (geo != null) {
          if (activity.depth > 0) {
            // This row's own elbow: branches off its parent's rail column
            // and reaches into its own indent column.
            final branchX =
                indentWidth * (activity.depth - 1) + indentWidth / 2;
            canvas.drawLine(
              Offset(branchX, geo.centerY),
              Offset(indentWidth * activity.depth, geo.centerY),
              paint,
            );
            // Rail continuing straight down to the next sibling's own
            // elbow, at this row's own branch column — one line regardless
            // of how many descendant rows sit in between.
            if (!activity.isLastChild) {
              final siblings = activity.parent?.children ?? activities;
              final index = siblings.indexWhere(
                (e) => identical(e, activity),
              );
              if (index != -1 && index + 1 < siblings.length) {
                final nextGeo = geometry[siblings[index + 1].key];
                if (nextGeo != null) {
                  canvas.drawLine(
                    Offset(branchX, geo.centerY),
                    Offset(branchX, nextGeo.centerY),
                    paint,
                  );
                }
              }
            }
          }
          // Drop straight down into the first child, if any — unconditional
          // (unrelated to sibling order), so even a root activity connects
          // to its own first child. Skipped while collapsed, since there's
          // nothing visible below to connect to.
          final children = activity.children;
          if (children != null &&
              children.isNotEmpty &&
              !isCollapsed(activity.key)) {
            final firstGeo = geometry[children.first.key];
            if (firstGeo != null) {
              final x = indentWidth * activity.depth + indentWidth / 2;
              canvas.drawLine(
                Offset(x, geo.centerY),
                Offset(x, firstGeo.centerY),
                paint,
              );
            }
          }
        }
        final children = activity.children;
        if (children != null &&
            children.isNotEmpty &&
            !isCollapsed(activity.key)) {
          walk(children);
        }
      }
    }

    walk(activities);
  }

  // Always repaint: `isCollapsed` is a closure, cheap to call but not
  // meaningfully comparable between old/new delegates, and `activities`
  // commonly stays the same List reference even when its collapsed subset
  // changed. Repainting this each rebuild is inexpensive.
  @override
  bool shouldRepaint(covariant _TreeGuidesPainter oldDelegate) => true;
}
