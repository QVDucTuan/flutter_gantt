import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../widgets/controller_extension.dart';

/// A single cell representing an activity's duration in the Gantt chart.
///
/// Each cell visually represents the duration of an activity in the timeline.
/// Supports hover effects, tap actions, and custom styling.
class GanttCell extends StatefulWidget {
  /// The [GanttActivity] this cell represents.
  final GanttActivity activity;

  /// Creates a [GanttCell] for the specified activity.
  ///
  /// [activity] must not be null.
  const GanttCell({super.key, required this.activity});

  @override
  State<GanttCell> createState() => _GanttCellState();
}

class _GanttCellState extends State<GanttCell> {
  /// Gets the cell color.
  ///
  /// If [GanttTheme.colorResolver] is set, it fully owns the result
  /// (including whether to honor the activity's own color). Otherwise falls
  /// back to the activity's color, then the theme's [GanttTheme.defaultCellColor].
  Color get color {
    final activity = widget.activity;
    final theme = context.watch<GanttTheme>();
    return theme.colorResolver?.call(
          activity.depth,
          activity.colorIndex,
          activity.color,
        ) ??
        activity.color ??
        theme.defaultCellColor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<GanttTheme>();
    final ctrl = context.watch<GanttActivityCtrl>();
    final progress = widget.activity.progress;
    // Left corners square off when the bar's start is scrolled off-screen
    // (it visually continues past the left edge); right corners the same
    // for the end, off-screen to the right. Both corners on a given side
    // round together — previously only topLeft/bottomRight were ever set,
    // leaving topRight/bottomLeft permanently square regardless of theme.
    final leftRadius =
        ctrl.cellsNotVisibleBefore
            ? Radius.zero
            : Radius.circular(theme.cellRounded);
    final rightRadius =
        ctrl.cellsNotVisibleAfter
            ? Radius.zero
            : Radius.circular(theme.cellRounded);
    final borderRadius = BorderRadius.only(
      topLeft: leftRadius,
      bottomLeft: leftRadius,
      topRight: rightRadius,
      bottomRight: rightRadius,
    );

    return InkWell(
      onTap: () => widget.activity.onCellTap?.call(widget.activity),
      hoverColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: color),
            if (progress != null)
              FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: progress,
                child: Container(color: theme.progressOverlayColor),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child:
                  widget.activity.titleWidget ??
                  Text(
                    widget.activity.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyle(
                      weight: FontWeight.w600,
                      color: theme.onBarTextColor(color),
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
