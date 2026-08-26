import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'activity.dart';

/// Resolves a display [Color] for an activity from its nesting [depth],
/// optional `colorIndex`, and any `explicitColor` the activity set via
/// `GanttActivity.color`.
///
/// When [GanttTheme.colorResolver] is set (it is, by default — see
/// [defaultGanttColorResolver]), it fully owns color computation — the
/// resolver decides whether/how to honor `explicitColor` itself (for
/// example, using it verbatim at depth 0 but lightening it at deeper
/// levels). Set [GanttTheme.colorResolver] to `null` to fall back instead to
/// an activity's own color, or [GanttTheme.defaultCellColor] if it has none.
typedef GanttColorResolver =
    Color Function(int depth, int? colorIndex, Color? explicitColor);

/// QV Agent Hub's own per-depth saturation/lightness table (see
/// `04-domain-logic.md`'s `GANTT_BAR_TONE`), ported verbatim — depth 1
/// (Subtask) is deliberately a touch *darker* than depth 0 (Task) in QV's
/// own design, not lighter, since a Subtask reads as its own stack's
/// "header"; depth 2 (Subitem) is the lightest of the three.
const List<({double s, double l})> _ganttBarTones = [
  (s: 0.62, l: 0.64), // depth 0 — Task
  (s: 0.56, l: 0.62), // depth 1 — Subtask
  (s: 0.58, l: 0.78), // depth 2 — Subitem
];

/// The hue QV Agent Hub's own `colorIndex` 0 preset resolves to (their
/// `hueForIndex`, evaluated at index 0). This package simplifies their
/// 100-hue rotating palette (one hue per Task) down to this single hue
/// family for activities with no explicit color — pass a `color` on the
/// Task itself (see [GanttActivity.withColor]) when the app wants to decide
/// each Task's color itself instead.
const double _ganttBarHue = 95;

/// The package's built-in default [GanttColorResolver]: QV Agent Hub's own
/// tone table when an activity has no explicit color, or QV's own
/// explicit-color lightening formula when it does — see `04-domain-logic.md`'s
/// `ganttBarColors` (this is that function, minus its 100-hue rotation; see
/// [_ganttBarHue]).
Color defaultGanttColorResolver(
  int depth,
  int? colorIndex,
  Color? explicitColor,
) {
  final clampedDepth = depth.clamp(0, _ganttBarTones.length - 1);
  if (explicitColor == null) {
    final tone = _ganttBarTones[clampedDepth];
    return HSLColor.fromAHSL(1, _ganttBarHue, tone.s, tone.l).toColor();
  }
  if (depth <= 0) return explicitColor;
  // A Subitem must always read visually lighter than its Subtask even when
  // the user picked an arbitrary custom hex — QV's own formula for that.
  final hsl = HSLColor.fromColor(explicitColor);
  final subLightness = (hsl.lightness + 0.06).clamp(0.48, 0.72);
  final itemLightness = (hsl.lightness + 0.22).clamp(subLightness + 0.12, 0.84);
  final fillLightness = depth == 1 ? subLightness : itemLightness;
  final fillSaturation = math.max(
    0.22,
    hsl.saturation * (depth == 1 ? 0.85 : 0.72),
  );
  return HSLColor.fromAHSL(
    1,
    hsl.hue,
    fillSaturation,
    fillLightness,
  ).toColor();
}

/// Resolves the visual style of the background capsule wrapping an activity
/// with children and all its descendants (see `GanttGroupCapsules`).
///
/// Returning `null` for a given [activity] skips drawing a capsule for it.
/// When [GanttTheme.groupCapsuleStyle] itself is `null`, a sensible built-in
/// style is used instead — this typedef is only for overriding it.
typedef GanttGroupCapsuleStyle =
    BoxDecoration? Function(GanttActivity activity, int depth);

/// Resolves a small leading icon for an activities-list row from its
/// nesting [depth] — shown right after the expand/collapse chevron (see
/// `ActivitiesList`). Return `null` for no icon at that depth.
typedef GanttDepthIconBuilder = Widget? Function(int depth);

/// The SVG assets backing [defaultGanttDepthIcon], one per nesting level —
/// bundled with the package itself (`assets/icons/task-level-*.svg`), so
/// the `packages/flutter_gantt/` prefix is required for `SvgPicture.asset`
/// to resolve them from a consuming app.
const List<String> _defaultDepthIconAssets = [
  'packages/flutter_gantt/assets/icons/task-level-0.svg',
  'packages/flutter_gantt/assets/icons/task-level-1.svg',
  'packages/flutter_gantt/assets/icons/task-level-2.svg',
];

