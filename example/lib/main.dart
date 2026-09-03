import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:flutter_gantt/flutter_gantt.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
  }
  runApp(const MyApp());
}

/// This app's own look — flutter_gantt's own defaults are intentionally
/// neutral/generic, so an app that wants a specific design (ours, here)
/// passes it explicitly instead of relying on the package to bake it in.
/// Shared by every `GanttTheme.of(...)` call in this file so the whole demo
/// stays visually consistent.
GanttTheme appGanttTheme(
  BuildContext context, {
  Color? todayLineColor,
  double? todayLineWidth,
}) =>
    GanttTheme.of(
      context,
      backgroundColor: const Color(0xFFFCFCFC),
      holidayColor: const Color(0xFFFFF1E4),
      weekendColor: const Color(0xFFF8F8F8),
      todayBackgroundColor: const Color(0xFF0D90D9),
      defaultCellColor: const Color(0xFF008ECB),
      colorResolver: defaultGanttColorResolver,
      nameWeightForDepth: ganttNameWeightForDepth,
      // Package no longer bundles this — it's this app's own font now (see
      // example/pubspec.yaml's fonts: section and example/assets/fonts/),
      // so it's just the plain family name, not the
      // packages/flutter_gantt/... form a package-bundled font would need.
      fontFamily: 'Montserrat',
      headerHeight: 48,
      rowPadding: 0,
      rowsGroupPadding: 0,
      cellHeight: 48,
      barVerticalPadding: 10,
      chartBorderRadius: 8,
      todayLineColor: todayLineColor,
      todayLineWidth: todayLineWidth ?? 1.5,
    );

/// Main app widget
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flutter Gantt Demo',
        scrollBehavior: AppCustomScrollBehavior(),
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.tealAccent,
            brightness: Brightness.dark,
          ),
        ),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.tealAccent,
            brightness: Brightness.light,
          ),
        ),
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('en'), // English
          Locale('it'), // Italian
        ],
        locale: Locale('en'),
        home: const MyHomePage(title: 'Flutter Gantt'),
      );
}

/// Enable scrolling with various input devices
class AppCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };
}

/// A Subitem's row content: checkbox + name, no date bar — the tree
/// connector line in front of it is drawn automatically by [ActivitiesList]
/// (via `GanttTreeIndent`), since `titleWidget` only replaces the name
/// portion of the row, not the indent ahead of it.
class SubitemChecklistTitle extends StatefulWidget {
  const SubitemChecklistTitle({super.key, required this.label});

  final String label;

  @override
  State<SubitemChecklistTitle> createState() => _SubitemChecklistTitleState();
}

class _SubitemChecklistTitleState extends State<SubitemChecklistTitle> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    // Custom titleWidget content isn't styled by the package automatically
    // (it's arbitrary consumer-supplied UI) — read GanttTheme ourselves so
    // this still matches the chart's own text color instead of falling back
    // to Flutter's ambient default.
    final theme = context.watch<GanttTheme>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _checked,
            onChanged: (value) => setState(() => _checked = value ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            fillColor: WidgetStateProperty.all(Colors.white),
            checkColor: theme.textColor,
            side: BorderSide(color: Colors.grey, width: 1),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: theme
                .textStyle(
                  color:
                      _checked ? theme.textColor.withValues(alpha: 0.5) : null,
                )
                .copyWith(
                  decoration: _checked ? TextDecoration.lineThrough : null,
                ),
          ),
        ),
      ],
    );
  }
}

/// Stand-in for a real app's own User model — swap this for yours; whatever
/// it is, it just needs a `name` to plug into [TaskMeta.assignee].
class User {
  const User(this.name);

  final String name;
}

/// Demo-only task metadata (status/priority/assignee) — not part of
/// [GanttActivity] itself, carried instead via its generic `data` payload.
/// Illustrates attaching arbitrary app data to an activity for use in custom
/// `GanttListColumn.cellBuilder`s, since the package itself stays generic
/// and has no concept of status/priority/assignee. A record, not a class —
/// no constructor to write, just a shape: `(status: ..., assignee: ...)`.
typedef TaskMeta = ({
  DemoTaskStatus status,
  DemoTaskPriority? priority,
  User assignee
});

