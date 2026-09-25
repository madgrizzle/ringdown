import 'package:flutter/material.dart';

import '../acknowledgements.dart';
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
    this.hidden = false,
    this.onAck,
    this.onHide,
    this.onUnhide,
    this.onOpen,
    this.onLongPress,
    this.onToggleSelect,
  });

  final Alarm alarm;
  final DateTime now;
  final DateTime? clearedFreezeAt;
  final bool selecting;
  final bool selected;
  final bool hidden;
  final VoidCallback? onAck;
  final VoidCallback? onHide;
  final VoidCallback? onUnhide;
  final VoidCallback? onOpen;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;

  Color get _stripe {
    if (hidden) return const Color(0xFF78909C);
    if (!kShowAcknowledgements) {
      return alarm.isActive
          ? RingdownColors.activeUnacked
          : RingdownColors.cleared;
    }
    if (alarm.isActive && !alarm.acked) return RingdownColors.activeUnacked;
    if (alarm.isActive && alarm.acked) return RingdownColors.activeAcked;
    if (alarm.isCleared && !alarm.acked) return RingdownColors.unackedAmber;
    return RingdownColors.cleared;
  }

  @override
  Widget build(BuildContext context) {
    final muted = alarm.isCleared || hidden;
    final card = Card(
      color: Theme.of(context).cardTheme.color?.withValues(
            alpha: kShowAcknowledgements && muted && alarm.acked ? 0.7 : 1,
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
                          CategoryChip(alarm: alarm),
                          StatusChip(alarm: alarm),
                          if (kShowAcknowledgements) AckChip(alarm: alarm),
                          if (hidden)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              label: const Text('HIDDEN'),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
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
              if (!selecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (kShowAcknowledgements && alarm.canAck)
                        Semantics(
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
                      SizedBox(
                        height: 48,
                        child: hidden
                            ? TextButton(
                                onPressed: onUnhide,
                                child: const Text('Unhide'),
                              )
                            : TextButton(
                                onPressed: onHide,
                                child: const Text('Hide'),
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (selecting) return card;

    final canSwipeAck = kShowAcknowledgements && alarm.canAck;
    return Dismissible(
      key: ValueKey('swipe-${alarm.id}'),
      direction: canSwipeAck
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (hidden) {
            onUnhide?.call();
          } else {
            onHide?.call();
          }
        } else {
          onAck?.call();
        }
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: const Color(0xFF546E7A).withValues(alpha: 0.4),
        child: Text(
          hidden ? 'UNHIDE' : 'HIDE',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      secondaryBackground: canSwipeAck
          ? Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              color: RingdownColors.cleared.withValues(alpha: 0.35),
              child: const Text(
                'ACK',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            )
          : const SizedBox.shrink(),
      child: card,
    );
  }
}
