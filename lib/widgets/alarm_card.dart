import 'package:flutter/material.dart';

import '../models/alarm.dart';
import '../theme.dart';
import 'status_chips.dart';
import 'timer_row.dart';

class AlarmCard extends StatelessWidget {
  const AlarmCard({
    super.key,
    required this.alarm,
    required this.now,
    this.clearedFreezeAt,
    this.selecting = false,
    this.selected = false,
    this.onAck,
    this.onOpen,
    this.onLongPress,
    this.onToggleSelect,
  });

  final Alarm alarm;
  final DateTime now;
  final DateTime? clearedFreezeAt;
  final bool selecting;
  final bool selected;
  final VoidCallback? onAck;
  final VoidCallback? onOpen;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;

  Color get _stripe {
    if (alarm.isActive && !alarm.acked) return RingdownColors.activeUnacked;
    if (alarm.isActive && alarm.acked) return RingdownColors.activeAcked;
    if (alarm.isCleared && !alarm.acked) return RingdownColors.unackedAmber;
    return RingdownColors.cleared;
  }

  @override
  Widget build(BuildContext context) {
    final muted = alarm.isCleared;
    final card = Card(
      color: Theme.of(context).cardTheme.color?.withValues(
            alpha: muted && alarm.acked ? 0.7 : 1,
          ),
      child: InkWell(
        onTap: selecting ? onToggleSelect : onOpen,
        onLongPress: selecting ? null : onLongPress,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: _stripe),
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Center(
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelect?.call(),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alarm.siteId,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        alarm.device,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        alarm.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          StatusChip(alarm: alarm),
                          AckChip(alarm: alarm),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TimerRow(
                        alarm: alarm,
                        now: now,
                        clearedFreezeAt: clearedFreezeAt,
                      ),
                    ],
                  ),
                ),
              ),
              if (!selecting && alarm.canAck)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: 'Acknowledge alarm at ${alarm.siteId}',
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: onAck,
                          child: const Text('ACK'),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (selecting || !alarm.canAck) return card;

    return Dismissible(
      key: ValueKey('ack-${alarm.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onAck?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: RingdownColors.cleared.withValues(alpha: 0.35),
        child: const Text(
          'ACK',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      child: card,
    );
  }
}
