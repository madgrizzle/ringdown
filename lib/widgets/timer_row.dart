import 'package:flutter/material.dart';

import '../models/alarm.dart';
import '../theme.dart';
import '../utils/alarm_timers.dart';
import '../utils/duration_format.dart';

class TimerRow extends StatelessWidget {
  const TimerRow({
    super.key,
    required this.alarm,
    required this.now,
    this.clearedFreezeAt,
    this.compact = true,
  });

  final Alarm alarm;
  final DateTime now;
  final DateTime? clearedFreezeAt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = activeDuration(
      alarm: alarm,
      now: now,
      clearedFreezeAt: clearedFreezeAt,
    );
    final unacked = unackedDuration(alarm: alarm, now: now);
    final activeLabel = alarm.isCleared
        ? 'Was active  ${formatCompactDuration(active)}'
        : 'Active  ${formatCompactDuration(active)}';
    final unackedLabel = alarm.acked
        ? 'Acked in  ${formatCompactDuration(unacked)}'
        : 'Unacked  ${formatCompactDuration(unacked)}';
    final unackedColor =
        alarm.acked ? null : RingdownColors.unackedAmber;
    final style = Theme.of(context).textTheme.bodySmall;
    return Semantics(
      label: [
        alarm.isCleared
            ? formatDurationSpoken(active, prefix: 'was active for')
            : formatDurationSpoken(active, prefix: 'active for'),
        alarm.acked
            ? formatDurationSpoken(unacked, prefix: 'acknowledged in')
            : formatDurationSpoken(unacked, prefix: 'unacknowledged for'),
      ].join('. '),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text(activeLabel, style: style),
          Text(
            unackedLabel,
            style: style?.copyWith(
              color: unackedColor,
              fontWeight: alarm.acked ? FontWeight.w400 : FontWeight.w700,
            ),
          ),
          if (alarm.acked && (alarm.ackedBy ?? '').isNotEmpty)
            Text('by ${alarm.ackedBy}', style: style),
        ],
      ),
    );
  }
}
