import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';

/// Draws the indentation preceding an activity row in the activities list,
/// and — when [showGuides] is `true` — the elbow/tee connector lines linking
/// it to its ancestors.
///
/// Always reserves the same width regardless of [showGuides], so toggling
/// guides on/off never changes row layout.
class GanttTreeIndent extends StatelessWidget {
  /// The activity this indent precedes.
  final GanttActivity activity;

  /// Whether to paint connector lines. When `false`, only the spacing is
  /// reserved.
  final bool showGuides;

  /// Creates a [GanttTreeIndent] for the given [activity].
  const GanttTreeIndent({
    super.key,
    required this.activity,
    this.showGuides = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<GanttTheme>();
    return SizedBox(
      width: theme.treeIndentWidth * (activity.depth + 1),
      child:
          showGuides && activity.depth > 0
              ? CustomPaint(
                painter: _TreeIndentPainter(
                  depth: activity.depth,
                  treeGuides: activity.treeGuides,
                  isLastChild: activity.isLastChild,
                  indentWidth: theme.treeIndentWidth,
                  color: theme.treeGuideColor,
                ),
                size: Size.infinite,
              )
              : null,
    );
  }
}

class _TreeIndentPainter extends CustomPainter {
  final int depth;
  final List<bool> treeGuides;
  final bool isLastChild;
  final double indentWidth;
  final Color color;

  _TreeIndentPainter({
    required this.depth,
    required this.treeGuides,
    required this.isLastChild,
    required this.indentWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1;
    final midY = size.height / 2;

    // Ancestor rails, excluding the immediate parent (handled below as the
    // branch point): a full-height line where that ancestor still has
    // siblings below it, nothing where it was its parent's last child.
    for (var i = 0; i < depth - 1; i++) {
      if (i < treeGuides.length && treeGuides[i]) {
        final x = indentWidth * i + indentWidth / 2;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }

    // This row's own branch point: elbow (stops here) or tee (continues,
    // because a sibling follows this row).
    final branchX = indentWidth * (depth - 1) + indentWidth / 2;
    canvas.drawLine(Offset(branchX, 0), Offset(branchX, midY), paint);
    canvas.drawLine(
      Offset(branchX, midY),
      Offset(indentWidth * depth, midY),
      paint,
    );
    if (!isLastChild) {
      canvas.drawLine(
        Offset(branchX, midY),
        Offset(branchX, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TreeIndentPainter oldDelegate) =>
      oldDelegate.depth != depth ||
      oldDelegate.isLastChild != isLastChild ||
      oldDelegate.color != color ||
      oldDelegate.indentWidth != indentWidth ||
      !_boolListEquals(oldDelegate.treeGuides, treeGuides);
}

bool _boolListEquals(List<bool> a, List<bool> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
