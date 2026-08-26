import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../flutter_gantt.dart';
import '../utils/datetime.dart';
import 'controller_extension.dart';

/// Displays the calendar grid portion of the Gantt chart.
///
/// Shows:
/// - Month headers
/// - (Optional) ISO week numbers
/// - Day cells with weekend/holiday highlighting
///
/// This grid appears above the activities grid to provide date context.
class CalendarGrid extends StatelessWidget {
  /// The list of holidays to highlight in the calendar.
  ///
  /// Holidays will be displayed with special background color and tooltips.
  final List<GantDateHoliday>? holidays;

  /// Whether to show the ISO week number row.
  ///
  /// If `true`, a row displaying ISO-8601 week numbers is shown
  /// between the month headers and the day cells.
  final bool showIsoWeek;

  /// A callback used to convert a [DateTime] value into a textual
  /// representation of its month, using the provided [BuildContext].
  ///
  /// If provided, this function overrides the default month-to-text
  /// conversion logic.
  /// If `null`, a fallback or built-in formatter may be used instead.
  final MonthToText? monthToText;

  /// Reports this grid's real total header height after every layout — the
  /// month row plus its divider (plus the week-number row too, when
  /// [showIsoWeek] is on) **plus** the day-number row's own height (see
  /// [_dayNumberSize]/[_dayNumberVerticalPadding]), since that row isn't a
  /// distinct widget of its own here — it's painted at the top of the
  /// (separately unbounded-height) days grid below, not measurable by
  /// walking up from a single render object. [Gantt] uses the reported
  /// total to size the activities-list header and every overlay that
  /// otherwise assumes a fixed `GanttTheme.headerHeight` to match, so
  /// nothing starts drawing bars/rows until *both* header rows have had
  /// their real space, not just the month row's.
  final ValueChanged<double>? onHeaderHeightMeasured;

  /// The day-number circle's diameter, in pixels — see the day cell built in
  /// [build]. Named (not a bare `22`/`4.0` there) so [onHeaderHeightMeasured]
  /// can add up the exact same numbers instead of a separately-maintained
  /// guess that could drift from the real rendering.
  static const double _dayNumberSize = 22.0;

  /// The vertical padding around the day-number circle, in pixels — applied
  /// on both the top and bottom, so the day-number row's total height is
  /// `_dayNumberSize + _dayNumberVerticalPadding * 2`.
  static const double _dayNumberVerticalPadding = 4.0;

  /// Creates a [CalendarGrid] widget.
  ///
  /// [holidays] is optional and can be null when no holiday highlighting is needed.
  /// [showIsoWeek] enables the ISO week-number row (default: `false`).
  const CalendarGrid({
    super.key,
    this.holidays,
    this.showIsoWeek = false,
    this.monthToText,
    this.onHeaderHeightMeasured,
  });

  /// Gets the background color for a specific date based on theme and holidays.
  ///
  /// Returns:
  /// - [GanttTheme.holidayColor] for holidays
  /// - [GanttTheme.weekendColor] for weekends
  /// - [Colors.transparent] for normal weekdays
  Color getDayColor(GanttTheme theme, DateTime date) {
    if ((holidays ?? []).map((e) => e.date).contains(date)) {
      return theme.holidayColor;
    }
    if (date.isWeekend) {
      return theme.weekendColor;
    }
    return Colors.transparent;
  }

  /// Gets the holiday name for a specific date, if any.
  ///
  /// Returns the holiday name if the date matches a holiday in [holidays],
  /// otherwise returns null.
  String? getDayHoliday(DateTime date) {
    final dayHolidays =
        (holidays ?? [])
            .where((e) => e.date.isAtSameMomentAs(date))
            .map((e) => e.holiday)
            .whereType<String>()
            .toList();

    if (dayHolidays.isEmpty) return null;
    if (dayHolidays.length == 1) return dayHolidays.first;

    return dayHolidays.map((h) => '• $h').join('\n');
  }

