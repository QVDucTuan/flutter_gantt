import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/row_geometry.dart';
import 'below_header_clip.dart';
import 'controller.dart';
import 'controller_extension.dart';

/// Draws the "peek children" badge for whichever bar is currently hovered
/// (see [GanttController.hoveredActivityKey]) and too narrow to show its
/// children's own content (see [GanttTheme.childrenPeekWidthThreshold]).
///
/// [GanttCell] only *reports* hover on the controller — it can't safely
/// paint the badge itself, since its own render size is tightly bound to
/// its bar's date span (needed for correct resize-handle/tap-region
/// geometry), and content painted past that boundary isn't hit-testable
/// even with `Clip.none` (Flutter's hit-testing rejects a position outside
/// a RenderBox's own resolved size before it ever checks overflowing
/// children). This is a sibling layer instead — like `MarkersOverlay` —
/// with genuinely wide bounds, so the badge is positioned at an absolute
/// canvas coordinate and stays properly clickable however far it sits past
/// its bar's own edge.
///
/// Meant to be mounted by [Gantt] automatically, alongside
/// `GanttGroupCapsules`/`MarkersOverlay`/etc. Renders nothing when no
/// qualifying activity is hovered.
class ChildrenPeekOverlay extends StatelessWidget {
  /// The activities to look up the hovered key against.
  final List<GanttActivity> activities;

  /// The activities grid's own vertical [ScrollController] — this overlay
  /// is a sibling layer, not inside the grid's scrolling list, so this
  /// keeps the badge visually attached to its row while it scrolls.
  final ScrollController verticalScrollController;

  /// Whether the ISO week number row is shown (affects the header height
  /// this layer must be offset by, matching `ActivitiesGrid`).
  final bool showIsoWeek;

  /// Creates a [ChildrenPeekOverlay] for the given [activities].
  const ChildrenPeekOverlay({
    super.key,
    required this.activities,
    required this.verticalScrollController,
    this.showIsoWeek = false,
  });

  static const double _iconSize = 22.0;
  // The gap kept between the bar's own edge and the peek icon — close
  // enough to still read as "belonging" to this bar, without sitting on
  // top of it.
  static const double _iconGap = 4.0;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<GanttController>();
    final theme = context.watch<GanttTheme>();
    final hoveredKey = controller.hoveredActivityKey;
    final activity =
        hoveredKey == null ? null : activities.getFromKey(hoveredKey);
    final qualifies =
        activity != null &&
        theme.peekBadgeBuilder != null &&
        (activity.children?.isNotEmpty ?? false) &&
        controller.dayColumnWidth * controller.getCellDays(activity) <
            theme.childrenPeekWidthThreshold;

    if (!qualifies) return const SizedBox.shrink();

    final geometry = computeRowGeometry(
      activities,
      theme,
      isCollapsed: controller.isCollapsed,
    );
    final rowGeometry = geometry[activity.key];
    if (rowGeometry == null) return const SizedBox.shrink();

    final headerOffset = headerOffsetFor(theme, showIsoWeek);
    final x =
        controller.xForDate(activity.end) +
        controller.dayColumnWidth +
        _iconGap;
    final y = headerOffset + rowGeometry.centerY;

    return BelowHeaderClip(
      top: headerOffset,
      child: ListenableBuilder(
        listenable: verticalScrollController,
        builder: (context, child) {
          // Read via `positions` (plural), not `offset`/`position` — those
          // assert exactly one attached view, which doesn't hold for the
          // one frame where the grid's ListView is mid-remount.
          final positions = verticalScrollController.positions;
          final offset = positions.length == 1 ? positions.single.pixels : 0.0;
          return Transform.translate(offset: Offset(0, -offset), child: child);
        },
        child: Stack(
          children: [
            Positioned(
              left: x,
              top: y - _iconSize / 2,
              child: _PeekBadge(activity: activity, controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeekBadge extends StatelessWidget {
  const _PeekBadge({required this.activity, required this.controller});

  final GanttActivity activity;
  final GanttController controller;

  @override
  Widget build(BuildContext context) => MouseRegion(
    // Re-marks the same key as hovered — keeps the badge from disappearing
    // the instant the pointer leaves the (narrower) bar to reach it, since
    // that would otherwise race scheduleUnhoverActivity's own delayed clear.
    onEnter: (_) => controller.hoverActivity(activity.key),
    onExit: (_) => controller.scheduleUnhoverActivity(activity.key),
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTapDown:
          (details) => controller.notifyPeekChildrenTap(
            activity,
            details.globalPosition,
          ),
      child: SizedBox(
        width: ChildrenPeekOverlay._iconSize,
        height: ChildrenPeekOverlay._iconSize,
        // Always non-null here — the badge is only ever built when
        // ChildrenPeekOverlay's own `qualifies` check already confirmed
        // theme.peekBadgeBuilder isn't null.
        child: context.watch<GanttTheme>().peekBadgeBuilder!(context, activity),
      ),
    ),
  );
}
