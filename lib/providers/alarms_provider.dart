import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../acknowledgements.dart';
import '../models/alarm.dart';
import '../models/auth_state.dart';
import '../models/filters.dart';
import '../priority_category.dart';
import '../services/ack_queue.dart';
import '../services/alarm_cache.dart';
import '../services/alarm_sync.dart';
import '../services/api_client.dart';
import '../utils/alarm_timers.dart';
import '../utils/limited.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';
import 'settings_provider.dart';

class AckBatchResult {
  const AckBatchResult({
    this.acked = 0,
    this.alreadyCleared = 0,
    this.failed = 0,
    this.skipped = 0,
  });

  final int acked;
  final int alreadyCleared;
  final int failed;
  final int skipped;

  int get attempted => acked + alreadyCleared + failed;
}

class AlarmsState {
  const AlarmsState({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.loading = false,
    this.loadingMore = false,
    this.offline = false,
    this.error,
    this.selected = const {},
    this.selecting = false,
    this.truncated = false,
  });

  final List<Alarm> items;
  final int total;
  final int page;
  final bool loading;
  final bool loadingMore;
  final bool offline;
  final String? error;
  final Set<int> selected;
  final bool selecting;
  final bool truncated;

  AlarmsState copyWith({
    List<Alarm>? items,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    bool? offline,
    String? error,
    bool clearError = false,
    Set<int>? selected,
    bool? selecting,
    bool? truncated,
  }) {
    return AlarmsState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      offline: offline ?? this.offline,
      error: clearError ? null : (error ?? this.error),
      selected: selected ?? this.selected,
      selecting: selecting ?? this.selecting,
      truncated: truncated ?? this.truncated,
    );
  }
}

class AlarmsNotifier extends Notifier<AlarmsState> {
  Timer? _poll;
  final Set<int> _autoAckInFlight = {};

  ApiClient get _api => ref.read(apiClientProvider);
  AlarmCache get _cache => ref.read(alarmCacheProvider);
  AckQueue get _queue => ref.read(ackQueueProvider);
  AlarmFilters get _filters {
    final filters = ref.read(settingsProvider).filters;
    if (kShowAcknowledgements) return filters;
    final sort = filters.sort.withoutAcknowledgement;
    if (!filters.unackedOnly && sort == filters.sort) return filters;
    return filters.copyWith(unackedOnly: false, sort: sort);
  }