/// The package's built-in default [GanttDepthIconBuilder]: one bundled SVG
/// per nesting level, so each level reads as visually distinct at a glance.
/// Levels deeper than the bundled set reuse the last (deepest) icon.
Widget? defaultGanttDepthIcon(int depth) {
  final asset =
      _defaultDepthIconAssets[depth.clamp(
        0,
        _defaultDepthIconAssets.length - 1,
      )];
  return SvgPicture.asset(asset, width: 12, height: 12);
}

/// A customizable theme for Gantt chart widgets.
///
/// Provides styling options for various elements of the Gantt chart,
/// including colors, dimensions, and spacing.
class GanttTheme {
  /// The background color of the Gantt chart.
  /// Defaults to [Color(0xFFFCFCFC)].
  final Color backgroundColor;

  /// The color used to highlight holiday dates.
  /// Defaults to [Color(0xFFFFF1E4)].
  final Color holidayColor;

  /// The color used to highlight weekend dates.
  /// Defaults to [Color(0xFFF8F8F8)] (a faint tint, not a hard grey block).
  final Color weekendColor;

  /// The background color for today's date cell.
  /// Defaults to [Color(0xFF0D90D9)].
  final Color todayBackgroundColor;

  /// The text color for today's date cell.
  /// Defaults to [Colors.white].
  final Color todayTextColor;

  /// The default color for activity cells.
  /// Defaults to [Color(0xFF008ECB)].
  final Color defaultCellColor;

  /// The color of the progress-fill overlay drawn over [GanttActivity.progress].
  /// Defaults to [Colors.black26].
  final Color progressOverlayColor;

  /// A hook to resolve an activity's color from its depth/index. Defaults to
  /// [defaultGanttColorResolver] (a single hue per activity family, lightened
  /// by depth); set to `null` to fall back instead to each activity's own
  /// color (or [defaultCellColor] if it has none), untouched. See
  /// [GanttColorResolver].
  final GanttColorResolver? colorResolver;

  /// The color of the vertical line marking today, drawn through the chart
  /// body. Defaults to [Color(0xFF0D90D9)]; set to `null` to disable the
  /// line entirely.
  final Color? todayLineColor;

  /// The width of the today line, in pixels.
  /// Defaults to 1.5.
  final double todayLineWidth;

  /// The color of tree connector guide lines (see [GanttActivity.treeGuides]).
  /// Defaults to [Color(0xFFCCD0DE)].
  final Color treeGuideColor;

  /// The color of the structural divider lines around and inside the chart:
  /// the outer frame border, the line between the activities-list and chart
  /// panes, and the line under the activities-list header row.
  /// Defaults to [Color(0xFFCCD0DE)] (the same tone as [treeGuideColor]).
  final Color dividerColor;

  /// Resolves the small leading icon shown after each activities-list row's
  /// expand/collapse chevron. Defaults to [defaultGanttDepthIcon]; set to
  /// `null` to show no depth icon at all.
  final GanttDepthIconBuilder? depthIconBuilder;

  /// The horizontal space reserved per nesting depth in the activities list,
  /// in pixels — used both for plain indentation and, when connector guides
  /// are shown, their spacing.
  /// Defaults to 14.0.
  final double treeIndentWidth;

  /// The color of dependency connector arrows (see [GanttActivity.dependsOn]).
  /// Defaults to [Color(0xFF97A0AF)].
  final Color dependencyArrowColor;

  /// The stroke width of dependency connector arrows, in pixels.
  /// Defaults to 1.25.
  final double dependencyArrowWidth;

  /// The background tint for an activities-list row while the pointer
  /// hovers over it. Only shown in the list pane, not the chart pane.
  /// Defaults to grey at 5% opacity.
  final Color hoverRowColor;

  /// The background tint for the currently-selected row (see
  /// [GanttController.selectedActivityKey]), shown across the full row
  /// width in both the activities list and the chart pane, so which row is
  /// selected reads clearly on either side.
  /// Defaults to grey at 10% opacity.
  final Color selectedRowColor;

  /// An optional hook to style the background capsule wrapping an activity
  /// with children and its descendants. `null` (the default) uses a
  /// built-in style. See [GanttGroupCapsuleStyle].
  final GanttGroupCapsuleStyle? groupCapsuleStyle;

  /// The horizontal padding, in pixels, between a group capsule's edge and
  /// the date span it wraps.
  /// Defaults to 6.0.
  final double groupCapsuleHorizontalPadding;

