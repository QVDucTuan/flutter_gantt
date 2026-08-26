import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../classes/activity.dart';
import '../classes/theme.dart';
import '../utils/datetime.dart';
import 'controller.dart';
import 'controller_extension.dart';

const Object _tapRegionGroupId = 'flutter_gantt_selectable_bars';

enum _DragMode { move, resizeStart, resizeEnd }

/// Click-to-select drag/resize for a single activity bar.
///
/// Clicking the bar body selects it (revealing resize handles) or, if
/// already selected, deselects it; clicking anywhere else deselects it too.
/// Dragging the bar body moves it; dragging a handle resizes it. Both show a
/// floating date tooltip while active and reposition live, snapping to day
/// boundaries only on release. Used when [GanttController.interactionMode]
/// is [GanttInteractionMode.selectableDrag] — see [GanttActivityRow] for the
/// default long-press mode this replaces.
///
/// Tracking is done via raw pointer events ([Listener]), not
/// [GestureDetector]'s pan callbacks — those only fire once movement
/// exceeds Flutter's built-in ~36px pan slop, which would silently swallow
/// every ordinary click (a click's movement is well under that) before this
/// widget's own click-vs-drag logic ever saw it.
class SelectableBarGesture extends StatefulWidget {
  /// The activity this bar represents.
  final GanttActivity activity;

  /// The per-row controller providing this row's live geometry.
  final GanttActivityCtrl ctrl;

  /// The already-built visual bar content (independent of drag mechanism).
  final Widget cell;

  /// Creates a [SelectableBarGesture] wrapping [cell] for [activity].
  const SelectableBarGesture({
    super.key,
    required this.activity,
    required this.ctrl,
    required this.cell,
  });

  @override
  State<SelectableBarGesture> createState() => _SelectableBarGestureState();
}

class _SelectableBarGestureState extends State<SelectableBarGesture> {
  int? _activePointer;
  Offset? _dragStart;
  Offset _pointerGlobal = Offset.zero;
  bool _dragging = false;
  _DragMode? _mode;
  int? _daysDelta;
  OverlayEntry? _tooltipEntry;

