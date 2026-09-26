import 'package:flutter_test/flutter_test.dart';
import 'package:ringdown/models/alarm.dart';

Map<String, dynamic> _json({
  int id = 1,
  String? status = 'Y',
  String? state,
  dynamic priority,
}) {
  return {
    'id': id,
    'site_id': 'SITE',
    'device': 'RTU',
    'description': 'temp',
    'status': status,
    'state': state,
    'priority': priority,
    'alarm_at': '2026-09-24T12:00:00Z',
    'received_at': '2026-09-24T12:00:00Z',
    'acked': false,
  };
}

void main() {
  group('blank/missing priority falls back to 20 (Major) instead of '
      'throwing and taking down the whole page parse', () {
    test('missing priority key', () {
      expect(Alarm.fromJson(_json(priority: null)).priority, 20);
    });

    test('blank string priority', () {
      expect(Alarm.fromJson(_json(priority: '')).priority, 20);
    });

    test('whitespace-only string priority', () {
      expect(Alarm.fromJson(_json(priority: '   ')).priority, 20);
    });

    test('non-numeric string priority', () {
      expect(Alarm.fromJson(_json(priority: 'n/a')).priority, 20);
    });

    test('a real numeric string priority still parses', () {
      expect(Alarm.fromJson(_json(priority: '5')).priority, 5);
    });

    test('an int priority passes through unchanged', () {
      expect(Alarm.fromJson(_json(priority: 30)).priority, 30);
    });

    test('a double/num priority is truncated to an int', () {
      expect(Alarm.fromJson(_json(priority: 12.0)).priority, 12);
    });
  });

  group('isActive reflects state alone, not status', () {
    test('state active, status Y -> active', () {
      expect(Alarm.fromJson(_json(status: 'Y', state: 'active')).isActive,
          isTrue);
    });

    test('state cleared while status is still Y (not yet re-polled) -> '
        'not active; status alone must not override state', () {
      expect(
        Alarm.fromJson(_json(status: 'Y', state: 'cleared')).isActive,
        isFalse,
      );
    });

    test('missing state defaults from status', () {
      expect(Alarm.fromJson(_json(status: 'Y', state: null)).isActive,
          isTrue);
      expect(Alarm.fromJson(_json(status: 'N', state: null)).isActive,
          isFalse);
    });
  });

  test('correlation_key round-trips through toJson/fromJson', () {
    final withKey = Alarm.fromJson({
      ..._json(),
      'correlation_key': 'SITE|RTU|temp',
    });
    expect(withKey.correlationKey, 'SITE|RTU|temp');
    expect(Alarm.fromJson(withKey.toJson()).correlationKey, 'SITE|RTU|temp');
  });
}
