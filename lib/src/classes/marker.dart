import 'package:flutter/material.dart';

import '../utils/datetime.dart';

/// A point-in-time marker pinned to a single [date] and anchored to a
/// specific activity's row via [activityKey], rather than occupying its
/// own row like a [GanttActivity] bar does.
///
/// Unlike a bar, a marker only needs one date and one row, so it renders
/// correctly in both fit mode and scroll mode (see
/// [GanttController.fixedDayWidth]) — if [date] falls outside the chart's
/// currently visible range, or [activityKey] doesn't resolve to a known
/// activity, it's simply not drawn.
class GanttMarker {
  /// Unique identifier for the marker.
  final String key;

  /// The date this marker is pinned to.
  late DateTime date;

  /// The [GanttActivity.key] of the row this marker is positioned against.
  final String activityKey;

  /// A custom icon widget. Defaults to the package's bundled flag-pin glyph
  /// (`assets/icons/ico_marker.svg`, tinted with [GanttTheme.todayBackgroundColor])
  /// if unset.
  final Widget? icon;

  /// Optional tooltip text.
  final String? tooltip;

  /// Callback when the marker is tapped.
  final VoidCallback? onTap;

  /// Creates a [GanttMarker] pinned to [date] and anchored to [activityKey].
  ///
  /// The [date] is normalized to UTC with time components set to zero.
  GanttMarker({
    required this.key,
    required DateTime date,
    required this.activityKey,
    this.icon,
    this.tooltip,
    this.onTap,
  }) {
    this.date = date.toDate;
  }
}
