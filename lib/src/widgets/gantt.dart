import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:provider/provider.dart';

import '../../flutter_gantt.dart';
import 'activities_grid.dart';
import 'activities_list.dart';
import 'calendar_grid.dart';
import 'checklist_tree_guides.dart';
import 'children_peek_overlay.dart';
import 'controller_extension.dart';
import 'dependency_arrows.dart';
import 'group_capsules.dart';
import 'markers_overlay.dart';

/// A function that converts a [DateTime] representing a month
/// into its textual representation, using the given [BuildContext].
///
/// The [BuildContext] can be used to access localization,
/// theme data, or other inherited widgets.
///
/// The returned string is typically a localized or human-readable
/// name of the month (e.g. "January", "Jan", "Gennaio").
///
/// Example:
/// ```dart
/// String monthName(BuildContext context, DateTime date) {
///   return MaterialLocalizations.of(context).formatMonthYear(date);
/// }
/// ```
typedef MonthToText = String Function(BuildContext context, DateTime date);

/// A customizable Gantt chart widget for Flutter.
///
/// Displays activities in a timeline view with configurable appearance and behavior.
/// The chart consists of three main components:
/// 1. ActivitiesList - Shows activity names on the left
/// 2. CalendarGrid - Shows date headers at the top
/// 3. ActivitiesGrid - Shows activity durations on the right
class Gantt extends StatefulWidget {
  /// The initial start date to display.
  final DateTime? startDate;

  /// The list of activities to display (mutually exclusive with [activitiesAsync]).
  final List<GanttActivity>? activities;

  /// Async function to load activities (mutually exclusive with [activities]).
  ///
  /// This function is called when the date range changes to fetch new activities.
  final Future<List<GanttActivity>> Function(
    DateTime startDate,
    DateTime endDate,
    List<GanttActivity> activities,
  )?
  activitiesAsync;

  /// The list of holidays to highlight (mutually exclusive with [holidaysAsync]).
  final List<GantDateHoliday>? holidays;

  /// Async function to load holidays (mutually exclusive with [holidays]).
  final Future<List<GantDateHoliday>> Function(
    DateTime startDate,
    DateTime endDate,
    List<GantDateHoliday> holidays,
  )?
  holidaysAsync;

  /// The list of point-in-time markers to display (mutually exclusive with
  /// [markersAsync]).
  final List<GanttMarker>? markers;

  /// Async function to load markers (mutually exclusive with [markers]).
  final Future<List<GanttMarker>> Function(
    DateTime startDate,
    DateTime endDate,
    List<GanttMarker> markers,
  )?
  markersAsync;

  /// The theme to use for the Gantt chart.
  final GanttTheme? theme;

  /// The controller for managing Gantt chart state.
  final GanttController? controller;

  /// Callback when an activity's dates changes.
  final GanttActivityOnChangedEvent? onActivityChanged;

  /// Enable draggable cell.
  final bool enableDraggable;

  /// Whether dragging or resizing a parent activity's bar is constrained
  /// only by its own parent's date range, ignoring its children's current
  /// dates — since neither a move nor a resize adjusts children on its own,
  /// requiring them to stay inside the new window would make any activity
  /// with children effectively un-draggable/un-resizable past them.
  /// Defaults to `true`.
  ///
  /// With this on, use [onActivityChanged] to reconcile children yourself —
  /// e.g. shift every descendant by the same delta on a move, or clamp a
  /// descendant's date to the new range on a resize — the same way you
  /// already update the dragged activity's own date. Without it, a child
  /// left behind outside its parent's new range would otherwise render
  /// looking clipped/detached.
  final bool allowParentIndependentDateMovement;

  /// The list of dates to highlight
  final List<DateTime>? highlightedDates;

  /// The flex ratio for the activities list column (default: 1).
  final int activitiesListFlex;

  /// The flex ratio for the grid area column (default: 4).
  final int gridAreaFlex;

