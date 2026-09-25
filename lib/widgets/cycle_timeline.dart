import 'package:flutter/material.dart';

import '../alarm_cycles.dart';
import '../models/alarm.dart';
import '../theme.dart';

/// A thin bar. Each mark is a stretch when this condition was in alarm.
class CycleTimelineBar extends StatelessWidget {
  const CycleTimelineBar({
    super.key,
    required this.cycles,
    required this.now,
  });

  final List<Alarm> cycles;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      height: 10,
      width: double.infinity,
      child: CustomPaint(
        painter: _CycleBarPainter(
          segments: cycleSegments(cycles, now),
          color: RingdownColors.activeUnacked,
          track: track,
        ),
      ),
    );
  }
}

class _CycleBarPainter extends CustomPainter {
  _CycleBarPainter({
    required this.segments,
    required this.color,
    required this.track,
  });

  final List<CycleSegment> segments;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(5),
    );
    canvas.drawRRect(rect, Paint()..color = track);
    if (segments.isEmpty) return;
    var start = segments.first.start;
    var end = segments.first.end;
    for (final segment in segments) {
      if (segment.start.isBefore(start)) start = segment.start;
      if (segment.end.isAfter(end)) end = segment.end;
    }
    final span = end.difference(start).inMilliseconds;
    if (span <= 0) {
      canvas.drawRRect(rect, Paint()..color = color);
      return;
    }
    canvas.save();
    canvas.clipRRect(rect);
    final paint = Paint()..color = color;
    for (final segment in segments) {
      final left = segment.start.difference(start).inMilliseconds / span * size.width;
      var width = segment.end.difference(segment.start).inMilliseconds / span * size.width;
      if (width < 3) width = 3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 0, width, size.height),
          const Radius.circular(5),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CycleBarPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}