  /// The header portion: the month row, its divider, and (if [showIsoWeek])
  /// the week-number row — everything above the days grid, *except* the
  /// day-number row (see [onHeaderHeightMeasured] for why that one's added
  /// in separately). Split out from [build] so it can be wrapped in its own
  /// measuring [Builder] there, sized to exactly what it needs
  /// (`mainAxisSize: MainAxisSize.min`) rather than however tall its parent
  /// happens to be.
  Widget _buildHeaderRows(BuildContext context, GanttController c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Month headers row
      Builder(
        builder: (context) {
          final months = c.getMonths(context, monthToText).entries.toList();
          return Row(
            children: List.generate(months.length, (i) {
              final month = months[i];
              return Expanded(
                flex: month.value,
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          month.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.watch<GanttTheme>().textStyle(
                            size: context.watch<GanttTheme>().fontSize + 1,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      color:
                          (i < months.length - 1)
                              ? context.watch<GanttTheme>().dividerColor
                              : Colors.transparent,
                      height: 10,
                    ),
                  ],
                ),
              );
            }),
          );
        },
      ),
      Container(height: 1, color: context.watch<GanttTheme>().dividerColor),
      // Week numbers row
      if (showIsoWeek)
        Builder(
          builder: (context) {
            final weeks = c.weeks.entries.toList();
            return Row(
              children: List.generate(weeks.length, (i) {
                final week = weeks[i];
                return Expanded(
                  flex: week.value,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            'W${week.key}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.watch<GanttTheme>().textStyle(
                              size: 10,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        color:
                            (i < weeks.length - 1)
                                ? context.watch<GanttTheme>().dividerColor
                                : Colors.transparent,
                        height: 10,
                      ),
                    ],
                  ),
                );
              }),
            );
          },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Consumer<GanttController>(
    builder:
        (context, c, child) => Column(
          children: [
            Builder(
              builder: (headerContext) {
                if (onHeaderHeightMeasured != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!headerContext.mounted) return;
                    final box = headerContext.findRenderObject() as RenderBox?;
                    if (box != null && box.hasSize) {
                      // The month/divider/week block's own real height,
                      // *plus* the day-number row it doesn't include (see
                      // this class's doc comment on [onHeaderHeightMeasured]
                      // for why that row can't just be measured the same
                      // way) — the two together are the grid's true total
                      // header height.
                      onHeaderHeightMeasured!(
                        box.size.height +
                            _dayNumberSize +
                            _dayNumberVerticalPadding * 2,
                      );
                    }
                  });
                }
                return _buildHeaderRows(headerContext, c);
              },
            ),
            // Days grid
            Expanded(
              child: Row(
                children: List.generate(c.days.length, (i) {
                  final day = c.days[i];
                  final holiday = getDayHoliday(day);
                  final child = Container(
                    width: _dayNumberSize,
                    height: _dayNumberSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          day.isToday
                              ? context.watch<GanttTheme>().todayBackgroundColor
                              : null,
                    ),
                    child: Text(
                      '${day.day}',
                      style: context.watch<GanttTheme>().textStyle(
                        size: 10,
                        color:
                            day.isToday
                                ? context.watch<GanttTheme>().todayTextColor
                                : null,
                        weight:
                            day.isToday ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  );
                  return Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            color: getDayColor(
                              context.watch<GanttTheme>(),
                              day,
                            ),
                            height: double.infinity,
                            child: Stack(
                              children: [
                                if (day.isToday &&
                                    context
                                            .watch<GanttTheme>()
                                            .todayLineColor !=
                                        null)
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: Container(
                                      width:
                                          context
                                              .watch<GanttTheme>()
                                              .todayLineWidth,
                                      height: double.infinity,
                                      color:
                                          context
                                              .watch<GanttTheme>()
                                              .todayLineColor,
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: _dayNumberVerticalPadding,
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        holiday != null
                                            ? Tooltip(
                                              message: holiday,
                                              child: child,
                                            )
                                            : child,
                                        if (holiday != null)
                                          Positioned(
                                            top: -2,
                                            right: -2,
                                            child: Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color:
                                                    Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          height: double.infinity,
                          width: 1,
                          color:
                              c.dateToHighlight(day)
                                  ? context.watch<GanttTheme>().defaultCellColor
                                  // Fainter than the structural dividers
                                  // (pane/header/frame) — this is a fine
                                  // day-by-day grid line, not a section
                                  // boundary, so it should recede more.
                                  : context
                                      .watch<GanttTheme>()
                                      .dividerColor
                                      .withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
  );
}