  /// Whether to show the ISO week number row.
  ///
  /// If `true`, a row displaying ISO-8601 week numbers is shown
  /// between the month headers and the day cells.
  final bool showIsoWeek;

  /// Whether to draw tree connector guide lines (elbow/tee) in the
  /// activities list, in addition to plain indentation.
  final bool showTreeGuides;

  /// When set, replaces the activities list's default name-only column with
  /// these columns — e.g. to also show start/end dates or duration next to
  /// the name, without leaving the chart. `null` (the default) keeps the
  /// original name-only layout. Rows here are never resortable (unlike
  /// `GanttActivitiesTable`), since row order must stay in lockstep with the
  /// chart beside it.
  final List<GanttListColumn>? listColumns;

  /// Whether to draw a background capsule wrapping each activity that has
  /// children, spanning it and its descendants. Only applies in scroll
  /// mode (see [GanttController.fixedDayWidth]).
  final bool showGroupCapsules;

  /// Called when an activities-list row is right-clicked (or, on a
  /// trackpad, secondary-tapped) — with the activity and the pointer's
  /// global position. `null` (the default) does nothing; there's no
  /// built-in context menu, since what it should contain (e.g. different
  /// items for a top-level Task vs. a leaf Subitem) is business logic the
  /// package can't know. Typically you'd call Flutter's own `showMenu` at
  /// [Offset] on tap:
  ///
  /// ```dart
  /// Gantt(
  ///   onActivitySecondaryTap: (activity, position) async {
  ///     final selected = await showMenu<String>(
  ///       context: context,
  ///       position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
  ///       items: [/* your own items, chosen from activity.depth etc. */],
  ///     );
  ///     // handle `selected`
  ///   },
  /// )
  /// ```
  final void Function(GanttActivity activity, Offset globalPosition)?
  onActivitySecondaryTap;

  /// Called when the small "peek children" icon on a bar is tapped — with
  /// the activity and the pointer's global position. `null` (the default)
  /// does nothing.
  ///
  /// [GanttCell] shows that icon, on hover, only for an activity that has
  /// children (e.g. a Subtask with checklist Subitems) whose bar is too
  /// narrow to make that obvious any other way — resized down to a few
  /// days, its own title barely fits, let alone a hint that there's more
  /// nested underneath. There's no built-in popup content, since it should
  /// look like whatever your `listColumns`/`titleWidget` already render for
  /// those children — typically you'd reuse the exact same widgets in a
  /// `showMenu`, positioned at [Offset]:
  ///
  /// ```dart
  /// Gantt(
  ///   onPeekChildrenTap: (activity, position) async {
  ///     await showMenu<void>(
  ///       context: context,
  ///       position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
  ///       items: [
  ///         for (final child in activity.children ?? const [])
  ///           PopupMenuItem<void>(
  ///             enabled: false,
  ///             child: child.titleWidget ?? Text(child.title ?? ''),
  ///           ),
  ///       ],
  ///     );
  ///   },
  /// )
  /// ```
  final void Function(GanttActivity activity, Offset globalPosition)?
  onPeekChildrenTap;

  /// Restores [listColumns] widths from a previous session — one ratio per
  /// column (each `0.0`–`1.0`, summed across the flex-based columns). Must
  /// match [listColumns] in length to take effect. The package never
  /// persists this itself; pair with [onColumnWidthsChanged] and your own
  /// storage (`SharedPreferences`, a user-settings API, ...):
  ///
  /// ```dart
  /// Gantt(
  ///   listColumns: myColumns,
  ///   initialColumnWidths: savedRatios, // read from storage at startup
  ///   onColumnWidthsChanged: (ratios) => saveToStorage(ratios),
  /// )
  /// ```
  final List<double>? initialColumnWidths;

  /// Called once a [listColumns] boundary drag finishes (on release, not on
  /// every pointer move mid-drag) with every column's current width ratio.
  /// `null` (the default) does nothing.
  final void Function(List<double> ratios)? onColumnWidthsChanged;

