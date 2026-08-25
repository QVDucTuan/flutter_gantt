import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/row_geometry.dart';
import 'controller.dart';
import 'controller_extension.dart';

/// Draws a background capsule wrapping every activity that has children,
/// spanning that activity's own row through its last visible descendant.
///
/// Meant to be mounted by [Gantt] automatically in scroll mode when
/// `Gantt.showGroupCapsules` is set — renders nothing otherwise. Ignores
/// pointer events, so bars underneath stay interactive.
class GanttGroupCapsules extends StatelessWidget {
  /// The activities to scan for children.
  final List<GanttActivity> activities;

  /// The activities grid's own vertical [ScrollController] — capsules are
  /// drawn as a sibling layer, not inside the grid's scrolling list, so
  /// this keeps them visually attached to their rows while it scrolls.
  final ScrollController verticalScrollController;

  /// Whether the ISO week number row is shown (affects the header height
  /// capsules must be offset by, matching `ActivitiesGrid`).
  final bool showIsoWeek;

  /// Creates a [GanttGroupCapsules] layer for the given [activities].
  const GanttGroupCapsules({
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
    final headerOffset = theme.headerHeight + (showIsoWeek ? 10 : 0);

    final capsules = <_CapsuleSpec>[];

    void collect(List<GanttActivity> items, int depth) {
      for (final activity in items) {
        final children = activity.children;
        if (children == null ||
            children.isEmpty ||
            controller.isCollapsed(activity.key)) {
          continue;
        }

        final decoration =
            theme.groupCapsuleStyle != null
                ? theme.groupCapsuleStyle!(activity, depth)
                : _defaultCapsuleStyle(theme, depth);
        if (decoration != null) {
          double? top;
          double? bottom;
          for (final descendant in activity.plainList) {
            final rowGeometry = geometry[descendant.key];
            if (rowGeometry == null) continue;
            // Anchor to the bar's own rendered edges, not the row slot's —
            // a bar is inset by barVerticalPadding within its (taller) row,
            // so hugging the raw row bounds left a visibly bigger gap on
            // top/bottom than groupCapsuleHorizontalPadding leaves on the
            // sides. Checklist rows (showCell false) have no such inset.
            final barInset = descendant.showCell ? theme.barVerticalPadding : 0.0;
            final rowTop = rowGeometry.top + barInset;
            final rowBottom = rowGeometry.top + rowGeometry.height - barInset;
            top = top == null ? rowTop : math.min(top, rowTop);
            bottom = bottom == null ? rowBottom : math.max(bottom, rowBottom);
          }
          if (top != null && bottom != null) {
            final left =
                controller.xForDate(activity.start) -
                theme.groupCapsuleHorizontalPadding;
            final right =
                controller.xForDate(activity.end) +
                controller.dayColumnWidth +
                theme.groupCapsuleHorizontalPadding;
            final verticalPadding = _verticalPaddingForDepth(theme, depth);
            final paddedTop = top - verticalPadding;
            final paddedBottom = bottom + verticalPadding;
            capsules.add(
              _CapsuleSpec(
                left: left,
                top: headerOffset + paddedTop,
                width: right - left,
                height: paddedBottom - paddedTop,
                decoration: decoration,
              ),
            );
          }
        }

        collect(children, depth + 1);
      }
    }

    collect(activities, 0);

    if (capsules.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: ClipRect(
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
              offset: Offset(0, -offset),
              child: child,
            );
          },
          child: Stack(
            children: [
              for (final capsule in capsules)
                Positioned(
                  left: capsule.left,
                  top: capsule.top,
                  width: capsule.width,
                  height: capsule.height,
                  child: DecoratedBox(decoration: capsule.decoration),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shrinks [GanttTheme.groupCapsuleVerticalPadding] by depth so an outer
/// group's capsule always extends further than a nested group's — even
/// though both may share the exact same last-descendant row (e.g. when a
/// group's own last child is itself a group), their padded edges never land
/// on the same pixel. Strictly decreasing and always positive, so this holds
/// at any nesting depth, not just the common 2-level case.
double _verticalPaddingForDepth(GanttTheme theme, int depth) =>
    theme.groupCapsuleVerticalPadding / (depth + 1);

BoxDecoration _defaultCapsuleStyle(GanttTheme theme, int depth) =>
    BoxDecoration(
      border: Border.all(
        color: theme.treeGuideColor.withValues(alpha: 0.5),
        width: 1,
      ),
      borderRadius: BorderRadius.circular(depth == 0 ? 8 : 12),
      color:
          depth == 0 ? null : theme.defaultCellColor.withValues(alpha: 0.08),
    );

class _CapsuleSpec {
  final double left;
  final double top;
  final double width;
  final double height;
  final BoxDecoration decoration;

  const _CapsuleSpec({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.decoration,
  });
}
