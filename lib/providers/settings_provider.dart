import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/filters.dart';
import '../services/alarm_sync.dart';
import '../services/prefs_store.dart';

class SettingsState {
  const SettingsState({
    required this.themeMode,
    required this.filters,
    required this.clearedFreeze,
    this.hiddenIds = const {},
    this.historyDays = defaultAlarmHistoryDays,
  });

  final ThemeMode themeMode;
  final AlarmFilters filters;
  final Map<int, DateTime> clearedFreeze;
  final Set<int> hiddenIds;

  /// How many days a cleared alarm stays on this phone. 1 to 30.
  final int historyDays;

  SettingsState copyWith({
    ThemeMode? themeMode,
    AlarmFilters? filters,
    Map<int, DateTime>? clearedFreeze,
    Set<int>? hiddenIds,
    int? historyDays,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      filters: filters ?? this.filters,
      clearedFreeze: clearedFreeze ?? this.clearedFreeze,
      hiddenIds: hiddenIds ?? this.hiddenIds,
      historyDays: historyDays ?? this.historyDays,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  PrefsStore get _prefs => ref.read(prefsStoreProvider);

  @override
  SettingsState build() {
    final prefs = ref.watch(prefsStoreProvider);
    return SettingsState(
      themeMode: _parseTheme(prefs.readThemeMode()),
      filters: prefs.readFilters(),
      clearedFreeze: prefs.readClearedFreeze(),
      hiddenIds: prefs.readHiddenIds(),
      historyDays: prefs.readHistoryDays(),
    );
  }

  Future<void> setHistoryDays(int days) async {
    final next = clampAlarmHistoryDays(days);
    state = state.copyWith(historyDays: next);
    await _prefs.writeHistoryDays(next);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.writeThemeMode(switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    });
  }

  Future<void> setFilters(AlarmFilters filters) async {
    state = state.copyWith(filters: filters);
    await _prefs.writeFilters(filters);
  }

  Future<void> recordClearedFreeze(int alarmId, DateTime at) async {
    if (state.clearedFreeze.containsKey(alarmId)) return;
    final next = Map<int, DateTime>.from(state.clearedFreeze)..[alarmId] = at;
    state = state.copyWith(clearedFreeze: next);
    await _prefs.writeClearedFreeze(next);
  }

  Future<void> recordClearedFreezes(Map<int, DateTime> more) async {
    if (more.isEmpty) return;
    final next = Map<int, DateTime>.from(state.clearedFreeze);
    var changed = false;
    for (final e in more.entries) {
      if (!next.containsKey(e.key)) {
        next[e.key] = e.value;
        changed = true;
      }
    }
    if (!changed) return;
    state = state.copyWith(clearedFreeze: next);
    await _prefs.writeClearedFreeze(next);
  }

  Future<void> hideAlarm(int alarmId) async {
    if (state.hiddenIds.contains(alarmId)) return;
    final next = {...state.hiddenIds, alarmId};
    state = state.copyWith(hiddenIds: next);
    await _prefs.writeHiddenIds(next);
  }

  Future<void> unhideAlarm(int alarmId) async {
    if (!state.hiddenIds.contains(alarmId)) return;
    final next = {...state.hiddenIds}..remove(alarmId);
    state = state.copyWith(hiddenIds: next);
    await _prefs.writeHiddenIds(next);
  }

  Future<void> clearFreeze(int alarmId) async {
    if (!state.clearedFreeze.containsKey(alarmId)) return;
    final next = Map<int, DateTime>.from(state.clearedFreeze)..remove(alarmId);
    state = state.copyWith(clearedFreeze: next);
    await _prefs.writeClearedFreeze(next);
  }

  static ThemeMode _parseTheme(String raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }
}

final prefsStoreProvider = Provider<PrefsStore>((ref) {
  throw UnimplementedError('prefsStoreProvider must be overridden');
});

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);
