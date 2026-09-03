import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'activity.dart';

/// Resolves a display [Color] for an [activity] — reads whatever fields on
/// it matter to your own scheme (its `depth`, `colorIndex`, `color`, or
/// anything else); the package itself never dictates which ones you need.
///
/// When [GanttTheme.colorResolver] is set, it fully owns color computation —
/// the resolver decides whether/how to honor [GanttActivity.color] itself
/// (for example, using it verbatim at depth 0 but lightening it at deeper
/// levels). `null` (the default) instead falls back to the activity's own
/// color, or [GanttTheme.defaultCellColor] if it has none — see
/// [defaultGanttColorResolver] for an optional per-depth tone-shading
/// resolver you can opt into instead.
typedef GanttColorResolver = Color Function(GanttActivity activity);

/// An example per-depth saturation/lightness table for
/// [defaultGanttColorResolver] — depth 1 a touch *darker* than depth 0,
/// depth 2 the lightest of the three. Not applied unless you opt into
/// [defaultGanttColorResolver] (or your own resolver) via
/// [GanttTheme.colorResolver]; tune freely if you do.
const List<({double s, double l})> _ganttBarTones = [
  (s: 0.62, l: 0.64), // depth 0
  (s: 0.56, l: 0.62), // depth 1
  (s: 0.58, l: 0.78), // depth 2
];

/// The hue used for an activity with no explicit color when
/// [defaultGanttColorResolver] is in effect. Pass a `color` on the activity
/// itself (see [GanttActivity.withColor]) to pick per-activity hues instead
/// of this single shared one.
const double _ganttBarHue = 95;

