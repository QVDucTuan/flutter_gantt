import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/list_column.dart';
import '../classes/theme.dart';
import 'tree_indent.dart';

/// A flat, column-configurable table view of the same activity tree a
/// [Gantt] chart shows — an alternative presentation, not a layer on top of
/// it. A standalone widget alongside [Gantt], not nested inside it; your own
/// app decides when to show which.
///
/// Hierarchy is preserved (a child always renders immediately after its
/// parent) even when a sortable column is tapped — only sibling rows are
/// reordered relative to each other, matching how the same tree looks in
/// [Gantt]'s own activities list. Note: if [showTreeGuides] is also on, the
/// connector lines reflect each activity's position in the underlying
/// [GanttActivity.children] order, not the current sort — they may look
/// slightly inconsistent with a non-default sort applied.
class GanttActivitiesTable extends StatefulWidget {
  /// The activities to display, most-ancestor-first (children nest under
  /// their parent automatically via [GanttActivity.children]).
  final List<GanttActivity> activities;

  /// The columns to render, in order.
  final List<GanttListColumn> columns;

  /// The theme to use. Defaults to `GanttTheme()` if unset.
  final GanttTheme? theme;

  /// Optional [ScrollController] for the row list.
  final ScrollController? controller;

  /// Whether to draw tree connector guide lines (elbow/tee) ahead of the
  /// first column's content. See [GanttTreeIndent].
  final bool showTreeGuides;

  /// Creates a [GanttActivitiesTable].
  const GanttActivitiesTable({
    super.key,
    required this.activities,
    required this.columns,
    this.theme,
    this.controller,
    this.showTreeGuides = false,
  });

  @override
  State<GanttActivitiesTable> createState() => _GanttActivitiesTableState();
}

class _GanttActivitiesTableState extends State<GanttActivitiesTable> {
  GanttListColumn? _sortColumn;
  bool _sortAscending = true;

  void _onHeaderTap(GanttListColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  List<GanttActivity> _sortedFlatten(List<GanttActivity> activities) {
    final sortValue = _sortColumn?.sortValue;
    final items =
        sortValue == null
            ? activities
            : (List<GanttActivity>.from(activities)..sort((a, b) {
              final cmp = sortValue(a).compareTo(sortValue(b));
              return _sortAscending ? cmp : -cmp;
            }));
    final result = <GanttActivity>[];
    for (final activity in items) {
      result.add(activity);
      final children = activity.children;
      if (children != null && children.isNotEmpty) {
        result.addAll(_sortedFlatten(children));
      }
    }
    return result;
  }

  Widget _columnCell(GanttListColumn column, Widget child) =>
      column.width != null
          ? SizedBox(width: column.width, child: child)
          : Expanded(flex: column.flex ?? 1, child: child);

  Widget _buildHeaderRow(GanttTheme theme) => SizedBox(
    height: theme.headerHeight,
    child: Row(
      children: [
        for (final column in widget.columns)
          _columnCell(
            column,
            InkWell(
              onTap:
                  column.sortValue != null
                      ? () => _onHeaderTap(column)
                      : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        column.header,
                        style: theme.textStyle(weight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_sortColumn == column)
                      Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 14,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildDataRow(
    BuildContext context,
    GanttTheme theme,
    GanttActivity activity,
  ) => SizedBox(
    height: theme.cellHeight,
    child: Row(
      children: [
        for (var i = 0; i < widget.columns.length; i++)
          _columnCell(
            widget.columns[i],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child:
                  i == 0
                      ? Row(
                        children: [
                          GanttTreeIndent(
                            activity: activity,
                            showGuides: widget.showTreeGuides,
                          ),
                          Expanded(
                            child: widget.columns[i].cellBuilder(
                              context,
                              activity,
                            ),
                          ),
                        ],
                      )
                      : widget.columns[i].cellBuilder(context, activity),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? GanttTheme();
    final rows = _sortedFlatten(widget.activities);
    return Provider<GanttTheme>.value(
      value: theme,
      child: Column(
        children: [
          _buildHeaderRow(theme),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: widget.controller,
              itemCount: rows.length,
              itemBuilder:
                  (context, index) =>
                      _buildDataRow(context, theme, rows[index]),
            ),
          ),
        ],
      ),
    );
  }
}
