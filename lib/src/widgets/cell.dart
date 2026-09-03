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
    return theme.colorResolver?.call(activity) ??
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

    final bar = InkWell(
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
              child: Align(
                alignment: AlignmentDirectional.centerStart,
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
            ),
          ],
        ),
      ),
    );

    // Matches ChildrenPeekOverlay's own "qualifies" check — no point
    // reporting hover here if that overlay wouldn't show anything for it
    // anyway (no children, or the badge is disabled via a null
    // peekBadgeBuilder).
    if (theme.peekBadgeBuilder == null ||
        widget.activity.children?.isNotEmpty != true) {
      return bar;
    }

    // Doesn't render the peek badge itself — a bar this narrow is
    // width-constrained by its own ancestor SizedBox (sized exactly to its
    // date span, for correct resize-handle/tap-region geometry), so
    // anything painted past its edge via Positioned/Clip.none would be
    // visible but NOT hit-testable (Flutter's hit-testing rejects a
    // position outside a RenderBox's own resolved size before ever
    // checking overflowing children — a real gotcha, not a hypothetical
    // one: that's exactly why the badge used to be unclickable). Instead,
    // this only reports hover state on the controller; `ChildrenPeekOverlay`
    // (a sibling layer with genuinely wide bounds, like `MarkersOverlay`)
    // reads it and draws the actual badge at an absolute canvas position.
    return MouseRegion(
      onEnter: (_) => ctrl.controller.hoverActivity(widget.activity.key),
      onExit:
          (_) => ctrl.controller.scheduleUnhoverActivity(widget.activity.key),
      child: bar,
    );
  }
}
