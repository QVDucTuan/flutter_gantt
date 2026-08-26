import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/row_geometry.dart';
import 'below_header_clip.dart';
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
                : _defaultCapsuleStyle(theme, activity, depth);
        if (decoration != null) {
          double? top;
          double? bottom;
          // The barInset of whichever descendant currently defines [top]/
          // [bottom] — tracked so the capsule's own outward padding on that
          // edge can be capped to it below, instead of always using the
          // theme's full padding regardless of what's actually there to
          // absorb it.
          var topInset = 0.0;
          var bottomInset = 0.0;
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
            if (top == null || rowTop < top) {
              top = rowTop;
              topInset = barInset;
            }
            if (bottom == null || rowBottom > bottom) {
              bottom = rowBottom;
              bottomInset = barInset;
            }
          }
          if (top != null && bottom != null) {
            final horizontalPadding = _paddingForDepth(
              theme.groupCapsuleHorizontalPadding,
              depth,
            );
            final left =
                controller.xForDate(activity.start) - horizontalPadding;
            final right =
                controller.xForDate(activity.end) +
                controller.dayColumnWidth +
                horizontalPadding;
            final verticalPadding = _paddingForDepth(
              theme.groupCapsuleVerticalPadding,
              depth,
            );
            // Capped per edge to that edge's own row's inset — an ordinary
            // bar row's inset (barVerticalPadding, 10 by default) comfortably
            // covers the padding at any depth, so this is a no-op there; a
            // checklist row's inset is 0, so its edge gets no outward padding
            // at all instead of bleeding past its own row into whatever
            // follows (see rowsGroupPadding's doc — rows are flush by
            // default, with no gap of their own to absorb an overshoot).
            final topPadding = math.min(verticalPadding, topInset);
            final bottomPadding = math.min(verticalPadding, bottomInset);
            final paddedTop = top - topPadding;
            final paddedBottom = bottom + bottomPadding;
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

/// Shrinks a capsule padding value ([GanttTheme.groupCapsuleVerticalPadding]
/// or [GanttTheme.groupCapsuleHorizontalPadding]) by depth so an outer
/// group's capsule always extends further than a nested group's — even
/// though both may share the exact same last-descendant row (e.g. when a
/// group's own last child is itself a group), their padded edges never land
/// on the same pixel. Strictly decreasing and always positive, so this holds
/// at any nesting depth, not just the common 2-level case. Applied to both
/// axes identically (not just vertical) so the ratio between them — and so
/// how "even" the capsule's frame looks — stays constant at every depth,
/// not just depth 0.
double _paddingForDepth(double base, int depth) => base / (depth + 1);

BoxDecoration _defaultCapsuleStyle(
  GanttTheme theme,
  GanttActivity activity,
  int depth,
) {
  // Wash tinted with this activity's own bar color (the same one
  // GanttCell resolves), not an unrelated fixed color — so the capsule
  // reads as "this activity's own group," matching QV's own washes.
  final barColor =
      theme.colorResolver?.call(depth, activity.colorIndex, activity.color) ??
      activity.color ??
      theme.defaultCellColor;
  return BoxDecoration(
    border: Border.all(
      // Bolder than a 50%-alpha hairline would be — this border is what
      // makes the group visually readable as "one thing", so it needs to
      // stand out more than a background/grid line does.
      color: theme.treeGuideColor.withValues(alpha: 0.9),
      width: 1.5,
    ),
    borderRadius: BorderRadius.circular(depth == 0 ? 8 : 12),
    color: depth == 0 ? null : barColor.withValues(alpha: 0.12),
  );
}

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
