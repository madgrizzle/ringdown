import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/filters.dart';

class PrefsStore {
  PrefsStore(this.prefs);

  final SharedPreferences prefs;
  SharedPreferences get _prefs => prefs;

  static const _filtersKey = 'alarm_filters';
  static const _themeKey = 'theme_mode';
  static const _freezeKey = 'cleared_freeze';
  static const _lastUsernameKey = 'last_username';
  static const _hiddenKey = 'hidden_alarm_ids';

  AlarmFilters readFilters() {
    final raw = _prefs.getString(_filtersKey);
    if (raw == null) return const AlarmFilters();
    try {
      return AlarmFilters.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AlarmFilters();
    }
  }

  Future<void> writeFilters(AlarmFilters filters) {
    return _prefs.setString(_filtersKey, jsonEncode(filters.toJson()));
  }

  /// dark | light | system
  String readThemeMode() => _prefs.getString(_themeKey) ?? 'dark';

  Future<void> writeThemeMode(String mode) => _prefs.setString(_themeKey, mode);

  Map<int, DateTime> readClearedFreeze() {
    final raw = _prefs.getString(_freezeKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          int.parse(e.key): DateTime.parse(e.value as String).toUtc(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> writeClearedFreeze(Map<int, DateTime> freeze) {
    final map = {
      for (final e in freeze.entries) e.key.toString(): e.value.toIso8601String(),
    };
    return _prefs.setString(_freezeKey, jsonEncode(map));
  }

  String? readLastUsername() => _prefs.getString(_lastUsernameKey);

  Future<void> writeLastUsername(String username) =>
      _prefs.setString(_lastUsernameKey, username);

  Set<int> readHiddenIds() {
    final raw = _prefs.getStringList(_hiddenKey) ?? const [];
    return {
      for (final s in raw)
        if (int.tryParse(s) != null) int.parse(s),
    };
  }

  Future<void> writeHiddenIds(Set<int> ids) {
    return _prefs.setStringList(
      _hiddenKey,
      ids.map((e) => e.toString()).toList(),
    );
  }
}