enum DemoTaskStatus { notStarted, inProgress, completed, overdue }

enum DemoTaskPriority { low, medium, high }

final _taskColorRandom = math.Random();

/// The app decides each Task's color itself — here, at random. Passed to
/// [GanttActivity.withColor] so the whole Task family shares it; the
/// package's default color resolver takes it from there and lightens it
/// per descendant depth.
Color _randomTaskColor() => HSLColor.fromAHSL(
      1,
      _taskColorRandom.nextDouble() * 360,
      0.55 + _taskColorRandom.nextDouble() * 0.15,
      0.5 + _taskColorRandom.nextDouble() * 0.1,
    ).toColor();

Widget _statusGlyph(DemoTaskStatus status) {
  final (icon, color) = switch (status) {
    DemoTaskStatus.notStarted => (Icons.circle_outlined, Colors.grey),
    DemoTaskStatus.inProgress => (
        Icons.access_time_filled,
        const Color(0xFF2F80ED)
      ),
    DemoTaskStatus.completed => (Icons.check, const Color(0xFF2E9E5B)),
    DemoTaskStatus.overdue => (Icons.priority_high, const Color(0xFFE0523B)),
  };
  return Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: Icon(icon, size: 14, color: Colors.white),
  );
}

Widget _priorityCell(DemoTaskPriority? priority, GanttTheme theme) {
  if (priority == null) {
    return Text(
      '—',
      style: theme.textStyle(color: theme.textColor.withValues(alpha: 0.35)),
    );
  }
  final (label, color) = switch (priority) {
    DemoTaskPriority.low => ('Low', Colors.grey),
    DemoTaskPriority.medium => ('Medium', const Color(0xFFE0A020)),
    DemoTaskPriority.high => ('High', const Color(0xFFE0523B)),
  };
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis, style: theme.textStyle())),
    ],
  );
}

Widget _assigneeCell(User assignee, GanttTheme theme) {
  final name = assignee.name;
  final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(
        radius: 12,
        backgroundColor: const Color(0xFFE3A8C4),
        child: Text(
          initial,
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textStyle(weight: FontWeight.w600),
        ),
      ),
    ],
  );
}

