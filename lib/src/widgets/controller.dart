import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../flutter_gantt.dart';
import '../utils/datetime.dart';

/// Callback type for activity dates changes.
typedef GanttActivityOnChangedEvent =
    void Function(GanttActivity activity, DateTime? start, DateTime? end);

/// The drag/resize interaction a [Gantt] chart's bars use.
enum GanttInteractionMode {
  /// Always-visible edge handles, whole-bar drag via long-press with a
  /// ghost-feedback overlay.
  longPressDrag,

  /// Click a bar to select it (revealing resize handles) or deselect it;
  /// drag the bar body or a handle to move/resize it live, with a floating
  /// date tooltip. Desktop/pointer-oriented — the default.
  selectableDrag,
}

/// Controls the state and behavior of a [Gantt] widget.
///
/// This controller manages the timeline view, activities data, and handles
/// user interactions like date range changes and activity modifications.
class GanttController extends ChangeNotifier {
  DateTime _startDate;
  DateTime? _minEndDate;
  List<GanttActivity> _activities = [];
  List<GantDateHoliday> _holidays = [];
  List<GanttMarker> _markers = [];
  int? _daysViews;
  final List<GanttActivityOnChangedEvent> _onActivityChangedListeners = [];
  double gridWidth = 0;
  List<DateTime> _highlightedDates = [];
  bool _enableDraggable = true;
  bool _allowParentIndependentDateMovement = true;
  Duration _dragStartDelay;
  double? _fixedDayWidth = _defaultFixedDayWidth;
  ScrollController? _horizontalScrollController;
  GanttInteractionMode _interactionMode = GanttInteractionMode.selectableDrag;
  String? _selectedActivityKey;
  final Set<String> _collapsedKeys = {};

  /// Scroll mode (see [fixedDayWidth]) is on by default, at this pixel
  /// width per day.
  static const double _defaultFixedDayWidth = 40.0;

  late GanttTheme _theme;

  GanttTheme get theme => _theme;

  set theme(GanttTheme value) {
    if (value != _theme) {
      _theme = value;
      notifyListeners();
    }
  }

  /// The current delay of starting drag.
  Duration get dragStartDelay => _dragStartDelay;

  /// Sets the delay of starting drag and notifies listeners if changed.
  set dragStartDelay(Duration value) {
    if (value != _dragStartDelay) {
      _dragStartDelay = value;
      notifyListeners();
    }
  }

  /// The current start date of the visible range.
  DateTime get startDate => _startDate;

  /// Sets the start date and notifies listeners if changed.
  set startDate(DateTime value) {
    value = value.toDate;
    if (value != _startDate) {
      _startDate = value;
      notifyListeners();
    }
  }

  /// In scroll mode, the date the visible range is guaranteed to extend
  /// through even if no activity or holiday reaches that far — the canvas
  /// still grows further when one does (see [GanttController.internalDaysViews]).
  /// Defaults to 30 days after today. Grows automatically as a bar is
  /// dragged past it (see [onActivityChanged]) but never shrinks on its
  /// own; set explicitly to pull it back in.
  DateTime? get minEndDate => _minEndDate;

  /// Sets [minEndDate] and notifies listeners if changed.
  set minEndDate(DateTime? value) {
    value = value?.toDate;
    if (value != _minEndDate) {
      _minEndDate = value;
      notifyListeners();
    }
  }

  /// The list of activities in the Gantt chart.
  List<GanttActivity> get activities => _activities;