  /// The drag/resize interaction bars use.
  /// Defaults to [GanttInteractionMode.selectableDrag].
  final GanttInteractionMode interactionMode;

  /// A callback used to convert a [DateTime] value into a textual
  /// representation of its month, using the provided [BuildContext].
  ///
  /// If provided, this function overrides the default month-to-text
  /// conversion logic.
  /// If `null`, a fallback or built-in formatter may be used instead.
  final MonthToText? monthToText;

  /// Whether the chart scrolls horizontally so today's column sits in the
  /// middle of the viewport once it first lays out. Only applies in scroll
  /// mode (see [GanttController.fixedDayWidth]). Defaults to `true`.
  final bool centerOnToday;

  /// Whether selecting an activity (clicking its row in the activities
  /// list, or clicking its bar — both set
  /// [GanttController.selectedActivityKey]) scrolls the chart horizontally
  /// to center that activity's bar in the viewport. Only applies in scroll
  /// mode. Defaults to `true`.
  final bool centerOnSelection;

  /// Creates a [Gantt] chart widget.
  ///
  /// Throws an [AssertionError] if:
  /// - Neither [startDate] nor [controller] is provided
  /// - Both [activities] and [activitiesAsync] are provided or both are null
  /// - Both [holidays] and [holidaysAsync] are provided
  /// [showIsoWeek] enables the ISO week-number row (default: `false`).
  const Gantt({
    super.key,
    this.startDate,
    this.theme,
    this.activities,
    this.activitiesAsync,
    this.holidays,
    this.holidaysAsync,
    this.markers,
    this.markersAsync,
    this.controller,
    this.onActivityChanged,
    this.highlightedDates,
    this.enableDraggable = true,
    this.allowParentIndependentDateMovement = true,
    this.activitiesListFlex = 1,
    this.gridAreaFlex = 4,
    this.showIsoWeek = false,
    this.showTreeGuides = false,
    this.showGroupCapsules = false,
    this.onActivitySecondaryTap,
    this.onPeekChildrenTap,
    this.initialColumnWidths,
    this.onColumnWidthsChanged,
    this.listColumns,
    this.interactionMode = GanttInteractionMode.selectableDrag,
    this.monthToText,
    this.centerOnToday = true,
    this.centerOnSelection = true,
  }) : assert(
         (startDate != null || controller != null) &&
             ((activities == null) != (activitiesAsync == null)) &&
             (holidays == null || holidaysAsync == null) &&
             (markers == null || markersAsync == null),
       );

  @override
  State<Gantt> createState() => _GanttState();
}

class _GanttState extends State<Gantt> {
  late GanttTheme theme;
  late GanttController controller;
  Offset? _lastPosition;
  DateTime? _panStartDate;
  late LinkedScrollControllerGroup _linkedControllers;
  late ScrollController _listController;
  late ScrollController _gridColumnsController;
  late ScrollController _horizontalController;
  // Keeps ActivitiesGrid's Element (and its ListView's live ScrollPosition)
  // alive across the GestureDetector <-> SingleChildScrollView swap that
  // toggling scroll mode causes, instead of Flutter destroying and
  // recreating it — which would otherwise transiently double-attach
  // _gridColumnsController and crash any code reading its offset mid-swap.
  final GlobalKey _activitiesGridKey = GlobalKey();
  bool _loading = false;
  // Tracks the last key we already centered on, so a notifyListeners() fired
  // for an unrelated change (e.g. mid-drag) doesn't re-trigger the scroll.
  String? _lastCenteredSelectionKey;