  GanttController get _controller => widget.ctrl.controller;
  bool get _isSelected =>
      _controller.selectedActivityKey == widget.activity.key;

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event, _DragMode mode) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _dragStart = event.position;
    _pointerGlobal = event.position;
    _mode = mode;
    _daysDelta = 0;
    // Resize handles are only shown once selected, so any handle drag is
    // deliberate — no dead-zone. A body drag still needs one, to
    // distinguish a click (toggle selection) from a move.
    _dragging = mode != _DragMode.move;
    if (_dragging) _showTooltip();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _pointerGlobal = event.position;
    final dx = _pointerGlobal.dx - _dragStart!.dx;
    if (!_dragging) {
      if (dx.abs() < _controller.dragActivationDistance) return;
      _dragging = true;
      _showTooltip();
    }

    final ctrl = widget.ctrl;
    final activity = widget.activity;
    final daysDeltaTemp = (dx / ctrl.dayColumnWidth).round();
    // Deliberately NOT bounded to the currently rendered date range — a
    // task near the edge of the visible window must still be draggable
    // earlier/later than what happens to be on screen right now. build()
    // below clamps the resulting pixel widths instead, so going past the
    // rendered edge just clips visually rather than crashing.
    final valid = switch (_mode!) {
      _DragMode.move =>
        activity.validMove(daysDeltaTemp) ||
            (_controller.allowParentIndependentDateMovement &&
                activity.validMoveToParent(daysDeltaTemp)),
      _DragMode.resizeStart =>
        ctrl.cellVisibleDays - daysDeltaTemp > 0 &&
            (activity.validStartMove(daysDeltaTemp) ||
                (_controller.allowParentIndependentDateMovement &&
                    activity.validStartMoveIgnoringChildren(daysDeltaTemp))),
      _DragMode.resizeEnd =>
        ctrl.cellVisibleDays + daysDeltaTemp > 0 &&
            (activity.validEndMove(daysDeltaTemp) ||
                (_controller.allowParentIndependentDateMovement &&
                    activity.validEndMoveIgnoringChildren(daysDeltaTemp))),
    };
    if (valid) {
      setState(() => _daysDelta = daysDeltaTemp);
      _tooltipEntry?.markNeedsBuild();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _endInteraction();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    // A cancelled gesture (e.g. an ancestor scroll took over) commits
    // nothing — just reset, don't treat it as a click either.
    _hideTooltip();
    setState(() {
      _dragging = false;
      _mode = null;
      _daysDelta = null;
    });
  }

  void _endInteraction() {
    _hideTooltip();
    final mode = _mode;
    final delta = _daysDelta;
    final wasDragging = _dragging;
    setState(() {
      _dragging = false;
      _mode = null;
      _daysDelta = null;
    });

    if (!wasDragging) {
      // A plain click: select if not already selected, else deselect.
      _controller.selectedActivityKey =
          _isSelected ? null : widget.activity.key;
      return;
    }
    if (mode == null || delta == null || delta == 0) return;
    final activity = widget.activity;
    switch (mode) {
      case _DragMode.move:
        _controller.onActivityChanged(
          activity,
          start: activity.start.addDays(delta),
          end: activity.end.addDays(delta),
        );
      case _DragMode.resizeStart:
        _controller.onActivityChanged(
          activity,
          start: activity.start.addDays(delta),
        );
      case _DragMode.resizeEnd:
        _controller.onActivityChanged(
          activity,
          end: activity.end.addDays(delta),
        );
    }
  }

  DateTime get _liveStart {
    final delta = _daysDelta ?? 0;
    if (_mode == _DragMode.move || _mode == _DragMode.resizeStart) {
      return widget.activity.start.addDays(delta);
    }
    return widget.activity.start;
  }

  DateTime get _liveEnd {
    final delta = _daysDelta ?? 0;
    if (_mode == _DragMode.move || _mode == _DragMode.resizeEnd) {
      return widget.activity.end.addDays(delta);
    }
    return widget.activity.end;
  }

  String _formatDate(DateTime date) {
    final format = _controller.theme.dragTooltipDateFormat;
    if (format != null) return format(date);
    final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag();
    return DateFormat.yMd(locale).format(date);
  }

  void _showTooltip() {
    if (_tooltipEntry != null) return;
    _tooltipEntry = OverlayEntry(
      builder: (context) {
        final startActive = _mode != _DragMode.resizeEnd;
        final endActive = _mode != _DragMode.resizeStart;
        return Positioned(
          left: _pointerGlobal.dx + 14,
          top: _pointerGlobal.dy - 10,
          child: IgnorePointer(
            child: Material(
              elevation: 4,
              color: Colors.black87,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: startActive ? 1 : 0.45,
                      child: Text(
                        _formatDate(_liveStart),
                        style: _controller.theme.textStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      '  →  ',
                      style: _controller.theme.textStyle(
                        color: Colors.white70,
                      ),
                    ),
                    Opacity(
                      opacity: endActive ? 1 : 0.45,
                      child: Text(
                        _formatDate(_liveEnd),
                        style: _controller.theme.textStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_tooltipEntry!);
  }

  void _hideTooltip() {
    _tooltipEntry?.remove();
    _tooltipEntry = null;
  }

  Widget _handle(GanttTheme theme, {required bool isStart}) => Positioned(
    left: isStart ? -7 : null,
    right: isStart ? null : -7,
    top: 0,
    bottom: 0,
    width: 14,
    child: Center(
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: Listener(
          onPointerDown:
              (e) => _onPointerDown(
                e,
                isStart ? _DragMode.resizeStart : _DragMode.resizeEnd,
              ),
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: theme.defaultCellColor, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 2),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<GanttTheme>();
    final ctrl = widget.ctrl;
    final delta = _daysDelta ?? 0;

    final startOffset =
        _mode == _DragMode.resizeStart ? delta * ctrl.dayColumnWidth : 0.0;
    final endOffset =
        _mode == _DragMode.resizeEnd ? delta * ctrl.dayColumnWidth : 0.0;
    final moveOffset =
        _mode == _DragMode.move ? delta * ctrl.dayColumnWidth : 0.0;

    final barBody = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (e) => _onPointerDown(e, _DragMode.move),
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: widget.cell,
      ),
    );

    final content = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        barBody,
        if (_isSelected) _handle(theme, isStart: true),
        if (_isSelected) _handle(theme, isStart: false),
      ],
    );

    return Row(
      children: [
        SizedBox(
          // Clamped, not the delta itself — dragging past the rendered
          // edge keeps tracking the pointer and still commits the real
          // date on release, it just can't draw further left than 0.
          width: (ctrl.spaceBefore + startOffset + moveOffset).clamp(
            0.0,
            double.infinity,
          ),
          child: const SizedBox(),
        ),
        SizedBox(
          width: ctrl.cellVisibleWidth - startOffset + endOffset,
          child: TapRegion(
            groupId: _tapRegionGroupId,
            onTapOutside: (_) => _controller.selectedActivityKey = null,
            child: content,
          ),
        ),
      ],
    );
  }
}