  @override
  AlarmsState build() {
    ref.onDispose(() => _poll?.cancel());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (ref.read(authProvider).status != AuthStatus.authenticated) {
        return;
      }
      silentRefresh();
    });
    ref.listen(connectivityProvider, (prev, next) {
      final wasOffline = prev?.asData?.value == false;
      final nowOnline = next.asData?.value == true;
      if (wasOffline && nowOnline) {
        drainAckQueue();
        silentRefresh();
      }
    });
    return const AlarmsState();
  }

  String? get _owner {
    final auth = ref.read(authProvider);
    final name = auth.username ?? auth.lastUsername;
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<void> refresh({bool silent = false, bool forceLookback = false}) async {
    if (ref.read(authProvider).token == null) return;
    if (!silent) {
      state = state.copyWith(loading: true, clearError: true);
    }
    final owner = _owner;
    if (owner != null && _cache.owner != null && _cache.owner != owner) {
      state = state.copyWith(items: const [], total: 0, loading: !silent);
    }
    final cached = owner == null ? null : _cache.loadFor(owner);
    try {
      final stored = forceLookback || cached == null || owner == null
          ? null
          : _cache.readCursor(owner);
      final days = ref.read(settingsProvider).historyDays;
      final synced = await _sync(stored, cached?.items ?? const [], days);
      final items = pruneClearedAlarms(
        synced.alarms,
        DateTime.now().toUtc(),
        maxAge: Duration(days: clampAlarmHistoryDays(days)),
      );
      if (owner != null) {
        await _cache.saveFor(owner, items);
        if (synced.complete && synced.cursor != null) {
          await _cache.writeCursor(owner, synced.cursor!);
        }
      }
      _captureClearedFreezes(state.items, items);
      state = state.copyWith(
        items: items,
        total: items.length,
        page: 1,
        loading: false,
        offline: false,
        truncated: false,
        clearError: true,
      );
      unawaited(_autoAcknowledge(items));
    } catch (e) {
      final saved = cached?.items ?? const <Alarm>[];
      if (saved.isNotEmpty) {
        state = state.copyWith(
          items: saved,
          total: saved.length,
          loading: false,
          offline: true,
          error: _err(e),
        );
        unawaited(_autoAcknowledge(saved));
      } else {
        state = state.copyWith(
          loading: false,
          offline: true,
          error: _err(e),
        );
      }
    }
  }

  /// A longer keep period downloads that many days once. A shorter one only
  /// drops the older cleared alarms. The old sync clock stays if the download fails.
  Future<void> historyWindowChanged({required bool expanded}) async {
    await refresh(forceLookback: expanded);
  }

  /// Pulls every page of the cursor. [complete] is false when a page was left unread,
  /// so the caller keeps the old cursor and the next refresh asks again.
  Future<({List<Alarm> alarms, DateTime? cursor, bool complete})> _sync(
    DateTime? cursor,
    List<Alarm> local,
    int historyDays,
  ) async {
    var merged = local;
    DateTime? afterTime;
    int? afterId;
    DateTime? serverTime;
    for (var page = 0; page < 20; page++) {
      final result = await _api.syncAlarms(
        changedSince: cursor,
        lookbackHours: cursor == null ? lookbackHoursFor(historyDays) : null,
        afterTime: afterTime,
        afterId: afterId,
      );
      serverTime ??= result.serverTime;
      merged = mergeAlarms(merged, result.items);
      if (!result.hasMore) {
        return (alarms: merged, cursor: serverTime, complete: serverTime != null);
      }
      if (result.nextAfterTime == null || result.nextAfterId == null) {
        break;
      }
      afterTime = result.nextAfterTime;
      afterId = result.nextAfterId;
    }
    return (alarms: merged, cursor: null, complete: false);
  }

  Future<void> silentRefresh() => refresh(silent: true);

  /// The synced cache is the whole list, so the list does not ask for a later page.
  Future<void> loadMore() async {}

  Future<void> applyFilters(AlarmFilters filters) async {
    await ref.read(settingsProvider.notifier).setFilters(filters);
    await refresh();
  }

  List<Alarm> visibleItems({bool includeCleared = false}) {
    final filters = _filters;
    var items = state.items.where((alarm) {
      if (filters.hideCleared && !includeCleared && alarm.isCleared) {
        return false;
      }
      if (filters.unackedOnly && alarm.acked) return false;
      if (!filters.priorityFloor.allows(alarm.priority)) return false;
      final site = filters.siteContains.trim().toLowerCase();
      if (site.isNotEmpty && !alarm.siteId.toLowerCase().contains(site)) {
        return false;
      }
      final device = filters.deviceContains.trim().toLowerCase();
      if (device.isNotEmpty &&
          !alarm.device.toLowerCase().contains(device)) {
        return false;
      }
      return true;
    }).toList();
    items = _applyClientSearch(items, filters);
    items = _applyClientSort(items, filters);
    final hidden = ref.read(settingsProvider).hiddenIds;
    if (!filters.showHidden) {
      items = items.where((a) => !hidden.contains(a.id)).toList();
    }
    return items;
  }

  void enterSelect({int? firstId}) {
    final selected = {...state.selected};
    if (firstId != null) selected.add(firstId);
    state = state.copyWith(selecting: true, selected: selected);
  }

  void exitSelect() {
    state = state.copyWith(selecting: false, selected: {});
  }

  void toggleSelected(int id) {
    final next = {...state.selected};
    if (!next.add(id)) next.remove(id);
    state = state.copyWith(selected: next);
  }

  void selectAllVisible() {
    state = state.copyWith(
      selected: visibleItems().map((a) => a.id).toSet(),
      selecting: true,
    );
  }

  void selectAllUnackedVisible() {
    state = state.copyWith(
      selected: visibleItems().where((a) => !a.acked).map((a) => a.id).toSet(),
      selecting: true,
    );
  }

  Future<AckBatchResult> ackOne(int id) async {
    return ackMany([id]);
  }

  Future<AckBatchResult> ackMany(
    Iterable<int> ids, {
    void Function(int done, int total)? onProgress,
  }) async {
    final byId = {for (final a in state.items) a.id: a};
    final targets = <Alarm>[];
    var skipped = 0;
    var alreadyCleared = 0;
    for (final id in ids) {
      final a = byId[id];
      if (a == null) continue;
      if (a.acked) {
        skipped++;
        continue;
      }
      if (a.status != 'Y') {
        alreadyCleared++;
        continue;
      }
      targets.add(a);
    }
    if (targets.isEmpty) {
      return AckBatchResult(
        skipped: skipped,
        alreadyCleared: alreadyCleared,
      );
    }

    final username = ref.read(authProvider).username ?? 'me';
    final now = DateTime.now().toUtc();
    final previous = {for (final a in targets) a.id: a};
    state = state.copyWith(
      items: [
        for (final a in state.items)
          if (previous.containsKey(a.id))
            a.copyWith(acked: true, ackedBy: username, ackedAt: now)
          else
            a,
      ],
    );

    var acked = 0;
    var failed = 0;
    var cleared = alreadyCleared;
    var done = 0;
    final revert = <int>[];
    final queue = <int>[];

    await mapLimited(targets, 8, (alarm) async {
      try {
        await _api.ack(alarm.id);
        acked++;
        await _queue.remove(alarm.id);
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          cleared++;
          revert.add(alarm.id);
        } else if (e.statusCode == null) {
          queue.add(alarm.id);
          acked++;
        } else {
          failed++;
          revert.add(alarm.id);
        }
      } catch (_) {
        failed++;
        revert.add(alarm.id);
      } finally {
        done++;
        onProgress?.call(done, targets.length);
      }
    });

    if (queue.isNotEmpty) {
      await _queue.enqueueAll(queue);
    }
    if (revert.isNotEmpty) {
      state = state.copyWith(
        items: [
          for (final a in state.items)
            if (previous.containsKey(a.id) && revert.contains(a.id))
              previous[a.id]!
            else
              a,
        ],
      );
    }
    await _cache.save(state.items, total: state.total);
    return AckBatchResult(
      acked: acked,
      alreadyCleared: cleared,
      failed: failed,
      skipped: skipped,
    );
  }

  /// Acknowledges alarms that can still be acknowledged, without any UI.
  /// No-ops while manual acknowledgement is visible.
  Future<void> _autoAcknowledge(Iterable<Alarm> alarms) {
    if (kShowAcknowledgements) return Future<void>.value();
    final ids = <int>[];
    for (final alarm in alarms) {
      if (!alarm.canAck) continue;
      if (_autoAckInFlight.add(alarm.id)) ids.add(alarm.id);
    }
    if (ids.isEmpty) return Future<void>.value();
    return _finishAutoAck(ids, ackMany(ids));
  }

  /// Acknowledges one alarm that just arrived, even if it is not loaded yet.
  Future<void> acknowledgeIncoming(int id) {
    if (kShowAcknowledgements) return Future<void>.value();
    if (!_autoAckInFlight.add(id)) return Future<void>.value();
    final match = state.items.where((a) => a.id == id).toList();
    if (match.isNotEmpty && !match.first.canAck) {
      _autoAckInFlight.remove(id);
      return Future<void>.value();
    }
    final future = match.isNotEmpty ? ackMany([id]) : _ackUnknown(id);
    return _finishAutoAck([id], future);
  }

  Future<void> _finishAutoAck(List<int> ids, Future<Object?> future) async {
    try {
      await future;
    } finally {
      _autoAckInFlight.removeAll(ids);
    }
  }

  Future<void> _ackUnknown(int id) async {
    try {
      await _api.ack(id);
      await _queue.remove(id);
    } on ApiException catch (e) {
      if (e.statusCode == null) await _queue.enqueue(id);
    } catch (_) {
      await _queue.enqueue(id);
    }
  }

  Future<AckBatchResult> ackSite(String siteId) {
    final ids = visibleItems()
        .where((a) => a.siteId == siteId && a.canAck)
        .map((a) => a.id);
    return ackMany(ids);
  }

  Future<AckBatchResult> ackStorm(List<int> ids) => ackMany(ids);

  Future<void> drainAckQueue() async {
    final pending = _queue.peek();
    if (pending.isEmpty) return;
    await ackMany(pending);
  }

  Future<Alarm> loadDetail(int id) async {
    try {
      final alarm = await _api.getAlarm(id);
      _upsert(alarm);
      _captureClearedFreezes(state.items, [alarm]);
      unawaited(_autoAcknowledge([alarm]));
      return alarm;
    } catch (e) {
      final local = state.items.where((a) => a.id == id);
      if (local.isNotEmpty) return local.first;
      rethrow;
    }
  }

  void _upsert(Alarm alarm) {
    final idx = state.items.indexWhere((a) => a.id == alarm.id);
    final List<Alarm> next;
    if (idx == -1) {
      next = [alarm, ...state.items];
    } else {
      next = [...state.items];
      next[idx] = alarm;
    }
    state = state.copyWith(items: next, total: next.length);
    final owner = _owner;
    if (owner != null) {
      unawaited(_cache.saveFor(owner, next));
    }
  }

  void _captureClearedFreezes(List<Alarm> previous, List<Alarm> next) {
    final now = DateTime.now().toUtc();
    final prevById = {for (final a in previous) a.id: a};
    final more = <int, DateTime>{};
    for (final a in next) {
      if (!a.isCleared) {
        unawaited(ref.read(settingsProvider.notifier).clearFreeze(a.id));
        continue;
      }
      more[a.id] = now;
      final was = prevById[a.id];
      if (was != null && was.isActive) {
        more[a.id] = now;
      }
    }
    unawaited(ref.read(settingsProvider.notifier).recordClearedFreezes(more));
  }

  static List<Alarm> _applyClientSearch(List<Alarm> items, AlarmFilters f) {
    final q = f.search.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where(
          (a) =>
              a.siteId.toLowerCase().contains(q) ||
              a.device.toLowerCase().contains(q) ||
              a.description.toLowerCase().contains(q),
        )
        .toList();
  }

  List<Alarm> _applyClientSort(List<Alarm> items, AlarmFilters f) {
    final now = DateTime.now().toUtc();
    final freeze = ref.read(settingsProvider).clearedFreeze;
    final copy = [...items];
    int byTimeDesc(Alarm a, Alarm b) => b.alarmAt.compareTo(a.alarmAt);
    int byText(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    switch (f.sort) {
      case SortMode.timeNewest:
        copy.sort(byTimeDesc);
      case SortMode.timeOldest:
        copy.sort((a, b) => a.alarmAt.compareTo(b.alarmAt));
      case SortMode.siteAsc:
        copy.sort((a, b) => byText(a.siteId, b.siteId));
      case SortMode.siteDesc:
        copy.sort((a, b) => byText(b.siteId, a.siteId));
      case SortMode.deviceAsc:
        copy.sort((a, b) => byText(a.device, b.device));
      case SortMode.deviceDesc:
        copy.sort((a, b) => byText(b.device, a.device));
      case SortMode.siteThenDevice:
        copy.sort((a, b) {
          final s = a.siteId.toLowerCase().compareTo(b.siteId.toLowerCase());
          if (s != 0) return s;
          return a.device.toLowerCase().compareTo(b.device.toLowerCase());
        });
      case SortMode.status:
        copy.sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          return byTimeDesc(a, b);
        });
      case SortMode.unackedFirst:
        copy.sort((a, b) {
          if (a.acked != b.acked) return a.acked ? 1 : -1;
          return byTimeDesc(a, b);
        });
      case SortMode.longestActive:
        copy.sort((a, b) {
          final da = activeDuration(
            alarm: a,
            now: now,
            clearedFreezeAt: freeze[a.id],
          );
          final db = activeDuration(
            alarm: b,
            now: now,
            clearedFreezeAt: freeze[b.id],
          );
          return db.compareTo(da);
        });
      case SortMode.longestUnacked:
        copy.sort((a, b) {
          final da = unackedDuration(alarm: a, now: now);
          final db = unackedDuration(alarm: b, now: now);
          return db.compareTo(da);
        });
    }
    return copy;
  }

  static String _err(Object e) {
    if (e is ApiException) return e.message;
    if (e is DioException) return e.message ?? 'Network error';
    return e.toString();
  }
}

final alarmCacheProvider = Provider<AlarmCache>((ref) {
  return AlarmCache(ref.watch(prefsStoreProvider).prefs);
});

final ackQueueProvider = Provider<AckQueue>((ref) {
  return AckQueue(ref.watch(prefsStoreProvider).prefs);
});

final alarmsProvider =
    NotifierProvider<AlarmsNotifier, AlarmsState>(AlarmsNotifier.new);