  @override
  void initState() {
    super.initState();
    _linkedControllers = LinkedScrollControllerGroup();
    _listController = _linkedControllers.addAndGet();
    _gridColumnsController = _linkedControllers.addAndGet();
    _horizontalController = ScrollController();
    theme = widget.theme ?? GanttTheme();
    controller =
        widget.controller ?? GanttController(startDate: widget.startDate);
    controller.theme = theme;
    controller.addFetchListener(_getAsync);
    controller.attachHorizontalScrollController(_horizontalController);
    controller.addListener(_onControllerChangedForCentering);
    if (widget.onActivityChanged != null) {
      controller.addOnActivityChangedListener(widget.onActivityChanged!);
    }
    if (widget.onPeekChildrenTap != null) {
      controller.addOnPeekChildrenTapListener(widget.onPeekChildrenTap!);
    }
    if (widget.holidays != null) {
      controller.setHolidays(widget.holidays!, notify: false);
    }
    if (widget.markers != null) {
      controller.setMarkers(widget.markers!, notify: false);
    }
    if (widget.activities != null) {
      controller.setActivities(widget.activities!, notify: false);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.fetch();
      });
    }
    if (widget.highlightedDates != null) {
      controller.setHighlightedDates(widget.highlightedDates!, notify: false);
    }
    controller.enableDraggable = widget.enableDraggable;
    controller.allowParentIndependentDateMovement =
        widget.allowParentIndependentDateMovement;
    controller.interactionMode = widget.interactionMode;
    if (widget.centerOnToday) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerOnDate(DateTime.now(), animate: false);
      });
    }
  }

  // Fires on every controller change; only acts when selectedActivityKey
  // actually changed, and only if the app opted into it.
  void _onControllerChangedForCentering() {
    if (!widget.centerOnSelection) return;
    final key = controller.selectedActivityKey;
    if (key == _lastCenteredSelectionKey) return;
    _lastCenteredSelectionKey = key;
    if (key == null) return;
    final activity = controller.activities.getFromKey(key);
    if (activity != null) _centerOnActivity(activity);
  }

  void _centerOnDate(DateTime date, {required bool animate}) {
    final x = controller.xForDate(date) + controller.dayColumnWidth / 2;
    _scrollHorizontalTo(x, animate: animate);
  }

  void _centerOnActivity(GanttActivity activity) {
    final startX = controller.xForDate(activity.start);
    final endX = controller.xForDate(activity.end) + controller.dayColumnWidth;
    _scrollHorizontalTo((startX + endX) / 2, animate: true);
  }

  void _scrollHorizontalTo(double targetX, {required bool animate}) {
    if (!controller.isScrollMode || !_horizontalController.hasClients) return;
    final position = _horizontalController.position;
    final target = (targetX - position.viewportDimension / 2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (animate) {
      _horizontalController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _horizontalController.jumpTo(target);
    }
  }

  @override
  void dispose() {
    controller.removeFetchListener(_getAsync);
    controller.removeListener(_onControllerChangedForCentering);
    if (widget.onActivityChanged != null) {
      controller.removeOnActivityChangedListener(widget.onActivityChanged!);
    }
    if (widget.onPeekChildrenTap != null) {
      controller.removeOnPeekChildrenTapListener(widget.onPeekChildrenTap!);
    }
    controller.attachHorizontalScrollController(null);
    if (widget.controller == null) {
      controller.dispose();
    }
    _listController.dispose();
    _gridColumnsController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  // A horizontal Scrollable only auto-applies a pointer signal's dx to its
  // own axis, so a plain mouse wheel (dy-only) does nothing by default —
  // only a trackpad swipe (which produces a real dx) scrolls it out of the
  // box. Redirect a dx-less wheel event's dy onto the horizontal controller
  // so both input methods work; leave any event that already has dx alone,
  // since the scroll view's own built-in handling already covers it.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        event.scrollDelta.dx == 0 &&
        event.scrollDelta.dy != 0 &&
        _horizontalController.hasClients) {
      final position = _horizontalController.position;
      final target = (position.pixels + event.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _horizontalController.jumpTo(target);

      // The same dx-less event is *also* auto-applied by the chart's own
      // nested vertical ListView — it independently registers for the
      // pointer-signal resolver on its own axis, unaffected by the redirect
      // above — which, since list/chart vertical scroll is linked, drags
      // the ActivitiesList pane along too. A wheel gesture over the chart
      // should stay purely horizontal, so undo that once it's landed
      // (resolver resolution happens synchronously right after this
      // handler returns, so a microtask is enough to run after it).
      if (_gridColumnsController.hasClients) {
        final verticalPixelsBefore = _gridColumnsController.position.pixels;
        Future.microtask(() {
          if (_gridColumnsController.hasClients &&
              _gridColumnsController.position.pixels != verticalPixelsBefore) {
            _gridColumnsController.jumpTo(verticalPixelsBefore);
          }
        });
      }
    }
  }

  void _handlePanStart(DragStartDetails details) {
    _lastPosition = details.localPosition;
    _panStartDate = controller.startDate;
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    double maxWidth,
    BuildContext context,
  ) {
    final dayWidth = maxWidth / controller.internalDaysViews;
    final dx = (details.localPosition.dx - _lastPosition!.dx);
    if (_lastPosition != null && dx.abs() > dayWidth) {
      // Check text direction to handle RTL correctly
      // Try Directionality first, fallback to locale check
      final textDirection = Directionality.of(context);
      final locale = Localizations.localeOf(context);
      final isRTL =
          textDirection == TextDirection.rtl ||
          locale.languageCode == 'ar' ||
          locale.languageCode == 'he' ||
          locale.languageCode == 'fa' ||
          locale.languageCode == 'ur';

      // In RTL, swap next/prev to match user expectations
      // LTR: negative dx (left) → next, positive dx (right) → prev
      // RTL: negative dx (left) → prev, positive dx (right) → next
      if (isRTL) {
        // In RTL, invert the logic
        if (dx.isNegative) {
          controller.prev(fetchData: false); // Drag left → earlier dates
        } else {
          controller.next(fetchData: false); // Drag right → later dates
        }
      } else {
        // LTR behavior (original)
        if (dx.isNegative) {
          controller.next(fetchData: false);
        } else {
          controller.prev(fetchData: false);
        }
      }
      _lastPosition = details.localPosition;
    }
  }

  void _handlePanEnd(DragEndDetails details) => _reset();

  void _handlePanCancel() => _reset();

  void _reset() {
    final dateChanged =
        _panStartDate != null &&
        !controller.startDate.isAtSameMomentAs(_panStartDate!);
    _lastPosition = null;
    _panStartDate = null;
    if (dateChanged) controller.fetch();
  }

  Future<void> _getAsync() async {
    if (!mounted) return;
    if (widget.activitiesAsync != null ||
        widget.holidaysAsync != null ||
        widget.markersAsync != null) {
      var activities = <GanttActivity>[];
      var holidays = <GantDateHoliday>[];
      var markers = <GanttMarker>[];
      if (mounted) {
        setState(() {
          _loading = true;
        });
      }
      if (widget.activitiesAsync != null) {
        activities = await widget.activitiesAsync!(
          controller.startDate,
          controller.endDate,
          controller.activities,
        );
        if (!mounted) return;
        controller.setActivities(activities, notify: false);
      }
      if (widget.holidaysAsync != null) {
        holidays = await widget.holidaysAsync!(
          controller.startDate,
          controller.endDate,
          controller.holidays,
        );
        if (!mounted) return;
        controller.setHolidays(holidays, notify: false);
      }
      if (widget.markersAsync != null) {
        markers = await widget.markersAsync!(
          controller.startDate,
          controller.endDate,
          controller.markers,
        );
        if (!mounted) return;
        controller.setMarkers(markers, notify: false);
      }
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      Provider<GanttTheme>.value(value: theme),
      ChangeNotifierProvider<GanttController>.value(value: controller),
    ],
    builder: (context, child) {
      final c = context.watch<GanttController>();
      return Container(
        decoration: BoxDecoration(
          color: theme.backgroundColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: 4,
              child: _loading ? LinearProgressIndicator() : Container(),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: widget.activitiesListFlex,
                    child: ActivitiesList(
                      activities: c.activities,
                      controller: _listController,
                      showIsoWeek: widget.showIsoWeek,
                      showTreeGuides: widget.showTreeGuides,
                      columns: widget.listColumns,
                      onActivitySecondaryTap: widget.onActivitySecondaryTap,
                      initialColumnWidths: widget.initialColumnWidths,
                      onColumnWidthsChanged: widget.onColumnWidthsChanged,
                    ),
                  ),
                  Container(width: 1, color: theme.dividerColor),
                  Expanded(
                    flex: widget.gridAreaFlex,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        controller.gridWidth = constraints.maxWidth;
                        final chart = Stack(
                          children: [
                            CalendarGrid(
                              holidays: c.holidays,
                              showIsoWeek: widget.showIsoWeek,
                              monthToText: widget.monthToText,
                            ),
                            // Separates the calendar header (month/week/day
                            // rows) from the bars below it, matching the
                            // header/content divider under the activities
                            // list's own column header.
                            Positioned(
                              top:
                                  theme.headerHeight +
                                  (widget.showIsoWeek ? 10 : 0) -
                                  1,
                              left: 0,
                              right: 0,
                              height: 1,
                              child: Container(color: theme.dividerColor),
                            ),
                            if (c.isScrollMode && widget.showGroupCapsules)
                              GanttGroupCapsules(
                                activities: c.activities,
                                verticalScrollController: _gridColumnsController,
                                showIsoWeek: widget.showIsoWeek,
                              ),
                            if (widget.showTreeGuides)
                              ChecklistTreeGuides(
                                activities: c.activities,
                                verticalScrollController: _gridColumnsController,
                                showIsoWeek: widget.showIsoWeek,
                              ),
                            ActivitiesGrid(
                              key: _activitiesGridKey,
                              activities: c.activities,
                              controller: _gridColumnsController,
                              showIsoWeek: widget.showIsoWeek,
                            ),
                            if (c.isScrollMode)
                              DependencyArrows(
                                activities: c.activities,
                                verticalScrollController: _gridColumnsController,
                                showIsoWeek: widget.showIsoWeek,
                              ),
                            MarkersOverlay(
                              activities: c.activities,
                              verticalScrollController: _gridColumnsController,
                              showIsoWeek: widget.showIsoWeek,
                            ),
                            ChildrenPeekOverlay(
                              activities: c.activities,
                              verticalScrollController: _gridColumnsController,
                              showIsoWeek: widget.showIsoWeek,
                            ),
                          ],
                        );
                        if (c.isScrollMode) {
                          final width =
                              c.canvasWidth > constraints.maxWidth
                                  ? c.canvasWidth
                                  : constraints.maxWidth;
                          return Listener(
                            onPointerSignal: _handlePointerSignal,
                            // Mouse is deliberately excluded from drag-to-
                            // scroll here (touch/trackpad keep it) so a
                            // mouse click-drag is unambiguously "manipulate
                            // a bar," never "pan the canvas" — the two
                            // would otherwise compete for the same gesture.
                            // Wheel scrolling is unaffected: it's handled
                            // separately, above, via onPointerSignal.
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(
                                dragDevices: const {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.trackpad,
                                },
                              ),
                              child: SingleChildScrollView(
                                controller: _horizontalController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: width,
                                  height: constraints.maxHeight,
                                  child: chart,
                                ),
                              ),
                            ),
                          );
                        }
                        return GestureDetector(
                          onPanStart: _handlePanStart,
                          onPanUpdate:
                              (details) => _handlePanUpdate(
                                details,
                                constraints.maxWidth,
                                context,
                              ),
                          onPanEnd: _handlePanEnd,
                          onPanCancel: _handlePanCancel,
                          child: chart,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