  /// Sets the activities list and optionally notifies listeners.
  void setActivities(List<GanttActivity> value, {bool notify = true}) {
    if (value != _activities) {
      _activities = value;
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// The list of holidays in the Gantt chart.
  List<GantDateHoliday> get holidays => _holidays;

  /// Sets the holidays list and optionally notifies listeners.
  void setHolidays(List<GantDateHoliday> value, {bool notify = true}) {
    if (value != _holidays) {
      _holidays = value;
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// The list of point-in-time markers in the Gantt chart.
  List<GanttMarker> get markers => _markers;

  /// Sets the markers list and optionally notifies listeners.
  void setMarkers(List<GanttMarker> value, {bool notify = true}) {
    if (value != _markers) {
      _markers = value;
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// The list of highlighted dates in the Gantt chart.
  List<DateTime> get highlightedDates => _highlightedDates;

  /// Sets the highlighted dates list and optionally notifies listeners.
  void setHighlightedDates(List<DateTime> value, {bool notify = true}) {
    if (value != _highlightedDates) {
      _highlightedDates = value;
      if (notify) {
        notifyListeners();
      }
    }
  }

  /// Return if a date has to be highlighted.
  bool dateToHighlight(DateTime date) =>
      _highlightedDates.map((e) => e.toDate).contains(date.toDate) == true ||
      _highlightedDates.map((e) => e.toDate).contains(date.addDays(1).toDate) ==
          true;

  /// The enable draggable value.
  bool get enableDraggable => _enableDraggable;

  /// Sets the enable draggable value.
  set enableDraggable(bool value) {
    if (value != _enableDraggable) {
      _enableDraggable = value;
      notifyListeners();
    }
  }

  /// The allow parent independent date movement value.
  bool get allowParentIndependentDateMovement =>
      _allowParentIndependentDateMovement;

  /// Sets the allow parent independent date movement value.
  set allowParentIndependentDateMovement(bool value) {
    if (value != _allowParentIndependentDateMovement) {
      _allowParentIndependentDateMovement = value;
      notifyListeners();
    }
  }

  /// The drag/resize interaction bars use.
  /// Defaults to [GanttInteractionMode.longPressDrag] (unchanged behavior).
  GanttInteractionMode get interactionMode => _interactionMode;

  /// Sets [interactionMode] and notifies listeners if changed.
  set interactionMode(GanttInteractionMode value) {
    if (value != _interactionMode) {
      _interactionMode = value;
      notifyListeners();
    }
  }

  /// The currently-selected activity's key, when
  /// [interactionMode] is [GanttInteractionMode.selectableDrag].
  /// `null` when nothing is selected. Only one activity can be selected at
  /// a time.
  String? get selectedActivityKey => _selectedActivityKey;

  /// Sets [selectedActivityKey] and notifies listeners if changed.
  set selectedActivityKey(String? value) {
    if (value != _selectedActivityKey) {
      _selectedActivityKey = value;
      notifyListeners();
    }
  }

  /// Whether [key] is currently collapsed (its children hidden in both the
  /// activities list and the chart). `false` for any key never toggled.
  bool isCollapsed(String key) => _collapsedKeys.contains(key);

  /// Toggles whether [key] is collapsed and notifies listeners. Only
  /// meaningful for an activity with children — collapsing a leaf has no
  /// visible effect, since it has nothing to hide.
  void toggleCollapsed(String key) {
    if (!_collapsedKeys.add(key)) {
      _collapsedKeys.remove(key);
    }
    notifyListeners();
  }

  /// Explicitly sets whether [key] is collapsed and notifies listeners if
  /// that's a change.
  void setCollapsed(String key, bool collapsed) {
    final changed =
        collapsed ? _collapsedKeys.add(key) : _collapsedKeys.remove(key);
    if (changed) notifyListeners();
  }

  /// In [GanttInteractionMode.selectableDrag], the minimum pointer movement,
  /// in pixels, before a press-and-move on a bar counts as a drag rather
  /// than a click. Defaults to 4.0.
  double dragActivationDistance = 4.0;

  /// The number of days currently visible in the chart, if null will be calculated automatically
  int? get daysViews => _daysViews;

  /// Sets the number of visible days and notifies listeners if changed, if set to null will be calculated automatically
  set daysViews(int? value) {
    if (value != _daysViews) {
      _daysViews = value;
      notifyListeners();
    }
  }

  /// When set (scroll mode — on by default, at 40px/day), the chart uses
  /// this fixed pixel width per day — instead of fitting exactly
  /// [daysViews] days into the available width — and scrolls horizontally
  /// for real rather than navigating by dragging to pan. Set to `null` to
  /// opt back into the original fit-to-width/pan behavior.
  double? get fixedDayWidth => _fixedDayWidth;

  /// Sets [fixedDayWidth] and notifies listeners if changed.
  set fixedDayWidth(double? value) {
    if (value != _fixedDayWidth) {
      _fixedDayWidth = value;
      notifyListeners();
    }
  }

  /// Whether the chart is in fixed-day-width scroll mode (see [fixedDayWidth]).
  bool get isScrollMode => _fixedDayWidth != null;

  /// Internal: wires up the [ScrollController] the chart's horizontal
  /// scroll view uses in scroll mode, so [next]/[prev] can drive it. Not for
  /// direct use by consumers.
  void attachHorizontalScrollController(ScrollController? controller) {
    _horizontalScrollController = controller;
  }

  /// Moves the view forward by [days] and optionally fetches new data.
  ///
  /// [days] - Number of days to move forward (default: 1)
  /// [fetchData] - Whether to trigger data fetch (default: true)
  void next({int days = 1, bool fetchData = true}) =>
      _shift(days: days, fetchData: fetchData);

  /// Moves the view backward by [days] and optionally fetches new data.
  ///
  /// [days] - Number of days to move backward (default: 1)
  /// [fetchData] - Whether to trigger data fetch (default: true)
  void prev({int days = 1, bool fetchData = true}) =>
      _shift(days: -days, fetchData: fetchData);

  void _shift({required int days, bool fetchData = true}) {
    final scrollController = _horizontalScrollController;
    if (isScrollMode && scrollController != null && scrollController.hasClients) {
      final position = scrollController.position;
      final target = (position.pixels + days * _fixedDayWidth!).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      startDate = startDate.add(Duration(days: days));
    }
    if (fetchData) {
      fetch();
    }
  }

  /// Forces an update of the chart and fetches new data.
  void update() {
    fetch();
    notifyListeners();
  }

  final List<VoidCallback> _fetchListener = <VoidCallback>[];

  /// Adds a listener to be called when data needs to be fetched.
  void addFetchListener(VoidCallback fn) => _fetchListener.add(fn);

  /// Removes a fetch listener.
  void removeFetchListener(VoidCallback fn) => _fetchListener.remove(fn);

  /// Removes all fetch listeners.
  void removeAllFetchListener() {
    for (var fn in _fetchListener) {
      _fetchListener.remove(fn);
    }
  }

  /// Notifies all fetch listeners to load new data.
  void fetch() {
    for (var fn in _fetchListener) {
      fn();
    }
  }

  @override
  void dispose() {
    removeAllFetchListener();
    super.dispose();
  }

  /// Creates a [GanttController] with optional start date.
  ///
  /// If no [startDate] is provided, defaults to 30 days before today; if no
  /// [minEndDate] is provided, defaults to 30 days after today — so the
  /// chart shows a full ±30-day window around today out of the box.
  GanttController({
    DateTime? startDate,
    DateTime? minEndDate,
    int? daysViews,
    Duration dragStartDelay = kLongPressTimeout,
    GanttTheme? theme,
  }) : _startDate =
           (startDate?.toDate ??
               DateTime.now().toDate.subtract(Duration(days: 30))),
       _minEndDate =
           minEndDate?.toDate ??
           DateTime.now().toDate.add(const Duration(days: 30)),
       _daysViews = daysViews,
       _dragStartDelay = dragStartDelay,
       _theme = theme ?? GanttTheme();

  /// Adds a listener for activity dates changes.
  void addOnActivityChangedListener(GanttActivityOnChangedEvent listener) {
    _onActivityChangedListeners.add(listener);
  }

  /// Removes a listener for activity dates changes.
  void removeOnActivityChangedListener(GanttActivityOnChangedEvent listener) {
    _onActivityChangedListeners.remove(listener);
  }

  /// Gets the list of dates change listeners.
  List<GanttActivityOnChangedEvent> get onActivityChangedListeners =>
      _onActivityChangedListeners;
}