  /// The vertical padding, in pixels, between a group capsule's top/bottom
  /// edge and the rows it wraps — halved at each deeper nesting level (see
  /// `GanttGroupCapsules`), so this is the depth-0 value.
  /// Defaults to 4.0.
  final double groupCapsuleVerticalPadding;

  /// Formats a date for the floating tooltip shown while dragging a bar in
  /// [GanttInteractionMode.selectableDrag]. `null` (the default) uses a
  /// locale-aware built-in format.
  final String Function(DateTime)? dragTooltipDateFormat;

  /// The font family used for all text the chart itself renders (bar
  /// titles, row names, date/month labels — not text supplied by a
  /// consumer via [GanttActivity.titleWidget]/`builder`/`cellBuilder`).
  /// Defaults to `'Montserrat'`. If that font isn't loaded/bundled by the
  /// host app, text simply falls back to the platform default — setting
  /// this name alone never throws.
  final String? fontFamily;

  /// The base font size, in logical pixels, for the chart's own text.
  /// Defaults to 12.0.
  final double fontSize;

  /// The default color for the chart's own text (row names, day/month
  /// labels, table headers, etc.) — anywhere [textStyle] is used without an
  /// explicit [color]. Defaults to [Color(0xFF324F6A)].
  final Color textColor;

  /// Builds a [TextStyle] using [fontFamily] and this theme's [fontSize]
  /// (or [size] to override it), for the chart's own internal text.
  /// Defaults to [textColor] when [color] isn't given.
  TextStyle textStyle({double? size, FontWeight? weight, Color? color}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size ?? fontSize,
        fontWeight: weight,
        color: color ?? textColor,
      );

  /// The text color used on top of a bar.
  /// Defaults to [Color(0xFF324F6A)].
  final Color barTextColor;

  /// The color for a label painted on top of a bar filled with [barColor].
  /// Always [barTextColor] by default — every piece of text the chart
  /// renders uses the same one color, regardless of the bar underneath it.
  /// Override this method (e.g. via a `GanttTheme` subclass, or by not
  /// calling it and styling `GanttCell`'s text yourself) if you need
  /// automatic light/dark contrast switching instead.
  Color onBarTextColor(Color barColor) => barTextColor;

  /// The height of each activity row's slot in pixels — reserved space in
  /// both panes, not the bar's own rendered height (see
  /// [barVerticalPadding] for that).
  /// Defaults to 44.0.
  final double cellHeight;

  /// The vertical padding, in pixels, between a bar's top/bottom edge and
  /// its row slot ([cellHeight]) — so the row can be taller than the bar
  /// itself. Applied on both edges, so the bar's own rendered height is
  /// `cellHeight - barVerticalPadding * 2`. Doesn't affect checklist rows
  /// (see `GanttActivity.showCell`), which already size to the row slot via
  /// their own layout.
  /// Defaults to 8.0.
  final double barVerticalPadding;

  /// The vertical padding between rows.
  /// Defaults to 0.0 (rows sit flush against each other); see
  /// [rowsGroupPadding] for the wider gap still kept around a group's own
  /// capsule.
  final double rowPadding;

  /// The vertical padding between groups of rows.
  /// Defaults to 16.0.
  final double rowsGroupPadding;

  /// The height of the header section.
  /// Defaults to 48.0.
  final double headerHeight;

  /// The minimum width of a day column in pixels.
  /// Defaults to 30.0.
  final double dayMinWidth;

  /// The border radius for activity cells, in pixels.
  /// Defaults to 8.0 (a slight rounding).
  final double cellRounded;

  /// The rendered bar-width threshold, in pixels, below which an activity
  /// with children is considered "too narrow" — its checklist children
  /// (see `GanttActivity.showCell`) stop rendering their normal content in
  /// the chart pane (they'd otherwise render at full size regardless of how
  /// short the parent's own date span is, visually spilling out past its
  /// group capsule), and its bar shows a small hover icon instead (see
  /// `Gantt.onPeekChildrenTap`) — tapping it is meant to reveal the same
  /// content some other way (e.g. a popup), since it's still there, just
  /// not shown inline. The activities list pane is unaffected either way —
  /// it was never date-width-bound to begin with.
  /// Defaults to 90.0.
  final double childrenPeekWidthThreshold;

