import '../models/alarm.dart';

/// Active timer: ticking while in alarm, frozen when cleared.
/// Gateway cleared_at wins over the phone-local freeze.
Duration activeDuration({
  required Alarm alarm,
  required DateTime now,
  DateTime? clearedFreezeAt,
}) {
  if (alarm.isCleared) {
    final freeze = alarm.clearedAt ?? clearedFreezeAt ?? now;
    return freeze.difference(alarm.alarmAt);
  }
  return now.difference(alarm.alarmAt);
}

/// Unacked timer: ticking until ACK, then frozen at acked_at − received_at.
Duration unackedDuration({
  required Alarm alarm,
  required DateTime now,
}) {
  if (alarm.acked) {
    final end = alarm.ackedAt ?? now;
    return end.difference(alarm.receivedAt);
  }
  return now.difference(alarm.receivedAt);
}
