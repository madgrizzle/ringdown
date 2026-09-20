import 'package:flutter/material.dart';

import '../models/alarm.dart';
import '../utils/alarm_timers.dart';
import '../utils/duration_format.dart';

class SummaryStrip extends StatelessWidget {
  const SummaryStrip({
    super.key,
    required this.items,
    required this.now,
  });

  final List<Alarm> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final active = items.where((a) => a.isActive).length;
    final unacked = items.where((a) => !a.acked).length;
    Duration? oldest;
    for (final a in items.where((a) => !a.acked)) {
      final d = unackedDuration(alarm: a, now: now);
      if (oldest == null || d > oldest) oldest = d;
    }
    final oldestText = oldest == null
        ? 'none'
        : formatCompactDuration(oldest);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        '$active active · $unacked unacked · oldest unacked $oldestText',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class StormBanner extends StatelessWidget {
  const StormBanner({
    super.key,
    required this.siteId,
    required this.count,
    required this.onAckAll,
  });

  final String siteId;
  final int count;
  final VoidCallback onAckAll;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: Text('Burst: $count new at $siteId'),
      actions: [
        TextButton(
          onPressed: onAckAll,
          child: const Text('ACK all new'),
        ),
      ],
    );
  }
}

({String siteId, int count, List<int> ids})? stormFrom(
  List<Alarm> items,
  DateTime now,
) {
  final cutoff = now.toUtc().subtract(const Duration(minutes: 2));
  final recent = items.where((a) => a.receivedAt.isAfter(cutoff)).toList();
  if (recent.length < 5) return null;
  final bySite = <String, List<Alarm>>{};
  for (final a in recent) {
    bySite.putIfAbsent(a.siteId, () => []).add(a);
  }
  MapEntry<String, List<Alarm>>? top;
  for (final e in bySite.entries) {
    if (top == null || e.value.length > top.value.length) top = e;
  }
  if (top == null) return null;
  return (
    siteId: top.key,
    count: top.value.length,
    ids: top.value.where((a) => a.canAck).map((a) => a.id).toList(),
  );
}
