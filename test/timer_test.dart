import 'package:flutter_test/flutter_test.dart';
import 'package:ringdown/models/alarm.dart';
import 'package:ringdown/utils/alarm_timers.dart';
import 'package:ringdown/utils/duration_format.dart';

Alarm _alarm({
  required DateTime alarmAt,
  required DateTime receivedAt,
  String state = 'active',
  String status = 'Y',
  bool acked = false,
  DateTime? ackedAt,
}) {
  return Alarm(
    id: 1,
    siteId: 'SITE_A',
    device: 'UPS',
    description: 'Battery',
    status: status,
    state: state,
    priority: 20,
    alarmAt: alarmAt,
    receivedAt: receivedAt,
    acked: acked,
    ackedAt: ackedAt,
  );
}

void main() {
  test('compact duration format', () {
    expect(formatCompactDuration(const Duration(seconds: 12)), '12s');
    expect(formatCompactDuration(const Duration(minutes: 3, seconds: 12)), '3m 12s');
    expect(formatCompactDuration(const Duration(hours: 1, minutes: 4)), '1h 04m');
    expect(formatCompactDuration(const Duration(days: 2, hours: 3)), '2d 3h');
  });

  test('active timer keeps ticking while active', () {
    final alarmAt = DateTime.utc(2026, 9, 20, 12, 0, 0);
    final now = DateTime.utc(2026, 9, 20, 12, 14, 2);
    final a = _alarm(
      alarmAt: alarmAt,
      receivedAt: alarmAt,
    );
    expect(
      activeDuration(alarm: a, now: now),
      const Duration(minutes: 14, seconds: 2),
    );
  });

  test('active timer freezes when cleared', () {
    final alarmAt = DateTime.utc(2026, 9, 20, 12, 0, 0);
    final freeze = DateTime.utc(2026, 9, 20, 12, 10, 0);
    final later = DateTime.utc(2026, 9, 20, 12, 30, 0);
    final a = _alarm(
      alarmAt: alarmAt,
      receivedAt: alarmAt,
      state: 'cleared',
      status: 'N',
    );
    expect(
      activeDuration(alarm: a, now: later, clearedFreezeAt: freeze),
      const Duration(minutes: 10),
    );
  });

  test('unacked timer freezes at acked_at', () {
    final received = DateTime.utc(2026, 9, 20, 12, 0, 0);
    final ackedAt = DateTime.utc(2026, 9, 20, 12, 2, 18);
    final later = DateTime.utc(2026, 9, 20, 13, 0, 0);
    final a = _alarm(
      alarmAt: received,
      receivedAt: received,
      acked: true,
      ackedAt: ackedAt,
    );
    expect(
      unackedDuration(alarm: a, now: later),
      const Duration(minutes: 2, seconds: 18),
    );
  });

  test('ACK does not freeze the active timer', () {
    final alarmAt = DateTime.utc(2026, 9, 20, 12, 0, 0);
    final now = DateTime.utc(2026, 9, 20, 12, 20, 0);
    final a = _alarm(
      alarmAt: alarmAt,
      receivedAt: alarmAt,
      acked: true,
      ackedAt: DateTime.utc(2026, 9, 20, 12, 1, 0),
    );
    expect(activeDuration(alarm: a, now: now), const Duration(minutes: 20));
  });
}
