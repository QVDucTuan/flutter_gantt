import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/datetime.dart';
import '../utils/row_geometry.dart';
import 'below_header_clip.dart';
import 'controller.dart';
import 'controller_extension.dart';

/// Renders every [GanttController.markers], positioned at its anchor row's
/// vertical center and its own date's horizontal offset.
///
/// Unlike `DependencyArrows`/`GanttGroupCapsules`, this works in both fit
/// mode and scroll mode — a marker only needs one row and one date, not
/// stable coordinates across every row at once. A marker whose date falls
/// outside the chart's currently visible range, or whose `activityKey`
/// doesn't resolve to a known activity, is simply skipped.
class MarkersOverlay extends StatelessWidget {
  /// The activities markers may anchor to.
  final List<GanttActivity> activities;

  /// The activities grid's own vertical [ScrollController] — markers are
  /// drawn as a sibling layer, not inside the grid's scrolling list, so
  /// this keeps them visually attached to their row while it scrolls.
  final ScrollController verticalScrollController;

  /// Whether the ISO week number row is shown (affects the header height
  /// markers must be offset by, matching `ActivitiesGrid`).
  final bool showIsoWeek;

  /// Creates a [MarkersOverlay] for the given [activities].
  const MarkersOverlay({
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
    final headerOffset = headerOffsetFor(theme, showIsoWeek);

    // Matches the bundled SVG's own native size (see
    // assets/icons/ico_marker.svg's width/height/viewBox) instead of
    // stretching it to an arbitrary one.
    const glyphSize = 18.0;
    final glyphs = <Widget>[];
    for (final marker in controller.markers) {
      if (!marker.date.isDateBetween(
        controller.startDate,
        controller.endDate,
      )) {
        continue;
      }
      final activity = all.getFromKey(marker.activityKey);
      if (activity == null) continue;
      final rowGeometry = geometry[activity.key];
      if (rowGeometry == null) continue;

      final x = controller.xForDate(marker.date);
      final y = headerOffset + rowGeometry.centerY;

      glyphs.add(
        Positioned(
          left: x - glyphSize / 2,
          top: y - glyphSize / 2,
          width: glyphSize,
          height: glyphSize,
          child: Tooltip(
            message: marker.tooltip ?? '',
            child: GestureDetector(
              onTap: marker.onTap,
              child: marker.icon ?? _defaultMarkerIcon(glyphSize),
            ),
          ),
        ),
      );
    }

    if (glyphs.isEmpty) return const SizedBox.shrink();

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
        child: Stack(children: glyphs),
      ),
    );
  }
}

// Bundled with the package itself (assets/icons/ico_marker.svg), so the
// packages/flutter_gantt/ prefix is required for SvgPicture.asset to
// resolve it from a consuming app — same as the depth icons.
const String _defaultMarkerIconAsset =
    'packages/flutter_gantt/assets/icons/ico_marker.svg';

// No colorFilter — renders with the SVG's own authored color (its `stroke`
// value) as-is, rather than tinting it to match the theme.
Widget _defaultMarkerIcon(double size) =>
    SvgPicture.asset(_defaultMarkerIconAsset, width: size, height: size);
