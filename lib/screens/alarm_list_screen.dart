import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/alarm.dart';
import '../models/filters.dart';
import '../providers/alarms_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ticker_provider.dart';
import '../widgets/alarm_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/summary_strip.dart';

class AlarmListScreen extends ConsumerStatefulWidget {
  const AlarmListScreen({super.key});

  @override
  ConsumerState<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends ConsumerState<AlarmListScreen> {
  final _scroll = ScrollController();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;
      _started = true;
      ref.read(alarmsProvider.notifier).refresh();
      ref.read(alarmsProvider.notifier).drainAckQueue();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - 400) {
      ref.read(alarmsProvider.notifier).loadMore();
    }
  }

  Future<void> _ack(BuildContext context, Iterable<int> ids) async {
    final messenger = ScaffoldMessenger.of(context);
    var last = 0;
    final result = await ref.read(alarmsProvider.notifier).ackMany(
      ids,
      onProgress: (done, total) {
        if (total > 1 && done != last) {
          last = done;
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text('ACKed $done/$total'),
              duration: const Duration(milliseconds: 600),
            ),
          );
        }
      },
    );
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    final parts = <String>[];
    if (result.acked > 0) parts.add('Acked ${result.acked}');
    if (result.alreadyCleared > 0) {
      parts.add('${result.alreadyCleared} already cleared');
    }
    if (result.failed > 0) parts.add('${result.failed} failed');
    if (result.acked == 0 &&
        result.alreadyCleared > 0 &&
        result.failed == 0 &&
        ids.length == 1) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Already cleared — cannot ACK on server.'),
        ),
      );
    } else if (parts.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    }
    if (result.failed == 0) {
      ref.read(alarmsProvider.notifier).exitSelect();
    }
  }

  Future<void> _confirmBulk(
    BuildContext context, {
    required String message,
    required List<int> ids,
  }) async {
    if (ids.length > 10) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Acknowledge alarms'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ACK'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    await _ack(context, ids);
  }

  Future<void> _hide(BuildContext context, Alarm alarm) async {
    await ref.read(settingsProvider.notifier).hideAlarm(alarm.id);
    if (alarm.canAck && context.mounted) {
      await ref.read(alarmsProvider.notifier).ackOne(alarm.id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alarm.canAck ? 'Hidden and acknowledged' : 'Alarm hidden',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref.read(settingsProvider.notifier).unhideAlarm(alarm.id);
          },
        ),
      ),
    );
  }

  Future<void> _unhide(BuildContext context, Alarm alarm) async {
    await ref.read(settingsProvider.notifier).unhideAlarm(alarm.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm unhidden')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final alarms = ref.watch(alarmsProvider);
    final settings = ref.watch(settingsProvider);
    final filters = settings.filters;
    final freeze = settings.clearedFreeze;
    final hiddenIds = settings.hiddenIds;
    final now = ref.watch(tickerProvider);
    final items = ref.read(alarmsProvider.notifier).visibleItems;
    final unackedCount =
        items.where((a) => !a.acked && a.isActive).length;
    final storm = stormFrom(items, now);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ringdown'),
            if ((auth.username ?? '').isNotEmpty)
              Text(
                auth.username!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (unackedCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Badge(
                label: Text('$unackedCount'),
                child: const Icon(Icons.notifications_active_outlined),
              ),
            ),
          if (alarms.selecting) ...[
            IconButton(
              tooltip: 'Select all visible',
              onPressed: () =>
                  ref.read(alarmsProvider.notifier).selectAllVisible(),
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              tooltip: 'Select all unacked visible',
              onPressed: () =>
                  ref.read(alarmsProvider.notifier).selectAllUnackedVisible(),
              icon: const Icon(Icons.deselect),
            ),
            IconButton(
              tooltip: 'Cancel',
              onPressed: () => ref.read(alarmsProvider.notifier).exitSelect(),
              icon: const Icon(Icons.close),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Select',
              onPressed: () =>
                  ref.read(alarmsProvider.notifier).enterSelect(),
              icon: const Icon(Icons.checklist),
            ),
            IconButton(
              tooltip: 'Settings',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (alarms.offline)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Offline — showing last cached alarms'),
                ),
              ),
            ),
          SummaryStrip(items: items, now: now),
          if (storm != null)
            StormBanner(
              siteId: storm.siteId,
              count: storm.count,
              onAckAll: () => _confirmBulk(
                context,
                message: 'ACK ${storm.ids.length} new alarms at ${storm.siteId}?',
                ids: storm.ids,
              ),
            ),
          FilterBar(
            filters: filters,
            onChanged: (f) =>
                ref.read(alarmsProvider.notifier).applyFilters(f),
            onOpenSheet: () async {
              final next = await showFilterSheet(
                context: context,
                current: filters,
              );
              if (next != null) {
                await ref.read(alarmsProvider.notifier).applyFilters(next);
              }
            },
          ),
          if (alarms.truncated)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Showing ${items.length} of ${alarms.total}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(alarmsProvider.notifier).refresh(),
              child: _buildList(
                context,
                alarms: alarms,
                items: items,
                filters: filters,
                now: now,
                freeze: freeze,
                hiddenIds: hiddenIds,
              ),
            ),
          ),
          if (alarms.selecting) _bulkBar(context, alarms, items),
        ],
      ),
    );
  }

  Widget _bulkBar(
    BuildContext context,
    AlarmsState alarms,
    List<Alarm> items,
  ) {
    final n = alarms.selected.length;
    return SafeArea(
      child: Material(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text('$n selected'),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(alarmsProvider.notifier).exitSelect(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: n == 0
                    ? null
                    : () => _confirmBulk(
                          context,
                          message: 'ACK $n selected alarms?',
                          ids: alarms.selected.toList(),
                        ),
                child: const Text('ACK selected'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required AlarmsState alarms,
    required List<Alarm> items,
    required AlarmFilters filters,
    required DateTime now,
    required Map<int, DateTime> freeze,
    required Set<int> hiddenIds,
  }) {
    if (alarms.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              filters.hideCleared ? 'No active alarms' : 'No alarms',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (filters.hideCleared)
            Center(
              child: TextButton(
                onPressed: () => ref.read(alarmsProvider.notifier).applyFilters(
                      filters.copyWith(hideCleared: false),
                    ),
                child: const Text('Show cleared'),
              ),
            ),
        ],
      );
    }

    if (filters.groupBy == GroupBy.none) {
      return ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: items.length + (alarms.loadingMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _card(context, items[i], now, freeze, alarms, hiddenIds);
        },
      );
    }

    final groups = <String, List<Alarm>>{};
    for (final a in items) {
      final key = filters.groupBy == GroupBy.site ? a.siteId : a.device;
      groups.putIfAbsent(key, () => []).add(a);
    }
    final keys = groups.keys.toList();
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: keys.length,
      itemBuilder: (context, gi) {
        final key = keys[gi];
        final group = groups[key]!;
        final unacked = group.where((a) => a.canAck).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(
                key,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(label: Text('${group.length}')),
                  if (unacked.isNotEmpty)
                    TextButton(
                      onPressed: () => _confirmBulk(
                        context,
                        message:
                            'ACK ${unacked.length} alarms at $key?',
                        ids: unacked.map((a) => a.id).toList(),
                      ),
                      child: const Text('ACK all'),
                    ),
                ],
              ),
            ),
            for (final a in group) ...[
              _card(context, a, now, freeze, alarms, hiddenIds),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _card(
    BuildContext context,
    Alarm alarm,
    DateTime now,
    Map<int, DateTime> freeze,
    AlarmsState alarms,
    Set<int> hiddenIds,
  ) {
    final hidden = hiddenIds.contains(alarm.id);
    return AlarmCard(
      alarm: alarm,
      now: now,
      clearedFreezeAt: freeze[alarm.id],
      selecting: alarms.selecting,
      selected: alarms.selected.contains(alarm.id),
      hidden: hidden,
      onAck: () => _ack(context, [alarm.id]),
      onHide: () => _hide(context, alarm),
      onUnhide: () => _unhide(context, alarm),
      onOpen: () => context.push('/alarms/${alarm.id}'),
      onLongPress: () =>
          ref.read(alarmsProvider.notifier).enterSelect(firstId: alarm.id),
      onToggleSelect: () =>
          ref.read(alarmsProvider.notifier).toggleSelected(alarm.id),
    );
  }
}
