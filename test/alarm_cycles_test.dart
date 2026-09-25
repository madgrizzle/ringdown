import 'package:flutter_test/flutter_test.dart';
import 'package:ringdown/alarm_cycles.dart';
import 'package:ringdown/models/alarm.dart';

Alarm _door({
  required int id,
  required DateTime received,
  DateTime? cleared,
  String description = 'DOOR INTRUSION',
}) {
  return Alarm(
    id: id,
    siteId: 'Mossy_Head',
    device: 'MossyHead RTU',
    description: description,
    status: cleared == null ? 'Y' : 'N',
    state: cleared == null ? 'active' : 'cleared',
    priority: 72,
    alarmAt: received,
    receivedAt: received,
    clearedAt: cleared,
    acked: false,
  );
}

void main() {
  test('repeated door alarms become one group and other alarms stay apart', () {
    final day = DateTime.utc(2026, 9, 23, 16);
    final doors = [
      for (var i = 0; i < 10; i++)
        _door(
          id: i + 1,
          received: day.add(Duration(minutes: i * 5)),
          cleared: day.add(Duration(minutes: i * 5, seconds: 30)),
        ),
    ];
    final radio = Alarm(
      id: 99,
      siteId: 'Mossy_Head',
      device: 'MossyHead Nokia 7705',
      description: 'Mw Radio Link Down',
      status: 'Y',
      state: 'active',
      priority: 20,
      alarmAt: day.add(const Duration(hours: 2)),
      receivedAt: day.add(const Duration(hours: 2)),
      acked: false,
    );
    final newestFirst = [radio, ...doors.reversed];
    final groups = groupAlarmCycles(newestFirst);
    expect(groups.map((group) => group.current.id), [99, 10]);
    expect(groups[1].cycles.map((alarm) => alarm.id), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(groups[1].repeats, isTrue);
    expect(groups[0].repeats, isFalse);
  });

  test('summary names today and the last clear', () {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10, 52);
    final cycles = [
      _door(id: 1, received: start, cleared: start.add(const Duration(minutes: 3))),
      _door(
        id: 2,
        received: start.add(const Duration(hours: 2)),
        cleared: start.add(const Duration(hours: 2, minutes: 7)),
      ),
    ];
    final text = cycleSummary(cycles, now);
    expect(text, contains('2 times today'));
    expect(text, contains('last cleared'));
  });

  test('an open repeat says it is in alarm now', () {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    final cycles = [
      _door(id: 1, received: start, cleared: start.add(const Duration(minutes: 1))),
      _door(id: 2, received: start.add(const Duration(hours: 1))),
    ];
    expect(cycleSummary(cycles, now), contains('In alarm now'));
    expect(groupAlarmCycles(cycles).single.current.id, 2);
  });

  test('older repeats are counted since the first day', () {
    final now = DateTime.utc(2026, 9, 24, 18);
    final cycles = [
      _door(
        id: 1,
        received: DateTime.utc(2026, 9, 22, 15),
        cleared: DateTime.utc(2026, 9, 22, 15, 1),
      ),
      _door(
        id: 2,
        received: DateTime.utc(2026, 9, 24, 16),
        cleared: DateTime.utc(2026, 9, 24, 16, 2),
      ),
    ];
    expect(cycleSummary(cycles, now), contains('since'));
    expect(cycleSummary(cycles, now), isNot(contains('today')));
  });
}
