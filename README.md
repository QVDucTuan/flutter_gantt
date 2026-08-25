# Flutter Gantt Chart

[![Pub Version](https://img.shields.io/pub/v/flutter_gantt)](https://pub.dev/packages/flutter_gantt) [![Pub Points](https://img.shields.io/pub/points/flutter_gantt)](https://pub.dev/packages/flutter_gantt/score) [![License](https://img.shields.io/github/license/insideapp-srl/flutter_gantt)](https://github.com/insideapp-srl/flutter_gantt/blob/main/LICENSE)

A production-ready, fully customizable Gantt chart widget for Flutter applications.

![Gantt Chart Demo](https://raw.githubusercontent.com/insideapp-srl/flutter_gantt/main/doc/static/img/preview.gif)

---

## Features

- 💓 Scrollable timeline view
- ↔  Draggable
- 🎈 Complete visual customization
- 🛳  Hierarchical activities with parent/child relationships
- 🙳  Activity custom builder
- 👅 Built-in date utilities and calculations
- 🚀 Optimized for performance
- 😱 Responsive across all platforms

---

## Installation

Add to your `pubspec.yaml`:

`yaml
dependencies:
  flutter_gantt: <latest-version>
`

Then run:

`bash
flutter pub get
`

---

## Quick Start

```dart
import 'package:flutter_gantt/flutter_gantt.dart';

Gantt(
  theme: GanttTheme.of(context),
  activitiesAsync: (startDate, endDate, activity) async => _activities,
  holidaysAsync: (startDate, endDate, holidays) async _holidays,
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
  },
),
```

---

## Documentation

### Core Components

#### `Gantt` Widget

The main chart container with these key properties:

| Property      | Type                   | Description                     |
|---------------|------------------------|---------------------------------|
| `startDate`   | DateTime               | Initial visible date            |
| `activities`  | List<GanttActivity>    | Activities to display           |
| `holidays`    | List<GanttDateHoliday> | Special dates to highlight      |
| `theme`       | GanttTheme             | Visual customization            |
| `controller`  | GanttController        | Programmatic control            |
| `showIsoWeek` | bool                   | Enables the ISO week-number row |

#### `GanttActivity`

Represents a task with:

```dart
GanttActivity(
  start: DateTime.now(),
  end: DateTime.now().add(Duration(days: 5)),
  title: 'Task Name',
  color: Colors.blue,
  // Optional:
  children: [/* sub-tasks */],
  onCellTap: (activity) => print('Tapped ${activity.title}'),
)
```

---

### Advanced Features

#### Programmatic Control

```dart
final controller = GanttController(
    startDate: DateTime.now(),
    daysViews: 30,
);

// Navigate timeline
controller.next(days: 7);   // Move forward
controller.prev(days: 14);  // Move backward

// Update data
controller.setActivities(newActivities);
```

#### Custom Builders

```dart
GanttActivity(
  cellBuilder: (date) => YourCustomWidget(date),
  titleWidget: YourTitleWidget(),
)
```

#### Extending with your own data (status, priority, assignee, checklist rows...)

`flutter_gantt` stays fully generic — it has no concept of a task's status, priority, or
assignee. Two extension points let an app add those without forking the package; the package
itself never reads either, it just carries them through to your own rendering code.

**1. Attach your own data via `GanttActivity<T>.data`**

```dart
// Your own type — the package never inspects it. A record works fine, so
// does a class.
typedef TaskMeta = ({TaskStatus status, TaskPriority? priority, User assignee});

GanttActivity(
  key: 'task1',
  start: DateTime.now(),
  end: DateTime.now().add(const Duration(days: 5)),
  title: 'Design review',
  data: (status: TaskStatus.inProgress, priority: TaskPriority.high, assignee: currentUser),
)
```

**2. Read it back in a `GanttListColumn.cellBuilder`**

```dart
Gantt(
  listColumns: [
    GanttListColumn(header: 'Task', flex: 3, cellBuilder: (context, a) => Text(a.title ?? '')),
    GanttListColumn(
      header: 'Status',
      cellBuilder: (context, a) {
        final meta = a.data as TaskMeta?;
        return meta == null ? const SizedBox.shrink() : StatusGlyph(meta.status);
      },
    ),
  ],
)
```

Every `cellBuilder`/`builder` you supply receives the plain `GanttActivity` — casting
`activity.data as YourType?` is how you get your fields back. The same `data` payload also
drives per-activity styling if you want it to (e.g. a `colorResolver` that picks a bar color
from `activity.data`).

The same idea makes a "checklist row" work: set `showCell: false` on an activity and supply
`titleWidget:` (a checkbox + name, say) instead of `title:` — the row keeps its dates (for
dependency arrows/group capsules) but renders as plain content instead of a bar, and can't be
dragged. See `example/lib/main.dart`'s `SubitemChecklistTitle`/`TaskMeta`/`User` for a
complete, runnable version of both patterns.

#### ISO Weeks

```dart
GanttActivity(
  showIsoWeek: true,
  ...
)
```

![Weeks](https://raw.githubusercontent.com/insideapp-srl/flutter_gantt/main/doc/static/img/show_weeks.png)

---

## Examples

[Explore complete examples](https://github.com/insideapp-srl/flutter_gantt/tree/main/example) in the example folder.

---

## Contributing

We welcome contributions!

---

## License

MIT – See [LICENSE](LICENSE) for details.

## Roadmap

- Added limitations when dragging
- Improving documentation
- Improving mobile usability