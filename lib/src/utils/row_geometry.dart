import '../classes/activity.dart';
import '../classes/theme.dart';

/// The per-row top padding `ActivitiesGrid`/`ActivitiesList` apply before
/// each activity, shared here so anything computing row positions
/// independently of the widget tree (like dependency-arrow drawing) can't
/// drift from the actual layout.
/// The top padding before one activity's row, matching the layout
/// `ActivitiesGrid`/`ActivitiesList` produce.
///
/// Root-level rows ([nested] `== 0`) always get the wider
/// [GanttTheme.rowsGroupPadding] gap. Deeper rows get the same wide gap only
/// when [current] or [previousSibling] has children — i.e. right around a
/// group's capsule — so two group capsules (or a capsule and a plain row)
/// never end up touching or overlapping regardless of nesting depth; every
/// other row keeps the tighter [GanttTheme.rowPadding].
double rowTopPadding(
  GanttTheme theme,
  int nested, {
  GanttActivity? previousSibling,
  GanttActivity? current,
}) {
  final touchesGroup =
      (current?.children?.isNotEmpty ?? false) ||
      (previousSibling?.children?.isNotEmpty ?? false);
  return theme.rowPadding +
      (nested == 0 || touchesGroup ? theme.rowsGroupPadding : 0);
}

/// The vertical position of one activity's row, matching the layout
/// `ActivitiesGrid`/`ActivitiesList` produce.
class GanttRowGeometry {
  /// The row's top offset, in pixels, from the top of the (unscrolled)
  /// activities content — i.e. excluding the header.
  final double top;

  /// The row's height, in pixels (always [GanttTheme.cellHeight]).
  final double height;

  const GanttRowGeometry({required this.top, required this.height});

  /// The row's vertical center, in pixels.
  double get centerY => top + height / 2;
}

/// Computes [GanttRowGeometry] for every *visible* activity in [activities]
/// and their descendants, keyed by activity key. An activity for which
/// [isCollapsed] returns `true` still gets its own entry, but its children
/// are skipped entirely — they simply have no entry in the result, which is
/// what every consumer (bars, capsules, dependency arrows, markers, tree
/// guides) already treats as "not currently on screen."
Map<String, GanttRowGeometry> computeRowGeometry(
  List<GanttActivity> activities,
  GanttTheme theme, {
  bool Function(String key)? isCollapsed,
}) {
  final result = <String, GanttRowGeometry>{};
  var y = 0.0;

  void walk(List<GanttActivity> items, int nested) {
    for (var i = 0; i < items.length; i++) {
      final activity = items[i];
      y += rowTopPadding(
        theme,
        nested,
        previousSibling: i > 0 ? items[i - 1] : null,
        current: activity,
      );
      result[activity.key] = GanttRowGeometry(
        top: y,
        height: theme.cellHeight,
      );
      y += theme.cellHeight;
      final children = activity.children;
      if (children != null &&
          children.isNotEmpty &&
          !(isCollapsed?.call(activity.key) ?? false)) {
        walk(children, nested + 1);
      }
    }
  }

  walk(activities, 0);
  return result;
}
