import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm.dart';
import '../models/auth_state.dart';
import '../models/filters.dart';
import '../services/ack_queue.dart';
import '../services/alarm_cache.dart';
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
  bool _loadMoreInFlight = false;

  ApiClient get _api => ref.read(apiClientProvider);
  AlarmCache get _cache => ref.read(alarmCacheProvider);
  AckQueue get _queue => ref.read(ackQueueProvider);
  AlarmFilters get _filters => ref.read(settingsProvider).filters;

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

  Future<void> refresh({bool silent = false}) async {
    if (ref.read(authProvider).token == null) return;
    if (!silent) {
      state = state.copyWith(loading: true, clearError: true);
    }
    try {
      final filters = _filters;
      final clientSort = filters.sort.isClientSort;
      final pageSize = clientSort ? 100 : 50;
      final page = await _api.listAlarms(
        filters: filters,
        page: 1,
        pageSize: pageSize,
      );
      var items = page.items;
      items = _applyClientSearch(items, filters);
      items = _applyClientSort(items, filters);
      _captureClearedFreezes(state.items, items);
      await _cache.save(items, total: page.total);
      state = state.copyWith(
        items: items,
        total: page.total,
        page: 1,
        loading: false,
        offline: false,
        truncated: clientSort && page.total > items.length,
        clearError: true,
      );
    } catch (e) {
      final cached = _cache.load();
      if (cached != null && cached.items.isNotEmpty) {
        state = state.copyWith(
          items: cached.items,
          total: cached.total,
          loading: false,
          offline: true,
          error: _err(e),
        );
      } else {
        state = state.copyWith(
          loading: false,
          offline: true,
          error: _err(e),
        );
      }
    }
  }

  Future<void> silentRefresh() => refresh(silent: true);

  Future<void> loadMore() async {
    if (_loadMoreInFlight) return;
    if (_filters.sort.isClientSort) return;
    if (state.items.length >= state.total) return;
    _loadMoreInFlight = true;
    state = state.copyWith(loadingMore: true);
    try {
      final nextPage = state.page + 1;
      final page = await _api.listAlarms(
        filters: _filters,
        page: nextPage,
        pageSize: 50,
      );
      final merged = [...state.items];
      final seen = merged.map((a) => a.id).toSet();
      for (final a in page.items) {
        if (seen.add(a.id)) merged.add(a);
      }
      final items = _applyClientSearch(merged, _filters);
      _captureClearedFreezes(state.items, items);
      state = state.copyWith(
        items: items,
        total: page.total,
        page: nextPage,
        loadingMore: false,
        offline: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: _err(e));
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<void> applyFilters(AlarmFilters filters) async {
    await ref.read(settingsProvider.notifier).setFilters(filters);
    await refresh();
  }

  List<Alarm> get visibleItems {
    var items = _applyClientSearch(state.items, _filters);
    final hidden = ref.read(settingsProvider).hiddenIds;
    if (!_filters.showHidden) {
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
      selected: visibleItems.map((a) => a.id).toSet(),
      selecting: true,
    );
  }

  void selectAllUnackedVisible() {
    state = state.copyWith(
      selected: visibleItems.where((a) => !a.acked).map((a) => a.id).toSet(),
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

  Future<AckBatchResult> ackSite(String siteId) {
    final ids = visibleItems
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
      return alarm;
    } catch (e) {
      final local = state.items.where((a) => a.id == id);
      if (local.isNotEmpty) return local.first;
      rethrow;
    }
  }

  void _upsert(Alarm alarm) {
    final idx = state.items.indexWhere((a) => a.id == alarm.id);
    if (idx == -1) {
      state = state.copyWith(items: [alarm, ...state.items]);
    } else {
      final next = [...state.items];
      next[idx] = alarm;
      state = state.copyWith(items: next);
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
    switch (f.sort) {
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
      default:
        break;
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
