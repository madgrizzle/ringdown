import '../models/alarm.dart';

const minAlarmHistoryDays = 1;
const defaultAlarmHistoryDays = 7;
const maxAlarmHistoryDays = 30;

int clampAlarmHistoryDays(int days) {
  if (days < minAlarmHistoryDays) return minAlarmHistoryDays;
  if (days > maxAlarmHistoryDays) return maxAlarmHistoryDays;
  return days;
}

/// First sync asks for this many hours. The server rejects a longer lookback.
int lookbackHoursFor(int days) => clampAlarmHistoryDays(days) * 24;

/// Merge a sync page into the phone's copy. An acknowledgement is never
/// undone by an older copy of the same alarm.
List<Alarm> mergeAlarms(Iterable<Alarm> local, Iterable<Alarm> incoming) {
  final byId = <int, Alarm>{for (final alarm in local) alarm.id: alarm};
  for (final alarm in incoming) {
    final previous = byId[alarm.id];
    if (previous != null && previous.acked && !alarm.acked) continue;
    byId[alarm.id] = alarm;
  }
  return byId.values.toList();
}

/// Drop cleared alarms older than [maxAge]. Alarms still in alarm stay.
List<Alarm> pruneClearedAlarms(
  Iterable<Alarm> alarms,
  DateTime now, {
  Duration maxAge = const Duration(days: defaultAlarmHistoryDays),
}) {
  final cutoff = now.toUtc().subtract(maxAge);
  return [
    for (final alarm in alarms)
      if (alarm.isActive || !_goneAt(alarm).isBefore(cutoff)) alarm,
  ];
}

DateTime _goneAt(Alarm alarm) => alarm.clearedAt ?? alarm.receivedAt;
