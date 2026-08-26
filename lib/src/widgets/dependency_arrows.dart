import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/row_geometry.dart';
import 'below_header_clip.dart';
import 'controller.dart';
import 'controller_extension.dart';

/// Draws an orthogonal connector with an arrowhead from every activity's
/// predecessors (see [GanttActivity.dependsOn]) to itself.
///
/// Meant to be mounted by [Gantt] automatically in scroll mode — renders
/// nothing if no activity has [GanttActivity.dependsOn] set. Ignores pointer
/// events, so bars underneath stay interactive.
class DependencyArrows extends StatelessWidget {
  /// The activities to scan for [GanttActivity.dependsOn].
  final List<GanttActivity> activities;

  /// The activities grid's own vertical [ScrollController] — arrows are
  /// drawn as a sibling layer, not inside the grid's scrolling list, so
  /// this keeps them visually attached to their rows while it scrolls.
  final ScrollController verticalScrollController;

  /// Whether the ISO week number row is shown (affects the header height
  /// arrows must be offset by, matching `ActivitiesGrid`).
  final bool showIsoWeek;

  /// Creates a [DependencyArrows] layer for the given [activities].
  const DependencyArrows({
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
    final all = activities.plainList;
    final headerOffset = theme.headerHeight + (showIsoWeek ? 10 : 0);

    final arrows = <_ArrowSpec>[];
    for (final target in all) {
      final dependsOn = target.dependsOn;
      if (dependsOn == null || dependsOn.isEmpty) continue;
      final targetGeometry = geometry[target.key];
      if (targetGeometry == null) continue;
      for (final sourceKey in dependsOn) {
        final source = all.getFromKey(sourceKey);
        final sourceGeometry = source == null ? null : geometry[source.key];
        if (source == null || sourceGeometry == null) continue;
        arrows.add(
          _ArrowSpec(
            startX:
                controller.xForDate(source.end) + controller.dayColumnWidth,
            startY: headerOffset + sourceGeometry.centerY,
            endX: controller.xForDate(target.start),
            endY: headerOffset + targetGeometry.centerY,
          ),
        );
      }
    }

    if (arrows.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: BelowHeaderClip(
        top: headerOffset,
        child: ListenableBuilder(
          listenable: verticalScrollController,
          builder: (context, child) {
            // Read via `positions` (plural), not the `offset`/`position`
            // getters — those assert exactly one attached view, which
            // doesn't hold for the one frame where the grid's ListView is
            // mid-remount (e.g. scroll mode just toggled).
            final positions = verticalScrollController.positions;
            final offset = positions.length == 1 ? positions.single.pixels : 0.0;
            return Transform.translate(offset: Offset(0, -offset), child: child);
          },
          child: CustomPaint(
            painter: _DependencyArrowsPainter(
              arrows: arrows,
              color: theme.dependencyArrowColor,
              strokeWidth: theme.dependencyArrowWidth,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _ArrowSpec {
  final double startX;
  final double startY;
  final double endX;
  final double endY;

  const _ArrowSpec({
    required this.startX,
    required this.startY,
    required this.endX,
    required this.endY,
  });

  @override
  bool operator ==(Object other) =>
      other is _ArrowSpec &&
      startX == other.startX &&
      startY == other.startY &&
      endX == other.endX &&
      endY == other.endY;

  @override
  int get hashCode => Object.hash(startX, startY, endX, endY);
}

class _DependencyArrowsPainter extends CustomPainter {
  final List<_ArrowSpec> arrows;
  final Color color;
  final double strokeWidth;

  _DependencyArrowsPainter({
    required this.arrows,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke;
    final headPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.fill;

    for (final arrow in arrows) {
      final midX = (arrow.startX + arrow.endX) / 2;
      final path =
          Path()
            ..moveTo(arrow.startX, arrow.startY)
            ..lineTo(midX, arrow.startY)
            ..lineTo(midX, arrow.endY)
            ..lineTo(arrow.endX, arrow.endY);
      canvas.drawPath(path, linePaint);

      const headSize = 5.0;
      final tip = Offset(arrow.endX, arrow.endY);
      final head =
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(tip.dx - headSize, tip.dy - headSize)
            ..lineTo(tip.dx - headSize, tip.dy + headSize)
            ..close();
      canvas.drawPath(head, headPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DependencyArrowsPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      !listEquals(oldDelegate.arrows, arrows);
}