/// An optional [GanttColorResolver] implementation: a shared hue for
/// activities with no explicit color (tinted per depth via
/// [_ganttBarTones]), or a lightening formula for activities that do have
/// one, so a deeper descendant reads lighter even for an arbitrary custom
/// hex. Not used unless you pass it explicitly as
/// `GanttTheme(colorResolver: defaultGanttColorResolver)` —
/// [GanttTheme.colorResolver] is `null` by default.
Color defaultGanttColorResolver(GanttActivity activity) {
  final depth = activity.depth;
  final explicitColor = activity.color;
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
  return HSLColor.fromAHSL(1, hsl.hue, fillSaturation, fillLightness).toColor();
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

/// Builds the "peek children" badge shown while hovering a bar too narrow
/// to show its children's own content inline (see
/// [GanttTheme.childrenPeekWidthThreshold], `ChildrenPeekOverlay`).
/// Rendered inside a fixed-size hit-testable region (see
/// `ChildrenPeekOverlay._iconSize`), so keep whatever you return roughly
/// icon-sized — it isn't stretched or clipped to fit.
typedef GanttPeekBadgeBuilder =
    Widget Function(BuildContext context, GanttActivity activity);

/// The package's built-in default [GanttPeekBadgeBuilder]: a small filled
/// badge with a chat-bubble icon, hinting "there's more content here, tap to
/// see it."
Widget defaultGanttPeekBadgeBuilder(
  BuildContext context,
  GanttActivity activity,
) => Container(
  decoration: BoxDecoration(
    color: const Color(0xFF1E9E93),
    borderRadius: BorderRadius.circular(7),
    boxShadow: const [
      BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
    ],
  ),
  child: const Icon(
    Icons.chat_bubble_outline_rounded,
    size: 13,
    color: Colors.white,
  ),
);

/// Resolves the [FontWeight] for a row's own name text from its nesting
/// [depth] (see `ActivitiesList`'s built-in name column). Return `null` for
/// a given depth to use `theme.textStyle()`'s own default weight there
/// instead.
typedef GanttNameWeightResolver = FontWeight? Function(int depth);

/// An example [GanttNameWeightResolver]: 600 at depth 0, 500 at depth 1, 400
/// at depth 2+ (matches QV Agent Hub's row-name weight scale). Not applied
/// unless you opt in via `GanttTheme(nameWeightForDepth:
/// ganttNameWeightForDepth)` — [GanttTheme.nameWeightForDepth] is `null` by
/// default, so every depth renders at the same weight out of the box.
FontWeight ganttNameWeightForDepth(int depth) => switch (depth) {
  0 => FontWeight.w600,
  1 => FontWeight.w500,
  _ => FontWeight.w400,
};

/// A customizable theme for Gantt chart widgets.
///
/// Provides styling options for various elements of the Gantt chart,
/// including colors, dimensions, and spacing.
class GanttTheme {
  /// The background color of the Gantt chart.
  /// Defaults to [Color(0xFFF9F9F9)].
  final Color backgroundColor;

  /// The color used to highlight holiday dates.
  /// Defaults to [Color(0xFFFF6F61)].
  final Color holidayColor;

  /// The color used to highlight weekend dates.
  /// Defaults to [Color(0xFFECEFF1)].
  final Color weekendColor;

  /// The background color for today's date cell.
  /// Defaults to [Color(0xFF2979FF)].
  final Color todayBackgroundColor;

  /// The text color for today's date cell.
  /// Defaults to [Colors.white].
  final Color todayTextColor;

  /// The default color for activity cells.
  /// Defaults to [Color(0xFF81D4FA)].
  final Color defaultCellColor;

  /// The color of the progress-fill overlay drawn over [GanttActivity.progress].
  /// Defaults to [Colors.black26].
  final Color progressOverlayColor;

  /// An optional hook to resolve an activity's color, overriding its plain
  /// per-activity color entirely. `null` by default — an activity's own
  /// color (or [defaultCellColor] if it has none) is used untouched. Pass
  /// [defaultGanttColorResolver] for a built-in per-depth tone-shading
  /// scheme instead, or supply your own. See [GanttColorResolver].
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

  /// The color of the structural divider lines inside the chart: the line
  /// between the activities-list and chart panes, and the line under the
  /// activities-list header row. Also used for the outer frame border when
  /// [chartBorderRadius] opts into one.
  /// Defaults to [Color(0xFFCCD0DE)] (the same tone as [treeGuideColor]).
  final Color dividerColor;

  /// Rounds the whole chart's outer corners and draws a [dividerColor]
  /// border around it (a "card" look) when set. `null` (the default) draws
  /// neither — a plain rectangle filled with [backgroundColor], same as
  /// before this option existed. Pass `0.0` for a square-cornered border
  /// with no rounding, or a positive radius for rounded corners.
  final double? chartBorderRadius;

  /// Resolves the small leading icon shown after each activities-list row's
  /// expand/collapse chevron. Defaults to [defaultGanttDepthIcon]; set to
  /// `null` to show no depth icon at all.
  final GanttDepthIconBuilder? depthIconBuilder;

  /// Resolves the [FontWeight] of a row's own name text in the
  /// activities-list built-in name column, from its nesting depth. `null`
  /// by default — every depth renders at the same (unbolded) weight. Pass
  /// [ganttNameWeightForDepth] for a built-in per-depth boldness scheme
  /// instead, or supply your own. See [GanttNameWeightResolver].
  final GanttNameWeightResolver? nameWeightForDepth;

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
  /// the date span it wraps — nudged down slightly at each deeper nesting
  /// level, just enough that two nested capsules sharing the same
  /// last-descendant row never draw their borders on the exact same pixel
  /// (see `GanttGroupCapsules`); every depth still reads as the same
  /// thickness at a glance. This is the depth-0 value.
  /// Defaults to 6.0.
  final double groupCapsuleHorizontalPadding;

  /// The vertical padding, in pixels, between a group capsule's top/bottom
  /// edge and the rows it wraps — nudged down the same way as
  /// [groupCapsuleHorizontalPadding] at each deeper nesting level; this is
  /// the depth-0 value. Equal to [groupCapsuleHorizontalPadding] by default
  /// so a capsule reads as an even frame around its bar, not a
  /// taller-looking gap on the sides than top/bottom. Also see
  /// `GanttGroupCapsules`, which additionally caps this per-edge to that
  /// edge's own bounding row's [barVerticalPadding] inset — an ordinary bar
  /// row's inset comfortably covers this default, so it's a no-op there,
  /// but a checklist row (`GanttActivity.showCell` false) has none, so that
  /// edge gets no outward padding rather than bleeding into whatever row
  /// follows it.
  /// Defaults to 6.0.
  final double groupCapsuleVerticalPadding;

  /// Formats a date for the floating tooltip shown while dragging a bar in
  /// [GanttInteractionMode.selectableDrag]. `null` (the default) uses a
  /// locale-aware built-in format.
  final String Function(DateTime)? dragTooltipDateFormat;

  /// The background color of that same floating drag tooltip.
  /// Defaults to [Colors.black87].
  final Color dragTooltipBackgroundColor;

  /// The text color of that same floating drag tooltip — the "→" separator
  /// between the two dates uses this at 70% opacity.
  /// Defaults to [Colors.white].
  final Color dragTooltipTextColor;

  /// The fill color of a selected bar's resize handles in
  /// [GanttInteractionMode.selectableDrag] (their border already uses
  /// [defaultCellColor]).
  /// Defaults to [Colors.white].
  final Color resizeHandleColor;

  /// The font family used for all text the chart itself renders (bar
  /// titles, row names, date/month labels — not text supplied by a
  /// consumer via [GanttActivity.titleWidget]/`builder`/`cellBuilder`).
  /// `null` by default — the package bundles no font of its own, so text
  /// falls back to whatever the host app's ambient font is. If you do want
  /// a specific font, bundle it in *your own* app (its `pubspec.yaml`, its
  /// `fonts:` section) and pass that family name here — remember a
  /// package-bundled font needs the `packages/<package>/<family>` form,
  /// but your own app's font is just the plain family name. Setting this to
  /// a name that isn't actually loaded never throws — text just falls back
  /// to the platform default.
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
  /// Defaults to 24.0.
  final double cellHeight;

  /// The vertical padding, in pixels, between a bar's top/bottom edge and
  /// its row slot ([cellHeight]) — so the row can be taller than the bar
  /// itself. Applied on both edges, so the bar's own rendered height is
  /// `cellHeight - barVerticalPadding * 2`. Doesn't affect checklist rows
  /// (see `GanttActivity.showCell`), which already size to the row slot via
  /// their own layout.
  /// Defaults to 0.0 (the bar fills its row slot exactly, same as before
  /// this field existed).
  final double barVerticalPadding;

  /// The vertical padding between rows that aren't a group boundary; see
  /// [rowsGroupPadding] for the wider gap kept around a group's own
  /// capsule.
  /// Defaults to 4.0.
  final double rowPadding;

  /// The vertical padding between groups of rows — applied around every
  /// activity with children (see `rowTopPadding`), on top of [rowPadding].
  /// A purely cosmetic knob for extra breathing room around groups; not
  /// what keeps a group's capsule from bleeding into whatever row follows
  /// it (`GanttGroupCapsules` clamps that per-edge on its own — see
  /// [groupCapsuleVerticalPadding] — regardless of this value).
  /// Defaults to 16.0.
  final double rowsGroupPadding;

  /// The height of the header section.
  /// Defaults to 62.0.
  final double headerHeight;

  /// The extra height reserved above the day rows for the ISO week-number
  /// row, on top of [headerHeight], when a widget's own `showIsoWeek` is on.
  /// See `headerOffsetFor`.
  /// Defaults to 10.0.
  final double weekRowHeight;

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

  /// Builds the "peek children" badge itself (see
  /// [childrenPeekWidthThreshold]). Defaults to
  /// [defaultGanttPeekBadgeBuilder]; set to `null` to disable the badge
  /// entirely — hovering a too-narrow bar then does nothing visible,
  /// though `Gantt.onPeekChildrenTap` is still wired the same either way.
  final GanttPeekBadgeBuilder? peekBadgeBuilder;

  // cellHeight/barVerticalPadding default to the package's original,
  // pre-existing sizing: cellHeight alone used to be the bar's own rendered
  // height (no separate row-slot-vs-bar-inset split existed at all) — so
  // barVerticalPadding defaults to 0, making `cellHeight - 0*2 == cellHeight`
  // once again the bar's full rendered height, same as before this field
  // existed. Both are still fully overridable if you want a taller row with
  // a visually smaller bar inside it.
  static const double _defaultCellHeight = 24.0;
  static const double _defaultBarVerticalPadding = 0.0;
  static const double _defaultRowPadding = 4.0;
  static const double _defaultRowsGroupPadding = 16.0;
  static const double _defaultHeaderHeight = 62.0;
  static const double _defaultWeekRowHeight = 10.0;
  static const double _defaultDayMinWidth = 30.0;
  static const double _defaultTodayLineWidth = 1.5;
  static const double _defaultTreeIndentWidth = 14.0;
  static const double _defaultDependencyArrowWidth = 1.25;
  static const double _defaultGroupCapsuleHorizontalPadding = 6.0;
  // Equal to horizontal so a capsule's frame looks even on every side, at
  // every nesting depth — see _paddingForDepth in group_capsules.dart, which
  // now shrinks both axes by depth identically instead of just this one.
  static const double _defaultGroupCapsuleVerticalPadding = 6.0;
  static const double _defaultFontSize = 12.0;
  static const double _defaultCellRounded = 8.0;
  static const double _defaultChildrenPeekWidthThreshold = 90.0;

  static const Color _defaultBackgroundColor = Color(0xFFF9F9F9);
  static const Color _defaultHolidayColor = Color(0xFFFF6F61);
  static const Color _defaultWeekendColor = Color(0xFFECEFF1);
  static const Color _defaultTodayBackgroundColor = Color(0xFF2979FF);
  static const Color _defaultCellColor = Color(0xFF81D4FA);
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
  static const Color _defaultDragTooltipBackgroundColor = Colors.black87;
  static const Color _defaultDragTooltipTextColor = Colors.white;
  static const Color _defaultResizeHandleColor = Colors.white;

  /// Creates a [GanttTheme] with customizable properties.
  const GanttTheme({
    this.backgroundColor = _defaultBackgroundColor,
    this.holidayColor = _defaultHolidayColor,
    this.weekendColor = _defaultWeekendColor,
    this.todayBackgroundColor = _defaultTodayBackgroundColor,
    this.todayTextColor = Colors.white,
    this.defaultCellColor = _defaultCellColor,
    this.progressOverlayColor = Colors.black26,
    this.colorResolver,
    this.todayLineColor = _defaultTodayLineColor,
    this.todayLineWidth = _defaultTodayLineWidth,
    this.treeGuideColor = _defaultTreeGuideColor,
    this.treeIndentWidth = _defaultTreeIndentWidth,
    this.dividerColor = _defaultDividerColor,
    this.chartBorderRadius,
    this.depthIconBuilder = defaultGanttDepthIcon,
    this.nameWeightForDepth,
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
    this.dragTooltipBackgroundColor = _defaultDragTooltipBackgroundColor,
    this.dragTooltipTextColor = _defaultDragTooltipTextColor,
    this.resizeHandleColor = _defaultResizeHandleColor,
    this.fontFamily,
    this.fontSize = _defaultFontSize,
    this.cellHeight = _defaultCellHeight,
    this.barVerticalPadding = _defaultBarVerticalPadding,
    this.rowPadding = _defaultRowPadding,
    this.rowsGroupPadding = _defaultRowsGroupPadding,
    this.headerHeight = _defaultHeaderHeight,
    this.weekRowHeight = _defaultWeekRowHeight,
    this.dayMinWidth = _defaultDayMinWidth,
    this.cellRounded = _defaultCellRounded,
    this.childrenPeekWidthThreshold = _defaultChildrenPeekWidthThreshold,
    this.peekBadgeBuilder = defaultGanttPeekBadgeBuilder,
  });

  /// Creates a [GanttTheme] using the same built-in defaults the plain
  /// constructor uses. [context] is accepted so a consumer can still opt
  /// individual fields into the ambient Material [ColorScheme] (e.g.
  /// `backgroundColor: Theme.of(context).colorScheme.surface`) or
  /// dark-mode-aware values, without this factory forcing that choice for
  /// every field.
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
    GanttColorResolver? colorResolver,
    Color? todayLineColor,
    double todayLineWidth = _defaultTodayLineWidth,
    Color? treeGuideColor,
    Color? dividerColor,
    double? chartBorderRadius,
    GanttDepthIconBuilder? depthIconBuilder = defaultGanttDepthIcon,
    GanttNameWeightResolver? nameWeightForDepth,
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
    Color dragTooltipBackgroundColor = _defaultDragTooltipBackgroundColor,
    Color dragTooltipTextColor = _defaultDragTooltipTextColor,
    Color resizeHandleColor = _defaultResizeHandleColor,
    String? fontFamily,
    double fontSize = _defaultFontSize,
    double cellHeight = _defaultCellHeight,
    double barVerticalPadding = _defaultBarVerticalPadding,
    double rowPadding = _defaultRowPadding,
    double rowsGroupPadding = _defaultRowsGroupPadding,
    double headerHeight = _defaultHeaderHeight,
    double weekRowHeight = _defaultWeekRowHeight,
    double dayMinWidth = _defaultDayMinWidth,
    double cellRounded = _defaultCellRounded,
    double childrenPeekWidthThreshold = _defaultChildrenPeekWidthThreshold,
    GanttPeekBadgeBuilder? peekBadgeBuilder = defaultGanttPeekBadgeBuilder,
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
    chartBorderRadius: chartBorderRadius,
    depthIconBuilder: depthIconBuilder,
    nameWeightForDepth: nameWeightForDepth,
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
    dragTooltipBackgroundColor: dragTooltipBackgroundColor,
    dragTooltipTextColor: dragTooltipTextColor,
    resizeHandleColor: resizeHandleColor,
    fontFamily: fontFamily,
    fontSize: fontSize,
    cellHeight: cellHeight,
    barVerticalPadding: barVerticalPadding,
    rowPadding: rowPadding,
    rowsGroupPadding: rowsGroupPadding,
    headerHeight: headerHeight,
    weekRowHeight: weekRowHeight,
    dayMinWidth: dayMinWidth,
    cellRounded: cellRounded,
    childrenPeekWidthThreshold: childrenPeekWidthThreshold,
    peekBadgeBuilder: peekBadgeBuilder,
  );

  /// Returns a copy of this theme with the given fields replaced — every
  /// other field carries over unchanged (unlike [GanttTheme.new]'s own
  /// defaults, which fall back to the package's built-in values, not this
  /// instance's). Used internally by [Gantt] to override just [headerHeight]
  /// with the calendar header's actually-measured height (see
  /// `CalendarGrid.onHeaderHeightMeasured`); equally useful for a consumer
  /// tweaking one or two fields of an otherwise-shared base theme.
  GanttTheme copyWith({
    Color? backgroundColor,
    Color? holidayColor,
    Color? weekendColor,
    Color? todayBackgroundColor,
    Color? todayTextColor,
    Color? defaultCellColor,
    Color? progressOverlayColor,
    GanttColorResolver? colorResolver,
    Color? todayLineColor,
    double? todayLineWidth,
    Color? treeGuideColor,
    double? treeIndentWidth,
    Color? dividerColor,
    double? chartBorderRadius,
    GanttDepthIconBuilder? depthIconBuilder,
    GanttNameWeightResolver? nameWeightForDepth,
    Color? dependencyArrowColor,
    double? dependencyArrowWidth,
    Color? hoverRowColor,
    Color? selectedRowColor,
    Color? textColor,
    Color? barTextColor,
    GanttGroupCapsuleStyle? groupCapsuleStyle,
    double? groupCapsuleHorizontalPadding,
    double? groupCapsuleVerticalPadding,
    String Function(DateTime)? dragTooltipDateFormat,
    Color? dragTooltipBackgroundColor,
    Color? dragTooltipTextColor,
    Color? resizeHandleColor,
    String? fontFamily,
    double? fontSize,
    double? cellHeight,
    double? barVerticalPadding,
    double? rowPadding,
    double? rowsGroupPadding,
    double? headerHeight,
    double? weekRowHeight,
    double? dayMinWidth,
    double? cellRounded,
    double? childrenPeekWidthThreshold,
    GanttPeekBadgeBuilder? peekBadgeBuilder,
  }) => GanttTheme(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    holidayColor: holidayColor ?? this.holidayColor,
    weekendColor: weekendColor ?? this.weekendColor,
    todayBackgroundColor: todayBackgroundColor ?? this.todayBackgroundColor,
    todayTextColor: todayTextColor ?? this.todayTextColor,
    defaultCellColor: defaultCellColor ?? this.defaultCellColor,
    progressOverlayColor: progressOverlayColor ?? this.progressOverlayColor,
    colorResolver: colorResolver ?? this.colorResolver,
    todayLineColor: todayLineColor ?? this.todayLineColor,
    todayLineWidth: todayLineWidth ?? this.todayLineWidth,
    treeGuideColor: treeGuideColor ?? this.treeGuideColor,
    treeIndentWidth: treeIndentWidth ?? this.treeIndentWidth,
    dividerColor: dividerColor ?? this.dividerColor,
    chartBorderRadius: chartBorderRadius ?? this.chartBorderRadius,
    depthIconBuilder: depthIconBuilder ?? this.depthIconBuilder,
    nameWeightForDepth: nameWeightForDepth ?? this.nameWeightForDepth,
    dependencyArrowColor: dependencyArrowColor ?? this.dependencyArrowColor,
    dependencyArrowWidth: dependencyArrowWidth ?? this.dependencyArrowWidth,
    hoverRowColor: hoverRowColor ?? this.hoverRowColor,
    selectedRowColor: selectedRowColor ?? this.selectedRowColor,
    textColor: textColor ?? this.textColor,
    barTextColor: barTextColor ?? this.barTextColor,
    groupCapsuleStyle: groupCapsuleStyle ?? this.groupCapsuleStyle,
    groupCapsuleHorizontalPadding:
        groupCapsuleHorizontalPadding ?? this.groupCapsuleHorizontalPadding,
    groupCapsuleVerticalPadding:
        groupCapsuleVerticalPadding ?? this.groupCapsuleVerticalPadding,
    dragTooltipDateFormat: dragTooltipDateFormat ?? this.dragTooltipDateFormat,
    dragTooltipBackgroundColor:
        dragTooltipBackgroundColor ?? this.dragTooltipBackgroundColor,
    dragTooltipTextColor: dragTooltipTextColor ?? this.dragTooltipTextColor,
    resizeHandleColor: resizeHandleColor ?? this.resizeHandleColor,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    cellHeight: cellHeight ?? this.cellHeight,
    barVerticalPadding: barVerticalPadding ?? this.barVerticalPadding,
    rowPadding: rowPadding ?? this.rowPadding,
    rowsGroupPadding: rowsGroupPadding ?? this.rowsGroupPadding,
    headerHeight: headerHeight ?? this.headerHeight,
    weekRowHeight: weekRowHeight ?? this.weekRowHeight,
    dayMinWidth: dayMinWidth ?? this.dayMinWidth,
    cellRounded: cellRounded ?? this.cellRounded,
    childrenPeekWidthThreshold:
        childrenPeekWidthThreshold ?? this.childrenPeekWidthThreshold,
    peekBadgeBuilder: peekBadgeBuilder ?? this.peekBadgeBuilder,
  );
}
