import 'package:flutter/widgets.dart';

/// Clips [child] to only the area at or below [top] (in [child]'s own
/// coordinate space — this does *not* shift [child]'s layout position, only
/// what gets painted).
///
/// Every chart overlay that tracks row scrolling via `Transform.translate`
/// (`GanttGroupCapsules`, `ChecklistTreeGuides`, `DependencyArrows`,
/// `MarkersOverlay`) needs this: a plain `ClipRect` only clips to its own
/// widget bounds, which span the *entire* chart area including the header —
/// so once scrolled far enough, a translated row can paint over the month/
/// day header above it instead of being hidden by it. This clips to the
/// sub-rect starting at [top] instead, so scrolled content is cut off right
/// at the header's bottom edge, same as [ActivitiesGrid]'s own `ListView`
/// already is (a real `Scrollable` clips to its viewport automatically).
class BelowHeaderClip extends StatelessWidget {
  const BelowHeaderClip({super.key, required this.top, required this.child});

  /// The y-coordinate (in this widget's own space) below which [child] may
  /// paint — typically the calendar header's height.
  final double top;

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ClipRect(clipper: _BelowHeaderClipper(top), child: child);
}

class _BelowHeaderClipper extends CustomClipper<Rect> {
  const _BelowHeaderClipper(this.top);

  final double top;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, top, size.width, size.height);

  @override
  bool shouldReclip(covariant _BelowHeaderClipper oldClipper) =>
      oldClipper.top != top;
}