  // Dimension defaults below match QV Agent Hub's own Gantt constants (see
  // doc/timeline-flutter-port/04-domain-logic.md's `ROW_H`/`AXIS_H`/
  // `TREE_INDENT`) — cellHeight/headerHeight/treeIndentWidth are QV's exact
  // pixel values, not this package's original generic defaults.
  static const double _defaultCellHeight = 48.0;
  static const double _defaultBarVerticalPadding = 10.0;
  static const double _defaultRowPadding = 0.0;
  // 0 so every row sits flush against the next, including across a group's
  // own boundary — deliberately chosen over the 6.0 that would keep
  // sibling group capsules (e.g. two Subtasks under the same Task) from
  // ever touching: their capsules now overlap by a few px right at the
  // shared edge (groupCapsuleVerticalPadding/(depth+1) on each side), a
  // known, accepted tradeoff for fully flush rows.
  static const double _defaultRowsGroupPadding = 0.0;
  static const double _defaultHeaderHeight = 48.0;
  static const double _defaultDayMinWidth = 30.0;
  static const double _defaultTodayLineWidth = 1.5;
  static const double _defaultTreeIndentWidth = 14.0;
  static const double _defaultDependencyArrowWidth = 1.25;
  static const double _defaultGroupCapsuleHorizontalPadding = 6.0;
  static const double _defaultGroupCapsuleVerticalPadding = 4.0;
  static const String _defaultFontFamily = 'Montserrat'; 
  static const double _defaultFontSize = 12.0;
  static const double _defaultCellRounded = 8.0;
  static const double _defaultChildrenPeekWidthThreshold = 90.0;

  // Color defaults below match QV Agent Hub's own design tokens (see
  // doc/timeline-flutter-port/10-design-tokens-and-shared-ui.md and, for
  // dependencyArrowColor, 05-gantt-board-ui.md's `#97a0af` spec value) —
  // this package's default look is intentionally QV-branded, not a neutral
  // Material default; override any of these per-instance as needed.
  static const Color _defaultBackgroundColor = Color(0xFFFCFCFC);
  static const Color _defaultHolidayColor = Color(0xFFFFF1E4);
  static const Color _defaultWeekendColor = Color(0xFFF8F8F8);
  static const Color _defaultTodayBackgroundColor = Color(0xFF0D90D9);
  static const Color _defaultCellColor = Color(0xFF008ECB);
  static const Color _defaultTodayLineColor = Color(0xFF0D90D9);
  static const Color _defaultTreeGuideColor = Color(0xFFCCD0DE);
  static const Color _defaultDividerColor = Color(0xFFCCD0DE);
  static const Color _defaultDependencyArrowColor = Color(0xFF97A0AF);
  static const Color _defaultTextColor = Color(0xFF324F6A);
  // Grey at 5%/10% opacity respectively (0x0D/0x1A alpha over Material
  // grey 500, 0x9E9E9E) — not tinted to any other theme color, per an
  // explicit request to make both neutral grey instead.
  static const Color _defaultHoverRowColor = Color(0x0D9E9E9E);
  static const Color _defaultSelectedRowColor = Color(0x1A9E9E9E);

  /// Creates a [GanttTheme] with customizable properties.
  const GanttTheme({
    this.backgroundColor = _defaultBackgroundColor,
    this.holidayColor = _defaultHolidayColor,
    this.weekendColor = _defaultWeekendColor,
    this.todayBackgroundColor = _defaultTodayBackgroundColor,
    this.todayTextColor = Colors.white,
    this.defaultCellColor = _defaultCellColor,
    this.progressOverlayColor = Colors.black26,
    this.colorResolver = defaultGanttColorResolver,
    this.todayLineColor = _defaultTodayLineColor,
    this.todayLineWidth = _defaultTodayLineWidth,
    this.treeGuideColor = _defaultTreeGuideColor,
    this.treeIndentWidth = _defaultTreeIndentWidth,
    this.dividerColor = _defaultDividerColor,
    this.depthIconBuilder = defaultGanttDepthIcon,
    this.dependencyArrowColor = _defaultDependencyArrowColor,
    this.dependencyArrowWidth = _defaultDependencyArrowWidth,
    this.hoverRowColor = _defaultHoverRowColor,
    this.selectedRowColor = _defaultSelectedRowColor,
    this.textColor = _defaultTextColor,
    this.barTextColor = _defaultTextColor,
    this.groupCapsuleStyle,
    this.groupCapsuleHorizontalPadding = _defaultGroupCapsuleHorizontalPadding,
    this.groupCapsuleVerticalPadding = _defaultGroupCapsuleVerticalPadding,
    this.dragTooltipDateFormat,
    this.fontFamily = _defaultFontFamily,
    this.fontSize = _defaultFontSize,
    this.cellHeight = _defaultCellHeight,
    this.barVerticalPadding = _defaultBarVerticalPadding,
    this.rowPadding = _defaultRowPadding,
    this.rowsGroupPadding = _defaultRowsGroupPadding,
    this.headerHeight = _defaultHeaderHeight,
    this.dayMinWidth = _defaultDayMinWidth,
    this.cellRounded = _defaultCellRounded,
    this.childrenPeekWidthThreshold = _defaultChildrenPeekWidthThreshold,
  });