/// Home page widget
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final GanttController controller;
  late final List<GanttActivity> _activities;
  late final DateTime _scrollStartDate;
  static final _listDateFormat = DateFormat('dd/MM');

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    // Always show a full ±30-day window around today — matches
    // GanttController's own defaults, spelled out explicitly here.
    _scrollStartDate = now.subtract(const Duration(days: 30));

    controller = GanttController(
      startDate: _scrollStartDate,
      minEndDate: now.add(const Duration(days: 30)),
      //daysViews: 10, // Optional: you can set the number of days to be displayed
    );
    // Scroll mode and selectable drag are both on by default already — the
    // package's own defaults now, not demo toggles.

    controller.addOnActivityChangedListener(_onActivityChanged);
    _activities = [
      // ✅ Main activity with children inside range
      GanttActivity(
        key: 'task1',
        start: now.subtract(const Duration(days: 3)),
        // Widened from +6 to fit Subtask 2/4/3 laid out sequentially below
        // (each starting exactly when the previous ends) instead of the
        // three of them fully overlapping — see their own comments.
        end: now.add(const Duration(days: 15)),
        title: 'Main Task',
        data: const (
          status: DemoTaskStatus.inProgress,
          priority: DemoTaskPriority.high,
          assignee: User('Nguyễn Văn A'),
        ),
        actions: [
          GanttActivityAction(
            icon: Icons.visibility,
            tooltip: 'View',
            onTap: () => debugPrint('Viewing WO-1001'),
          ),
          GanttActivityAction(
            icon: Icons.edit,
            tooltip: 'Edit',
            onTap: () => debugPrint('Editing WO-1001'),
          ),
          GanttActivityAction(
            icon: Icons.delete,
            tooltip: 'Delete',
            onTap: () => debugPrint('Deleting WO-1001'),
          ),
        ],
        children: [
          // GanttActivity(
          //   key: 'task1.sub1',
          //   start: now.subtract(const Duration(days: 2)),
          //   end: now.add(const Duration(days: 1)),
          //   title: 'Subtask 1',
          //   tooltip: 'WO-1001-1 | Subtask',
          //   progress: 0.75,
          //   actions: [
          //     GanttActivityAction(
          //       icon: Icons.check,
          //       tooltip: 'Mark done',
          //       onTap: () => debugPrint('Marking subtask done'),
          //     ),
          //   ],
          // ),
          GanttActivity(
            key: 'task1.sub2',
            start: now,
            end: now.add(const Duration(days: 5)),
            title: 'Subtask 2',
            data: const (
              status: DemoTaskStatus.inProgress,
              priority: DemoTaskPriority.medium,
              assignee: User('Nguyễn Văn A'),
            ),
            actions: [
              GanttActivityAction(
                icon: Icons.add,
                onTap: () => debugPrint('Add nested to WO-1001-2'),
              ),
            ],
            children: [
              // Subitems (2nd-level nesting) render as a checklist row —
              // checkbox + name, no date bar — not a scaled-down copy of
              // the Task/Subtask bar. showCell: false stops GanttActivityRow
              // from mounting any drag gesture for it (structurally, not
              // just visually), and titleWidget supplies the checkbox+name;
              // the tree connector line ahead of it still comes from
              // ActivitiesList's own indent, unaffected by titleWidget.
              GanttActivity(
                key: 'task1.sub2.subA',
                start: now.add(const Duration(days: 1)),
                end: now.add(const Duration(days: 3)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask A',
                ),
                // Only consulted by the demo's own list-column cellBuilders
                // below — lets the list pane(s) show plain text like every
                // other row, while the chart pane still shows the checkbox
                // via titleWidget.
                listTitle: 'Nested Subtask A',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.completed,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
              GanttActivity(
                key: 'task1.sub2.subB',
                start: now.add(const Duration(days: 2)),
                end: now.add(const Duration(days: 4)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask B',
                ),
                listTitle: 'Nested Subtask B',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
              GanttActivity(
                key: 'task1.sub2.subC',
                start: now.add(const Duration(days: 2)),
                end: now.add(const Duration(days: 4)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask C',
                ),
                listTitle: 'Nested Subtask C',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
            ],
          ),
          GanttActivity(
            key: 'task1.sub4',
            // Starts exactly when Subtask 2 ends — sequential, not
            // overlapping, like Subtask 3 below it.
            start: now.add(const Duration(days: 5)),
            end: now.add(const Duration(days: 10)),
            title: 'Subtask 4',
            data: const (
              status: DemoTaskStatus.inProgress,
              priority: DemoTaskPriority.medium,
              assignee: User('Nguyễn Văn A'),
            ),
            actions: [
              GanttActivityAction(
                icon: Icons.add,
                onTap: () => debugPrint('Add nested to WO-1001-2'),
              ),
            ],
            children: [
              // Subitems (2nd-level nesting) render as a checklist row —
              // checkbox + name, no date bar — not a scaled-down copy of
              // the Task/Subtask bar. showCell: false stops GanttActivityRow
              // from mounting any drag gesture for it (structurally, not
              // just visually), and titleWidget supplies the checkbox+name;
              // the tree connector line ahead of it still comes from
              // ActivitiesList's own indent, unaffected by titleWidget.
              GanttActivity(
                key: 'task1.sub4.subA',
                start: now.add(const Duration(days: 6)),
                end: now.add(const Duration(days: 8)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask A4',
                ),
                // Only consulted by the demo's own list-column cellBuilders
                // below — lets the list pane(s) show plain text like every
                // other row, while the chart pane still shows the checkbox
                // via titleWidget.
                listTitle: 'Nested Subtask A4',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.completed,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
              GanttActivity(
                key: 'task1.sub4.subB',
                start: now.add(const Duration(days: 7)),
                end: now.add(const Duration(days: 9)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask B4',
                ),
                listTitle: 'Nested Subtask B4',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
              GanttActivity(
                key: 'task1.sub4.subC',
                start: now.add(const Duration(days: 7)),
                end: now.add(const Duration(days: 9)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask C4',
                ),
                listTitle: 'Nested Subtask C4',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
            ],
          ),
          GanttActivity(
            key: 'task1.sub3',
            // Starts exactly when Subtask 4 ends — sequential, not
            // overlapping. Was `now`/`now+5`, fully overlapping Subtask 2 —
            // which is exactly why the dependsOn arrow below used to draw a
            // backwards/degenerate elbow instead of a clean forward one:
            // the arrow's math assumes the source (Subtask 2) finishes
            // before the target (this) starts, same as QV's own.
            start: now.add(const Duration(days: 10)),
            end: now.add(const Duration(days: 15)),
            title: 'Subtask 3',
            // Was 'task1.sub1' — an activity that got commented out above,
            // so this dependency silently never drew (DependencyArrows
            // skips a dependsOn key it can't find, rather than erroring).
            // Points at an activity that actually exists now.
            dependsOn: const ['task1.sub2'],
            data: const (
              status: DemoTaskStatus.notStarted,
              priority: DemoTaskPriority.low,
              assignee: User('Nguyễn Văn A'),
            ),
            actions: [
              GanttActivityAction(
                icon: Icons.add,
                onTap: () => debugPrint('Add nested to WO-1001-2'),
              ),
            ],
            children: [
              // Subitems (2nd-level nesting) render as a checklist row —
              // checkbox + name, no date bar — not a scaled-down copy of
              // the Task/Subtask bar. showCell: false stops GanttActivityRow
              // from mounting any drag gesture for it (structurally, not
              // just visually), and titleWidget supplies the checkbox+name;
              // the tree connector line ahead of it still comes from
              // ActivitiesList's own indent, unaffected by titleWidget.
              GanttActivity(
                key: 'task1.sub3.subA',
                start: now.add(const Duration(days: 11)),
                end: now.add(const Duration(days: 13)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask A3',
                ),
                listTitle: 'Nested Subtask A3',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
              GanttActivity(
                key: 'task1.sub3.subB',
                start: now.add(const Duration(days: 12)),
                end: now.add(const Duration(days: 14)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask B3',
                ),
                listTitle: 'Nested Subtask B3',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
            ],
          ),
        ],
        // The app decides this Task's color itself (here, at random) and
        // withColor propagates it to every descendant below — the default
        // resolver lightens it further per depth, so the whole family
        // still reads as one color that fades, not an unrelated hue per
        // row. task2/task4 below each get their own random color the same
        // way, to stand apart as their own color families.
      ).withColor(_randomTaskColor()),

      // ✅ Standalone task near today
      GanttActivity(
        key: 'task2',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 8)),
        title: 'Independent Task',
        data: const (
          status: DemoTaskStatus.inProgress,
          priority: DemoTaskPriority.medium,
          assignee: User('Nguyễn Văn A'),
        ),
        children: [
          GanttActivity(
            key: 'task2.sub1',
            start: now.add(const Duration(days: 1)),
            end: now.add(const Duration(days: 4)),
            title: 'Subtask 2.1',
            data: const (
              status: DemoTaskStatus.inProgress,
              priority: DemoTaskPriority.medium,
              assignee: User('Nguyễn Văn A'),
            ),
            children: [
              GanttActivity(
                key: 'task2.sub1.subA',
                start: now.add(const Duration(days: 2)),
                end: now.add(const Duration(days: 3)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask 2.1A',
                ),
                listTitle: 'Nested Subtask 2.1A',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
            ],
          ),
          GanttActivity(
            key: 'task2.sub2',
            start: now.add(const Duration(days: 4)),
            end: now.add(const Duration(days: 8)),
            title: 'Subtask 2.2',
            data: const (
              status: DemoTaskStatus.notStarted,
              priority: DemoTaskPriority.low,
              assignee: User('Nguyễn Văn A'),
            ),
          ),
        ],
      ).withColor(_randomTaskColor()),

      // ✅ Activity a few days ago
      GanttActivity(
        key: 'task4',
        start: now.subtract(const Duration(days: 10)),
        end: now.subtract(const Duration(days: 4)),
        title: 'Older Task',
        progress: 1.0,
        data: const (
          status: DemoTaskStatus.completed,
          priority: DemoTaskPriority.low,
          assignee: User('Nguyễn Văn A'),
        ),
      ).withColor(_randomTaskColor()),
    ];
  }

  void _onActivityChanged(
    GanttActivity activity,
    DateTime? start,
    DateTime? end,
  ) {
    if (start != null && end != null) {
      debugPrint('$activity was moved (Event on controller)');
    } else if (start != null) {
      debugPrint('$activity start was moved (Event on controller)');
    } else if (end != null) {
      debugPrint('$activity end was moved (Event on controller)');
    }
  }

  @override
  void dispose() {
    controller.removeOnActivityChangedListener(_onActivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
        ),
        body: Column(
          children: [
            GanttRangeSelector(controller: controller),
            Expanded(
              child: Gantt(
                theme: appGanttTheme(
                  context,
                  todayLineColor: Colors.blue,
                  todayLineWidth: 2,
                ),
                //monthToText: (context, date) => 'Month: ${date.month}', //this function overrides the default month-to-text
                controller: controller,
                activitiesAsync: (startDate, endDate, activity) async =>
                    _activities,
                //showIsoWeek: true,
                showTreeGuides: true,
                showGroupCapsules: true,
                // Package defaults to longPressDrag/false (unchanged from
                // before either option existed) — this demo opts into the
                // click-to-select drag mode and lets a parent's own bar move
                // independently of its children's current dates.
                interactionMode: GanttInteractionMode.selectableDrag,
                allowParentIndependentDateMovement: true,
                listColumns: [
                  GanttListColumn(
                    header: 'Task Summary',
                    flex: 3,
                    cellBuilder: (context, activity) => Text(
                      activity.listTitle ?? activity.title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.watch<GanttTheme>().textStyle(
                            weight: ganttNameWeightForDepth(activity.depth),
                          ),
                    ),
                  ),
                  GanttListColumn(
                    header: 'Status',
                    flex: 1,
                    cellBuilder: (context, activity) {
                      final meta = activity.data as TaskMeta?;
                      return meta == null
                          ? const SizedBox.shrink()
                          : _statusGlyph(meta.status);
                    },
                  ),
                  GanttListColumn(
                    header: 'Priority',
                    flex: 1,
                    cellBuilder: (context, activity) => _priorityCell(
                      (activity.data as TaskMeta?)?.priority,
                      context.watch<GanttTheme>(),
                    ),
                  ),
                  // GanttListColumn(
                  //   header: 'Start',
                  //   flex: 2,
                  //   cellBuilder:
                  //       (context, activity) => Text(
                  //         _listDateFormat.format(activity.start),
                  //         style: context.watch<GanttTheme>().textStyle(),
                  //       ),
                  // ),
                  // GanttListColumn(
                  //   header: 'End',
                  //   flex: 2,
                  //   cellBuilder:
                  //       (context, activity) => Text(
                  //         _listDateFormat.format(activity.end),
                  //         style: context.watch<GanttTheme>().textStyle(),
                  //       ),
                  // ),
                  GanttListColumn(
                    header: 'Assignee',
                    flex: 3,
                    cellBuilder: (context, activity) {
                      final meta = activity.data as TaskMeta?;
                      return meta == null
                          ? const SizedBox.shrink()
                          : _assigneeCell(
                              meta.assignee,
                              context.watch<GanttTheme>(),
                            );
                    },
                  ),
                ],
                markers: [
                  GanttMarker(
                    key: 'milestone1',
                    date: _activities.first.start.add(const Duration(days: 5)),
                    activityKey: 'task1',
                    tooltip: 'Milestone: mid-project checkpoint',
                    onTap: () => debugPrint('Marker tapped'),
                  ),
                ],
                // holidaysAsync: (startDate, endDate, holidays) async {},
                activitiesListFlex: 3,
                gridAreaFlex: 4,
                onColumnWidthsChanged: (ratios) =>
                    debugPrint('New ratios: $ratios'),
                onPeekChildrenTap: (activity, position) {
                  final children = activity.children ?? const [];
                  if (children.isEmpty) return;
                  // showMenu pushes its route on the app's root Navigator —
                  // outside Gantt's own provider subtree — so a titleWidget
                  // reading GanttTheme/GanttController via context (like
                  // SubitemChecklistTitle does) can't find them there unless
                  // re-provided here. Same fix the package's own drag-
                  // feedback overlay uses (see SelectableBarGesture).
                  showMenu<void>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      position.dx,
                      position.dy,
                      position.dx,
                      position.dy,
                    ),
                    // The app is in dark ThemeMode, but the chart itself is
                    // styled light (GanttTheme) — an explicit light color/
                    // shape here keeps the popup matching the chart it
                    // popped out of, instead of the ambient dark Material
                    // menu style clashing with it.
                    color: Colors.white,
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 200),
                    items: [
                      for (final child in children)
                        PopupMenuItem<void>(
                          enabled: false,
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          // Reuses each child's own titleWidget (the
                          // checkbox for a Subitem, same as ActivitiesList
                          // shows it) rather than inventing separate popup
                          // content — a quick peek at what's already there.
                          // Theme.light overrides the app's own dark
                          // ThemeMode just for this popup, so the Checkbox
                          // (a Material widget, not GanttTheme-styled)
                          // renders for a light background too.
                          child: Theme(
                            data: ThemeData.light(),
                            child: MultiProvider(
                              providers: [
                                // GanttController extends ChangeNotifier —
                                // plain Provider.value asserts against that
                                // (it wouldn't know how to update
                                // dependents), so this needs
                                // ChangeNotifierProvider instead.
                                ChangeNotifierProvider<GanttController>.value(
                                  value: controller,
                                ),
                                Provider<GanttTheme>.value(
                                  value: appGanttTheme(
                                    context,
                                    todayLineColor: Colors.blue,
                                    todayLineWidth: 2,
                                  ),
                                ),
                              ],
                              child: child.titleWidget ??
                                  Text(child.listTitle ?? child.title ?? ''),
                            ),
                          ),
                        ),
                    ],
                  );
                },
                onActivityChanged: (activity, start, end) {
                  if (start != null && end != null) {
                    debugPrint('$activity was moved (Event on widget)');
                  } else if (start != null) {
                    debugPrint(
                      '$activity start was moved (Event on widget)',
                    );
                  } else if (end != null) {
                    debugPrint('$activity end was moved (Event on widget)');
                  }
                  // A whole-bar move (both dates shift, not a resize of
                  // just one edge) on an activity with children carries
                  // every descendant along by the same number of days —
                  // otherwise dragging a Task leaves its Subtasks/Subitems
                  // behind at their old dates. `activity.start` here is
                  // still the *old* value (mutated below), so this has to
                  // run before that assignment.
                  //kéo cha - con bên trong move theo
                  if (start != null && end != null) {
                    final deltaDays = start.difference(activity.start).inDays;
                    if (deltaDays != 0) {
                      for (final descendant
                          in activity.children?.plainList ?? const []) {
                        descendant.start = descendant.start.add(
                          Duration(days: deltaDays),
                        );
                        descendant.end = descendant.end.add(
                          Duration(days: deltaDays),
                        );
                      }
                    }
                  } else if (start != null) {
                    // Resize of just the start edge: the package lets this
                    // shrink past a descendant's own start (see
                    // allowParentIndependentDateMovement) instead of
                    // refusing the drag — so a Subitem left outside the
                    // Subtask's new range gets pulled in to match here,
                    // rather than rendering before/outside its own parent.
                    for (final descendant
                        in activity.children?.plainList ?? const []) {
                      if (descendant.start.isBefore(start)) {
                        descendant.start = start;
                        if (descendant.end.isBefore(descendant.start)) {
                          descendant.end = descendant.start;
                        }
                      }
                    }
                  } else if (end != null) {
                    // Same as above, for the end edge.
                    for (final descendant
                        in activity.children?.plainList ?? const []) {
                      if (descendant.end.isAfter(end)) {
                        descendant.end = end;
                        if (descendant.start.isAfter(descendant.end)) {
                          descendant.start = descendant.end;
                        }
                      }
                    }
                  }
                  if (start != null) {
                    _activities.getFromKey(activity.key)!.start = start;
                  }
                  if (end != null) {
                    _activities.getFromKey(activity.key)!.end = end;
                  }
                  controller.update();
                },
              ),
            ),
          ],
        ),
      );
}
