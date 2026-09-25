import 'package:intl/intl.dart';

import 'models/alarm.dart';

/// One repeating condition on this phone: same site, device, and description.
class AlarmCycleGroup {
  const AlarmCycleGroup({required this.cycles, required this.current});

  /// Oldest first.
  final List<Alarm> cycles;

  /// The cycle that is in alarm, or the most recent one.
  final Alarm current;

  bool get repeats => cycles.length > 1;
}

/// Same site, device, and description, ignoring case and extra spaces.
String conditionKey(Alarm alarm) {
  String norm(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return '${norm(alarm.siteId)}|${norm(alarm.device)}|${norm(alarm.description)}';
}

/// Collapse repeated conditions. A group is inserted where its first alarm
/// sits in [sorted], so the list order stays the list's sort order.
List<AlarmCycleGroup> groupAlarmCycles(List<Alarm> sorted) {
  final byKey = <String, List<Alarm>>{};
  for (final alarm in sorted) {
    byKey.putIfAbsent(conditionKey(alarm), () => []).add(alarm);
  }
  final seen = <String>{};
  final groups = <AlarmCycleGroup>[];
  for (final alarm in sorted) {
    final key = conditionKey(alarm);
    if (!seen.add(key)) continue;
    final cycles = [...byKey[key]!]
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    groups.add(AlarmCycleGroup(cycles: cycles, current: _current(cycles)));
  }
  return groups;
}

/// Every saved cycle of [alarm]'s condition, oldest first.
List<Alarm> cyclesFor(Alarm alarm, Iterable<Alarm> all) {
  final key = conditionKey(alarm);
  final cycles = all.where((other) => conditionKey(other) == key).toList()
    ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  if (cycles.any((other) => other.id == alarm.id)) return cycles;
  return [...cycles, alarm]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
}

Alarm _current(List<Alarm> cycles) {
  for (final alarm in cycles.reversed) {
    if (alarm.isActive) return alarm;
  }
  return cycles.last;
}

/// "10 times today, last cleared 1:40 PM" or "In alarm now · 10 times today".
String cycleSummary(List<Alarm> cycles, DateTime now) {
  final count = cycles.length == 1 ? '1 time' : '${cycles.length} times';
  final earliest = cycles
      .map((alarm) => alarm.receivedAt.toLocal())
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final localNow = now.toLocal();
  final when = _sameDay(earliest, localNow)
      ? 'today'
      : 'since ${DateFormat.MMMd().format(earliest)}';
  if (cycles.any((alarm) => alarm.isActive)) {
    return 'In alarm now · $count $when';
  }
  DateTime? lastCleared;
  for (final alarm in cycles) {
    final cleared = alarm.clearedAt?.toLocal();
    if (cleared == null) continue;
    if (lastCleared == null || cleared.isAfter(lastCleared)) {
      lastCleared = cleared;
    }
  }
  if (lastCleared == null) return '$count $when';
  return '$count $when, last cleared ${DateFormat.jm().format(lastCleared)}';
}

/// One line for the detail list. Newest cycles are shown by the caller.
String cycleIntervalLabel(Alarm alarm, DateTime now) {
  final start = alarm.receivedAt.toLocal();
  final end = (alarm.isActive ? null : alarm.clearedAt)?.toLocal();
  if (end == null) return 'In alarm since ${_stamp(start, now)}';
  final minutes = end.difference(start).inSeconds;
  final length = minutes < 60
      ? '${end.difference(start).inSeconds}s'
      : minutes < 3600
          ? '${end.difference(start).inMinutes}m'
          : '${end.difference(start).inHours}h ${end.difference(start).inMinutes.remainder(60)}m';
  return '${_stamp(start, now)} – ${_stamp(end, now)} · $length';
}

String _stamp(DateTime local, DateTime now) {
  final clock = DateFormat.jm().format(local);
  if (_sameDay(local, now.toLocal())) return clock;
  return '${DateFormat.MMMd().format(local)}, $clock';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Start and end of one in-alarm stretch. An open alarm runs to [now].
class CycleSegment {
  const CycleSegment({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

List<CycleSegment> cycleSegments(List<Alarm> cycles, DateTime now) {
  return [
    for (final alarm in cycles)
      CycleSegment(
        start: alarm.receivedAt,
        end: alarm.isActive ? now : (alarm.clearedAt ?? alarm.receivedAt),
      ),
  ];
}
