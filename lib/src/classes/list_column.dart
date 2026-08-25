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
    this.sortValue,
  });
}
