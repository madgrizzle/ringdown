import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm.dart';

class AlarmCache {
  AlarmCache(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'cached_alarms';
  static const _totalKey = 'cached_alarms_total';
  static const _ownerKey = 'cached_alarms_owner';
  static const _cursorKey = 'alarm_sync_cursor';

  Future<void> save(List<Alarm> items, {int? total}) async {
    final encoded = jsonEncode(items.map((a) => a.toJson()).toList());
    await _prefs.setString(_key, encoded);
    if (total != null) {
      await _prefs.setInt(_totalKey, total);
    }
  }

  ({List<Alarm> items, int total})? load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Alarm.fromJson(e as Map<String, dynamic>))
          .toList();
      final total = _prefs.getInt(_totalKey) ?? list.length;
      return (items: list, total: total);
    } catch (_) {
      return null;
    }
  }

  /// Alarms and cursor belong to one technician. A different login starts over.
  ({List<Alarm> items, int total})? loadFor(String owner) {
    if (_prefs.getString(_ownerKey) != owner) return null;
    return load();
  }

  Future<void> saveFor(String owner, List<Alarm> items) async {
    await _prefs.setString(_ownerKey, owner);
    await save(items, total: items.length);
  }

  String? get owner => _prefs.getString(_ownerKey);

  DateTime? readCursor(String owner) {
    if (_prefs.getString(_ownerKey) != owner) return null;
    final raw = _prefs.getString(_cursorKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> writeCursor(String owner, DateTime cursor) async {
    await _prefs.setString(_ownerKey, owner);
    await _prefs.setString(_cursorKey, cursor.toUtc().toIso8601String());
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_totalKey);
    await _prefs.remove(_ownerKey);
    await _prefs.remove(_cursorKey);
  }
}
