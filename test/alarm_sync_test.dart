import 'package:flutter_test/flutter_test.dart';
import 'package:ringdown/models/alarm.dart';
import 'package:ringdown/services/alarm_sync.dart';

Alarm _alarm({
  required int id,
  String status = 'Y',
  bool acked = false,
  DateTime? receivedAt,
  DateTime? clearedAt,
}) {
  final received = receivedAt ?? DateTime.utc(2026, 9, 24, 12);
  return Alarm(
    id: id,
    siteId: 'SITE',
    device: 'RTU',
    description: 'temp',
    status: status,
    state: status == 'Y' ? 'active' : 'cleared',
    priority: 20,
    alarmAt: received,
    receivedAt: received,
    clearedAt: clearedAt,
    acked: acked,
  );
}

void main() {
  test('merge keeps a local acknowledgement ahead of the server', () {
    final local = [_alarm(id: 1, acked: true)];
    final incoming = [_alarm(id: 1, acked: false), _alarm(id: 2, status: 'N')];
    final merged = mergeAlarms(local, incoming);
    final byId = {for (final alarm in merged) alarm.id: alarm};
    expect(byId[1]!.acked, isTrue);
    expect(byId[2]!.isCleared, isTrue);
  });

  test('merge applies a clear over the copy the phone already had', () {
    final local = [_alarm(id: 7)];
    final incoming = [
      _alarm(
        id: 7,
        status: 'N',
        clearedAt: DateTime.utc(2026, 9, 24, 12, 5),
      ),
    ];
    final merged = mergeAlarms(local, incoming);
    expect(merged.single.isCleared, isTrue);
    expect(merged.single.clearedAt, DateTime.utc(2026, 9, 24, 12, 5));
  });

  test('prune keeps a clear inside the chosen window and drops an older one', () {
    final now = DateTime.utc(2026, 9, 24);
    final alarms = [
      _alarm(id: 1, receivedAt: now.subtract(const Duration(days: 40))),
      _alarm(
        id: 2,
        status: 'N',
        receivedAt: now.subtract(const Duration(days: 40)),
        clearedAt: now.subtract(const Duration(days: 10)),
      ),
      _alarm(
        id: 3,
        status: 'N',
        receivedAt: now.subtract(const Duration(days: 10)),
        clearedAt: now.subtract(const Duration(days: 2)),
      ),
    ];
    final week = pruneClearedAlarms(alarms, now).map((alarm) => alarm.id);
    expect(week, [1, 3]);
    final month = pruneClearedAlarms(
      alarms,
      now,
      maxAge: const Duration(days: maxAlarmHistoryDays),
    ).map((alarm) => alarm.id);
    expect(month, [1, 2, 3]);
  });

  test('history days stay between 1 and 30', () {
    expect(clampAlarmHistoryDays(0), minAlarmHistoryDays);
    expect(clampAlarmHistoryDays(7), defaultAlarmHistoryDays);
    expect(clampAlarmHistoryDays(45), maxAlarmHistoryDays);
    expect(lookbackHoursFor(30), 720);
  });
}