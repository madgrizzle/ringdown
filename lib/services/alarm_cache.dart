import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm.dart';

class AlarmCache {
  AlarmCache(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'cached_alarms';
  static const _totalKey = 'cached_alarms_total';

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

  Future<void> clear() async {
    await _prefs.remove(_key);
    await _prefs.remove(_totalKey);
  }
}
