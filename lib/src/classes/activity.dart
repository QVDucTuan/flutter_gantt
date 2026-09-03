import 'package:flutter/material.dart';

import '../utils/datetime.dart';

/// Sentinel distinguishing "field not passed to [GanttActivity.copyWith]"
/// from "explicitly passed `null`" for its nullable parameters.
const Object _unset = Object();

/// An action that can be performed on a Gantt activity.
class GanttActivityAction {
  /// The icon representing the action.
  final IconData icon;

  /// The callback when the action is triggered.
  final VoidCallback onTap;

  /// Optional tooltip text for the action.
  final String? tooltip;

  /// Creates an activity action with an icon, tap handler, and optional tooltip.
  const GanttActivityAction({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
}

/// Represents an activity in the Gantt chart.
///
/// Each activity has a start/end date, title, and optional styling properties.
/// Activities can be hierarchical with parent-child relationships.
class GanttActivity<T> {
  /// Unique identifier for the activity.
  late String key;

  /// The start date of the activity.
  late DateTime start;

  /// The end date of the activity.
  late DateTime end;

  /// The title text of the activity (mutually exclusive with [titleWidget]).
  final String? title;

  /// A custom widget for the activity title (mutually exclusive with [title]).
  final Widget? titleWidget;

  /// Alternative title for the list view (optional).
  final String? listTitle;

  /// Custom widget for the list view title (optional).
  final Widget? listTitleWidget;

  /// The tooltip message.
  final String? tooltip;

  /// An optional icon to display with the title.
  final Widget? iconTitle;

  /// Child activities that are hierarchically under this one.
  final List<GanttActivity>? children;

  /// Actions that can be performed on this activity.
  final List<GanttActivityAction>? actions;

  /// Callback when the activity cell is tapped.
  final Function(GanttActivity activity)? onCellTap;

  /// Builder function for custom single cell rendering.
  final Widget Function(DateTime cellDate)? cellBuilder;

  /// The color of the activity cell.
  final Color? color;

  /// The completion progress of the activity, from `0.0` to `1.0`.
  ///
  /// When set, [GanttCell] renders a progress-fill overlay covering this
  /// fraction of the bar (see [GanttTheme.progressOverlayColor]). `null`
  /// (the default) renders no overlay.
  final double? progress;

  /// An index into a consumer-supplied color palette.
  ///
  /// Only consulted by a [GanttTheme.colorResolver] a consumer supplies —
  /// this package has no built-in palette. To let the app pick each Task's
  /// actual color itself (e.g. randomly), set [color] instead — see
  /// [withColor].
  final int? colorIndex;

  /// The [key]s of activities this one depends on (predecessors).
  ///
  /// When set, a connector arrow is drawn from each predecessor to this
  /// activity — see `DependencyArrows`. Only rendered in scroll mode (see
  /// [GanttController.fixedDayWidth]).
  final List<String>? dependsOn;

  /// Whether to render a date-bound bar for this activity at all.
  ///
  /// Set to `false` to make an activity render as a plain row instead of a
  /// bar — e.g. a checklist-style "subitem" that has dates (for dependency
  /// arrows/group capsules) but isn't itself a scheduled span. Pair this
  /// with [titleWidget] to supply the row's content (a checkbox + name, for
  /// example) — see `example/lib/main.dart`'s `SubitemChecklistTitle` for a
  /// complete pattern. Structurally disables dragging/resizing, not just
  /// the visual — `GanttActivityRow` never mounts a drag gesture for it.
  final bool showCell;

  /// Builder function for custom cell rendering.
  final Widget Function(GanttActivity activity)? builder;

  /// A place to attach whatever business data this activity represents —
  /// status, priority, assignee, a link back to your own domain model,
  /// anything. The package never reads this itself; it only exists so your
  /// own [GanttListColumn.cellBuilder]s (or `builder`/`cellBuilder` above)
  /// can read it back via `activity.data`. A minimal example:
  ///
  /// ```dart
  /// typedef TaskMeta = ({TaskStatus status, User assignee});
  ///
  /// GanttActivity(
  ///   ...,
  ///   data: (status: TaskStatus.inProgress, assignee: someUser),
  /// )
  ///
  /// GanttListColumn(
  ///   header: 'Status',
  ///   cellBuilder: (context, activity) {
  ///     final meta = activity.data as TaskMeta?;
  ///     return meta == null ? const SizedBox.shrink() : StatusGlyph(meta.status);
  ///   },
  /// )
  /// ```
  final T? data;

  GanttActivity? _parent;

  /// The parent activity, if this is a child activity.
  GanttActivity? get parent => _parent;

  /// The nesting depth of this activity (`0` for a root activity).
  int get depth => parent == null ? 0 : parent!.depth + 1;

  /// Whether this activity is the last child among its parent's [children].
  ///
  /// Always `true` for a root activity (no [parent]).
  bool get isLastChild {
    final siblings = parent?.children;
    return siblings == null || identical(siblings.last, this);
  }

  /// One entry per ancestor depth (shallowest first): `true` means that
  /// ancestor still has siblings below it, so a plain connector rail should
  /// continue past this row at that depth; `false` means it was the last of
  /// its own siblings, so the rail should stop. Does not describe this
  /// activity's own branch point — see [isLastChild] for that.
  List<bool> get treeGuides {
    final guides = <bool>[];
    var p = parent;
    while (p != null) {
      guides.add(!p.isLastChild);
      p = p.parent;
    }
    return guides.reversed.toList();
  }

  /// The limit of the start date of the activity.
  late DateTime? limitStart;

  /// The limit of the end date of the activity.
  late DateTime? limitEnd;

  /// Creates a [GanttActivity] with the specified properties.
  ///
  /// Throws an [AssertionError] if:
  /// - Start date is after end date
  /// - Only one between [title] and [titleWidget] must be provided
  /// - Any segment dates fall outside the activity dates
  /// - Any child activity dates fall outside this activity's dates
  GanttActivity({
    required this.key,
    required DateTime start,
    required DateTime end,
    this.title,
    this.titleWidget,
    this.listTitle,
    this.listTitleWidget,
    this.tooltip,
    this.iconTitle,
    this.children,
    this.onCellTap,
    this.cellBuilder,
    this.color,
    this.progress,
    this.colorIndex,
    this.dependsOn,
    this.actions,
    this.showCell = true,
    this.builder,
    this.data,
    this.limitStart,
    this.limitEnd,
  }) : assert(
         start.toDate.isBeforeOrSame(end.toDate) &&
             ((title == null) != (titleWidget == null)) &&
             ((cellBuilder == null) || (builder == null)) &&
             ((listTitle == null) || (listTitleWidget == null)) &&
             (progress == null || (progress >= 0.0 && progress <= 1.0)),
       ) {
    this.start = start.toDate;
    this.end = end.toDate;
    if (children != null) {
      for (final child in children!) {
        assert(
          child.start.isDateBetween(this.start, this.end) &&
              child.end.isDateBetween(this.start, this.end),
        );
        child._parent = this;
      }
    }
  }

  /// Returns a copy of this activity with the given fields replaced.
  ///
  /// [children] and [data] are the two fields you'll reach for most: since
  /// both are `final`, editing a tree (adding/removing a child, marking an
  /// activity's `data` complete, etc.) means rebuilding the affected
  /// activity — and every ancestor up to whatever you hand to
  /// [GanttController.setActivities], since each one holds its own `final
  /// children` list. This only rebuilds the one activity you call it on.
  ///
  /// Every nullable field can be explicitly cleared by passing `null` — it
  /// isn't confused with "leave unchanged" (which is what omitting the
  /// parameter does), the same distinction `copyWith` methods generally
  /// make in Dart. [key]/[start]/[end] are non-nullable, so there's nothing
  /// to clear for those — omitting them just keeps the current value.
  ///
  /// ```dart
  /// // Append a new Subitem to a Subtask's children:
  /// final updatedSubtask = subtask.copyWith(
  ///   children: [...?subtask.children, newSubitem],
  /// );
  /// // ...then rebuild subtask's own parent the same way, up to the root,
  /// // and call controller.setActivities(newTopLevelList).
  /// ```
  GanttActivity<T> copyWith({
    String? key,
    DateTime? start,
    DateTime? end,
    Object? title = _unset,
    Object? titleWidget = _unset,
    Object? listTitle = _unset,
    Object? listTitleWidget = _unset,
    Object? tooltip = _unset,
    Object? iconTitle = _unset,
    Object? children = _unset,
    Object? onCellTap = _unset,
    Object? cellBuilder = _unset,
    Object? color = _unset,
    Object? progress = _unset,
    Object? colorIndex = _unset,
    Object? dependsOn = _unset,
    Object? actions = _unset,
    bool? showCell,
    Object? builder = _unset,
    Object? data = _unset,
    Object? limitStart = _unset,
    Object? limitEnd = _unset,
  }) => GanttActivity<T>(
    key: key ?? this.key,
    start: start ?? this.start,
    end: end ?? this.end,
    title: title == _unset ? this.title : title as String?,
    titleWidget:
        titleWidget == _unset ? this.titleWidget : titleWidget as Widget?,
    listTitle: listTitle == _unset ? this.listTitle : listTitle as String?,
    listTitleWidget:
        listTitleWidget == _unset
            ? this.listTitleWidget
            : listTitleWidget as Widget?,
    tooltip: tooltip == _unset ? this.tooltip : tooltip as String?,
    iconTitle: iconTitle == _unset ? this.iconTitle : iconTitle as Widget?,
    children:
        children == _unset ? this.children : children as List<GanttActivity>?,
    onCellTap:
        onCellTap == _unset
            ? this.onCellTap
            : onCellTap as Function(GanttActivity activity)?,
    cellBuilder:
        cellBuilder == _unset
            ? this.cellBuilder
            : cellBuilder as Widget Function(DateTime)?,
    color: color == _unset ? this.color : color as Color?,
    progress: progress == _unset ? this.progress : progress as double?,
    colorIndex: colorIndex == _unset ? this.colorIndex : colorIndex as int?,
    dependsOn:
        dependsOn == _unset ? this.dependsOn : dependsOn as List<String>?,
    actions:
        actions == _unset
            ? this.actions
            : actions as List<GanttActivityAction>?,
    showCell: showCell ?? this.showCell,
    builder:
        builder == _unset
            ? this.builder
            : builder as Widget Function(GanttActivity)?,
    data: data == _unset ? this.data : data as T?,
    limitStart:
        limitStart == _unset ? this.limitStart : limitStart as DateTime?,
    limitEnd: limitEnd == _unset ? this.limitEnd : limitEnd as DateTime?,
  );

  /// Returns a copy of this activity and every descendant with [color] set
  /// throughout, so a whole Task family shares one base color without
  /// hand-setting it node by node. If [GanttTheme.colorResolver] is set to
  /// `defaultGanttColorResolver`, it uses this color verbatim at this
  /// activity's own depth and lightens it further for each deeper
  /// descendant — so the app only has to decide *one* color per Task (e.g.
  /// at random) and the whole family still reads as that one color fading
  /// with depth.
  ///
  /// ```dart
  /// // App decides the color itself — e.g. randomly, one per Task:
  /// activities = [
  ///   for (final task in tasks) task.withColor(randomColor()),
  /// ];
  /// ```
  GanttActivity<T> withColor(Color color) => copyWith(
    color: color,
    children: children?.map((c) => c.withColor(color)).toList(),
  );

  /// The duration of the activity in days.
  int get daysDuration => end.diffInDays(start) + 1;

  @override
  String toString() => title ?? super.toString();

  /// Gets a flat list of this activity and all its descendants.
  List<GanttActivity> get plainList => [this, ...children?.plainList ?? []];

  bool validStartMoveToParent(int days) =>
      parent == null ||
      !parent!.showCell ||
      start.addDays(days).isAfterOrSame(parent!.start);

  bool validStartMoveToChildren(int days) =>
      (children?.isEmpty ?? true) == true ||
      start
          .addDays(days)
          .isBeforeOrSame(
            DateTimeEx.firstDateFromList(
              children!.map((e) => e.start).toList(),
            ),
          );

  bool validEndMoveToParent(int days) =>
      parent == null ||
      !parent!.showCell ||
      end.addDays(days).isBeforeOrSame(parent!.end);

  bool validEndMoveToChildren(int days) =>
      (children?.isEmpty ?? true) == true ||
      end
          .addDays(days)
          .isAfterOrSame(
            DateTimeEx.lastDateFromList(children!.map((e) => e.end).toList()),
          );

  bool validMoveToParent(int days) =>
      validStartMoveToParent(days) && validEndMoveToParent(days);

  bool validStartMove(int days) =>
      validStartMoveToParent(days) &&
      validStartMoveToChildren(days) &&
      (limitStart == null || start.addDays(days).isAfterOrSame(limitStart!));

  bool validEndMove(int days) =>
      validEndMoveToParent(days) &&
      validEndMoveToChildren(days) &&
      (limitEnd == null || end.addDays(days).isBeforeOrSame(limitEnd!));

  bool validMove(int days) => validStartMove(days) && validEndMove(days);

  /// Same as [validStartMove], minus the [validStartMoveToChildren] check —
  /// the resize-equivalent of [validMoveToParent], for a consumer that
  /// handles reconciling children with the new range itself (e.g. clamping
  /// a Subitem's date to stay inside its resized Subtask — see
  /// [GanttController.allowParentIndependentDateMovement]) instead of
  /// having the resize simply refuse to shrink past one.
  bool validStartMoveIgnoringChildren(int days) =>
      validStartMoveToParent(days) &&
      (limitStart == null || start.addDays(days).isAfterOrSame(limitStart!));

  /// Same as [validEndMove], minus the [validEndMoveToChildren] check — see
  /// [validStartMoveIgnoringChildren].
  bool validEndMoveIgnoringChildren(int days) =>
      validEndMoveToParent(days) &&
      (limitEnd == null || end.addDays(days).isBeforeOrSame(limitEnd!));
}

/// Extension methods for working with lists of [GanttActivity].
extension GanttActivityListExtension on List<GanttActivity> {
  /// Gets a flat list of all activities and their descendants.
  List<GanttActivity> get plainList {
    final as = <GanttActivity>[];
    for (var a in this) {
      as.addAll(a.plainList);
    }
    return as;
  }

  /// Finds an activity by its key in the flattened list.
  GanttActivity? getFromKey(String key) {
    final i = plainList.indexWhere((e) => e.key == key);
    return i < 0 ? null : plainList[i];
  }
}
