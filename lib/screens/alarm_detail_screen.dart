import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/alarm.dart';
import '../providers/alarms_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ticker_provider.dart';
import '../services/api_client.dart';
import '../utils/alarm_timers.dart';
import '../utils/duration_format.dart';
import '../widgets/status_chips.dart';
import '../widgets/timer_row.dart';

class AlarmDetailScreen extends ConsumerStatefulWidget {
  const AlarmDetailScreen({super.key, required this.alarmId});

  final int alarmId;

  @override
  ConsumerState<AlarmDetailScreen> createState() => _AlarmDetailScreenState();
}

class _AlarmDetailScreenState extends ConsumerState<AlarmDetailScreen> {
  Alarm? _alarm;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final alarm =
          await ref.read(alarmsProvider.notifier).loadDetail(widget.alarmId);
      if (mounted) {
        setState(() {
          _alarm = alarm;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _ack() async {
    final result =
        await ref.read(alarmsProvider.notifier).ackOne(widget.alarmId);
    if (!mounted) return;
    if (result.alreadyCleared > 0 && result.acked == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already cleared — cannot ACK on server.'),
        ),
      );
    } else if (result.failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ACK failed')),
      );
    } else if (result.acked > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acknowledged')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(tickerProvider);
    final freeze = ref.watch(settingsProvider).clearedFreeze;
    final fromList = ref
        .watch(alarmsProvider)
        .items
        .where((a) => a.id == widget.alarmId);
    final alarm = fromList.isNotEmpty ? fromList.first : _alarm;

    return Scaffold(
      appBar: AppBar(title: Text(alarm?.siteId ?? 'Alarm')),
      body: _loading && alarm == null
          ? const Center(child: CircularProgressIndicator())
          : alarm == null
              ? Center(child: Text(_error ?? 'Alarm not found'))
              : _body(context, alarm, now, freeze[alarm.id]),
      bottomNavigationBar: alarm != null && alarm.canAck
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  height: 56,
                  child: Semantics(
                    button: true,
                    label: 'Acknowledge alarm at ${alarm.siteId}',
                    child: FilledButton(
                      onPressed: _ack,
                      child: const Text(
                        'ACK',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body(
    BuildContext context,
    Alarm alarm,
    DateTime now,
    DateTime? freeze,
  ) {
    final fmt = DateFormat.yMMMd().add_jm();
    final active = activeDuration(
      alarm: alarm,
      now: now,
      clearedFreezeAt: freeze,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          alarm.siteId,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(alarm.device, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(alarm.description, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusChip(alarm: alarm),
            AckChip(alarm: alarm),
            Chip(label: Text('Priority ${alarm.priority}')),
            if ((alarm.aid ?? '').isNotEmpty) Chip(label: Text('AID ${alarm.aid}')),
          ],
        ),
        const SizedBox(height: 16),
        TimerRow(
          alarm: alarm,
          now: now,
          clearedFreezeAt: freeze,
          compact: false,
        ),
        if (alarm.isCleared) ...[
          const SizedBox(height: 8),
          Text(
            'Cleared after ${formatCompactDuration(active)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        if (alarm.acked) ...[
          const SizedBox(height: 8),
          Text(
            [
              'Acknowledged',
              if ((alarm.ackedBy ?? '').isNotEmpty) 'by ${alarm.ackedBy}',
              if (alarm.ackedAt != null)
                'at ${fmt.format(alarm.ackedAt!.toLocal())}',
            ].join(' '),
          ),
        ],
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alarm time'),
          subtitle: Text(fmt.format(alarm.alarmAt.toLocal())),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Received'),
          subtitle: Text(fmt.format(alarm.receivedAt.toLocal())),
        ),
        if ((alarm.rawSubject ?? '').isNotEmpty ||
            (alarm.rawBody ?? '').isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Original message'),
            children: [
              if ((alarm.rawSubject ?? '').isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    alarm.rawSubject!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if ((alarm.rawBody ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(alarm.rawBody!),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
