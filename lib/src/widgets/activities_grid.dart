import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../flutter_gantt.dart';
import '../utils/row_geometry.dart';

/// Displays the activities grid portion of the Gantt chart.
///
/// The grid shows activity rows with their durations and optional child activities
/// in a timeline view. It synchronizes scrolling with the [ActivitiesList] widget.
class ActivitiesGrid extends StatelessWidget {
  /// The list of [GanttActivity] items to display in the grid.
  ///
  /// This list can contain parent activities with nested child activities.
  final List<GanttActivity> activities;

  /// Optional [ScrollController] to synchronize scrolling with other widgets.
  ///
  /// Typically used with [LinkedScrollControllerGroup] to sync with the activity list.
  final ScrollController? controller;

  /// Whether to show the ISO week number row.
  ///
  /// If `true`, a row displaying ISO-8601 week numbers is shown
  /// between the month headers and the day cells.
  final bool showIsoWeek;

  /// Creates an [ActivitiesGrid] widget.
  ///
  /// [activities] must not be null and should contain at least one activity.
  /// [showIsoWeek] enables the ISO week-number row (default: `false`).
  const ActivitiesGrid({
    super.key,
    required this.activities,
    this.controller,
    this.showIsoWeek = false,
  });

  /// Recursively builds widgets for activities and their children.
  ///
  /// [activities] - The list of activities to build widgets for
  /// [theme] - The current [GanttTheme] for styling
  /// [nested] - The current nesting level (used for indentation)
  List<Widget> getItems(
    List<GanttActivity> activities,
    GanttTheme theme,
    GanttController controller, {
    int nested = 0,
  }) => List.generate(
    activities.length,
    (index) => Padding(
      padding: EdgeInsets.only(
        top: rowTopPadding(
          theme,
          nested,
          previousSibling: index > 0 ? activities[index - 1] : null,
          current: activities[index],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GanttActivityRow(activity: activities[index]),
          if (activities[index].children?.isNotEmpty == true &&
              !controller.isCollapsed(activities[index].key))
            ...getItems(
              activities[index].children!,
              theme,
              controller,
              nested: nested + 1,
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Consumer<GanttTheme>(
    builder: (context, theme, child) {
      final controller = context.watch<GanttController>();
      return Padding(
        padding: EdgeInsets.only(
          top: theme.headerHeight + (showIsoWeek ? 10 : 0),
        ),
        child: ListView(
          controller: this.controller,
          children: getItems(activities, theme, controller),
        ),
      );
    },
  );
}