  /// Creates a [GanttTheme] using QV Agent Hub's own colors by default —
  /// the same defaults the plain constructor uses. [context] is accepted so
  /// a consumer can still opt individual fields back into the ambient
  /// Material [ColorScheme] (e.g. `backgroundColor:
  /// Theme.of(context).colorScheme.surface`) or dark-mode-aware values,
  /// without this factory forcing that choice for every field.
  ///
  /// You can override individual styling by providing specific color values.
  factory GanttTheme.of(
    // ignore: avoid_unused_constructor_parameters
    BuildContext context, {
    Color? backgroundColor,
    Color? holidayColor,
    Color? weekendColor,
    Color? todayBackgroundColor,
    Color? todayTextColor,
    Color? defaultCellColor,
    Color? progressOverlayColor,
    GanttColorResolver? colorResolver = defaultGanttColorResolver,
    Color? todayLineColor,
    double todayLineWidth = _defaultTodayLineWidth,
    Color? treeGuideColor,
    Color? dividerColor,
    GanttDepthIconBuilder? depthIconBuilder = defaultGanttDepthIcon,
    double treeIndentWidth = _defaultTreeIndentWidth,
    Color? dependencyArrowColor,
    double dependencyArrowWidth = _defaultDependencyArrowWidth,
    Color? hoverRowColor,
    Color? selectedRowColor,
    Color? textColor,
    Color? barTextColor,
    GanttGroupCapsuleStyle? groupCapsuleStyle,
    double groupCapsuleHorizontalPadding =
        _defaultGroupCapsuleHorizontalPadding,
    double groupCapsuleVerticalPadding = _defaultGroupCapsuleVerticalPadding,
    String Function(DateTime)? dragTooltipDateFormat,
    String? fontFamily = _defaultFontFamily,
    double fontSize = _defaultFontSize,
    double cellHeight = _defaultCellHeight,
    double barVerticalPadding = _defaultBarVerticalPadding,
    double rowPadding = _defaultRowPadding,
    double rowsGroupPadding = _defaultRowsGroupPadding,
    double headerHeight = _defaultHeaderHeight,
    double dayMinWidth = _defaultDayMinWidth,
    double cellRounded = _defaultCellRounded,
    double childrenPeekWidthThreshold = _defaultChildrenPeekWidthThreshold,
  }) => GanttTheme(
    backgroundColor: backgroundColor ?? _defaultBackgroundColor,
    defaultCellColor: defaultCellColor ?? _defaultCellColor,
    weekendColor: weekendColor ?? _defaultWeekendColor,
    holidayColor: holidayColor ?? _defaultHolidayColor,
    todayBackgroundColor: todayBackgroundColor ?? _defaultTodayBackgroundColor,
    todayTextColor: todayTextColor ?? Colors.white,
    progressOverlayColor: progressOverlayColor ?? Colors.black26,
    colorResolver: colorResolver,
    todayLineColor: todayLineColor ?? _defaultTodayLineColor,
    todayLineWidth: todayLineWidth,
    treeGuideColor: treeGuideColor ?? _defaultTreeGuideColor,
    dividerColor: dividerColor ?? _defaultDividerColor,
    depthIconBuilder: depthIconBuilder,
    treeIndentWidth: treeIndentWidth,
    dependencyArrowColor: dependencyArrowColor ?? _defaultDependencyArrowColor,
    dependencyArrowWidth: dependencyArrowWidth,
    hoverRowColor: hoverRowColor ?? _defaultHoverRowColor,
    selectedRowColor: selectedRowColor ?? _defaultSelectedRowColor,
    textColor: textColor ?? _defaultTextColor,
    barTextColor: barTextColor ?? _defaultTextColor,
    groupCapsuleStyle: groupCapsuleStyle,
    groupCapsuleHorizontalPadding: groupCapsuleHorizontalPadding,
    groupCapsuleVerticalPadding: groupCapsuleVerticalPadding,
    dragTooltipDateFormat: dragTooltipDateFormat,
    fontFamily: fontFamily,
    fontSize: fontSize,
    cellHeight: cellHeight,
    barVerticalPadding: barVerticalPadding,
    rowPadding: rowPadding,
    rowsGroupPadding: rowsGroupPadding,
    headerHeight: headerHeight,
    dayMinWidth: dayMinWidth,
    cellRounded: cellRounded,
    childrenPeekWidthThreshold: childrenPeekWidthThreshold,
  );
}
