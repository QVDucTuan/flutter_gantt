import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_gantt/flutter_gantt.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

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
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyle(
              color: _checked ? theme.textColor.withValues(alpha: 0.5) : null,
            ).copyWith(
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
typedef TaskMeta =
    ({DemoTaskStatus status, DemoTaskPriority? priority, User assignee});

enum DemoTaskStatus { notStarted, inProgress, completed, overdue }

enum DemoTaskPriority { low, medium, high }

Widget _statusGlyph(DemoTaskStatus status) {
  final (icon, color) = switch (status) {
    DemoTaskStatus.notStarted => (Icons.circle_outlined, Colors.grey),
    DemoTaskStatus.inProgress => (Icons.access_time_filled, const Color(0xFF2F80ED)),
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
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: theme.textStyle())),
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

    // Scroll mode needs the canvas to start early enough to cover every demo
    // activity (the earliest, "Older Task", starts 10 days ago) — a couple
    // days of buffer, not a whole extra month of empty columns.
    _scrollStartDate = now.subtract(const Duration(days: 12));

    controller = GanttController(
      startDate: _scrollStartDate,
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
        end: now.add(const Duration(days: 6)),
        title: 'Main Task',
        tooltip: 'WO-1001 | Top-level task across multiple days',
        // No explicit color: falls back to the package's default green
        // color family (see GanttTheme.colorResolver /
        // defaultGanttColorResolver) so every activity here reads as one
        // consistent hue instead of an arbitrary color per row.
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
            tooltip: 'WO-1001-2 | Subtask with nested children',
            dependsOn: const ['task1.sub1'],
            data: const (
              status: DemoTaskStatus.inProgress,
              priority: DemoTaskPriority.medium,
              assignee: User('Nguyễn Văn A'),
            ),
            actions: [
              GanttActivityAction(
                icon: Icons.add,
                tooltip: 'Add nested task',
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
                tooltip: 'WO-1001-2A | Second-level task',
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
                tooltip: 'WO-1001-2B | Continued',
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
                tooltip: 'WO-1001-2B | Continued',
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
            start: now,
            end: now.add(const Duration(days: 5)),
            title: 'Subtask 3',
            tooltip: 'WO-1001-2 | Subtask with nested children',
            dependsOn: const ['task1.sub1'],
            data: const (
              status: DemoTaskStatus.notStarted,
              priority: DemoTaskPriority.low,
              assignee: User('Nguyễn Văn A'),
            ),
            actions: [
              GanttActivityAction(
                icon: Icons.add,
                tooltip: 'Add nested task',
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
                start: now.add(const Duration(days: 1)),
                end: now.add(const Duration(days: 3)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask A3',
                ),
                listTitle: 'Nested Subtask A3',
                tooltip: 'WO-1001-2A | Second-level task',
                showCell: false,
                data: const (
                  status: DemoTaskStatus.notStarted,
                  priority: null,
                  assignee: User('Nguyễn Văn A'),
                ),
              ),
              GanttActivity(
                key: 'task1.sub3.subB',
                start: now.add(const Duration(days: 2)),
                end: now.add(const Duration(days: 4)),
                titleWidget: const SubitemChecklistTitle(
                  label: 'Nested Subtask B3',
                ),
                listTitle: 'Nested Subtask B3',
                tooltip: 'WO-1001-2B | Continued',
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
      ),

      // ✅ Standalone task near today
      GanttActivity(
        key: 'task2',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 8)),
        title: 'Independent Task',
        tooltip: 'A separate task',
        data: const (
          status: DemoTaskStatus.inProgress,
          priority: DemoTaskPriority.medium,
          assignee: User('Nguyễn Văn A'),
        ),
      ),

      // ✅ Activity a few days ago
      GanttActivity(
        key: 'task4',
        start: now.subtract(const Duration(days: 10)),
        end: now.subtract(const Duration(days: 4)),
        title: 'Older Task',
        tooltip: 'Past task',
        progress: 1.0,
        data: const (
          status: DemoTaskStatus.completed,
          priority: DemoTaskPriority.low,
          assignee: User('Nguyễn Văn A'),
        ),
      ),

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
                theme: GanttTheme.of(
                  context,
                  todayLineColor: Colors.blue,
                  todayLineWidth: 2,
                  // colorResolver left unset: uses the package's own default
                  // (defaultGanttColorResolver) — a single green family,
                  // lightened by depth.
                ),
                //monthToText: (context, date) => 'Month: ${date.month}', //this function overrides the default month-to-text
                controller: controller,
                activitiesAsync: (startDate, endDate, activity) async =>
                    _activities,
                //showIsoWeek: true,
                showTreeGuides: true,
                showGroupCapsules: true,
                listColumns: [
                  GanttListColumn(
                    header: 'Task Summary',
                    flex: 3,
                    cellBuilder:
                        (context, activity) => Text(
                          activity.listTitle ?? activity.title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.watch<GanttTheme>().textStyle(),
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
                    cellBuilder:
                        (context, activity) => _priorityCell(
                          (activity.data as TaskMeta?)?.priority,
                          context.watch<GanttTheme>(),
                        ),
                  ),
                  GanttListColumn(
                    header: 'Start',
                    flex: 2,
                    cellBuilder:
                        (context, activity) => Text(
                          _listDateFormat.format(activity.start),
                          style: context.watch<GanttTheme>().textStyle(),
                        ),
                  ),
                  GanttListColumn(
                    header: 'End',
                    flex: 2,
                    cellBuilder:
                        (context, activity) => Text(
                          _listDateFormat.format(activity.end),
                          style: context.watch<GanttTheme>().textStyle(),
                        ),
                  ),
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
                  // GanttMarker(
                  //   key: 'milestone1',
                  //   date: _activities.first.start.add(const Duration(days: 5)),
                  //   activityKey: 'task1',
                  //   tooltip: 'Milestone: mid-project checkpoint',
                  //   onTap: () => debugPrint('Marker tapped'),
                  // ),
                ],
                // holidaysAsync: (startDate, endDate, holidays) async {},
                activitiesListFlex: 4,
                gridAreaFlex: 4,
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