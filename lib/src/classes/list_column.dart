import 'package:flutter/widgets.dart';

import 'activity.dart';

/// A single column in a `GanttActivitiesTable`.
class GanttListColumn {
  /// The column's header label.
  final String header;

  /// A fixed width for this column. Leave unset to use [flex] instead.
  final double? width;

  /// A flex factor for this column, used whenever [width] is unset.
  /// Defaults to `1` if both are unset.
  final int? flex;

  /// The narrowest this column can be dragged to via `ActivitiesList`'s
  /// header resize handle — dragging a boundary stops right at this width
  /// instead of shrinking the column further. Only applies to a flex-based
  /// column (one with [width] unset); a fixed-[width] column isn't
  /// draggable at all. Defaults to 40.0.
  final double minWidth;

  /// Builds this column's cell content for a given activity.
  final Widget Function(BuildContext context, GanttActivity activity)
  cellBuilder;

  /// Returns a sortable value for a given activity, so tapping this
  /// column's header re-sorts sibling rows by it (hierarchy is preserved —
  /// only rows sharing the same parent are reordered relative to each
  /// other). `null` (the default) means this column can't be sorted by.
  final Comparable Function(GanttActivity activity)? sortValue;

  /// Creates a [GanttListColumn].
  const GanttListColumn({
    required this.header,
    required this.cellBuilder,
    this.width,
    this.flex,
    this.minWidth = 40.0,
    this.sortValue,
  });
}
