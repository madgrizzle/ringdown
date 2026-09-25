import 'package:flutter/material.dart';

import '../models/alarm.dart';
import '../priority_category.dart';
import '../theme.dart';

class CategoryChip extends StatelessWidget {
  const CategoryChip({super.key, required this.alarm});

  final Alarm alarm;

  @override
  Widget build(BuildContext context) {
    final category = priorityCategory(alarm.priority);
    return Chip(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      label: Text(category.name),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: category.onColor,
      ),
      color: WidgetStatePropertyAll(category.color),
      backgroundColor: category.color,
      side: BorderSide(color: category.color),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.alarm});

  final Alarm alarm;

  @override
  Widget build(BuildContext context) {
    final active = alarm.isActive;
    return Chip(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      label: Text(active ? 'ACTIVE' : 'CLEARED'),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: active ? RingdownColors.activeUnacked : RingdownColors.cleared,
      ),
      side: BorderSide(
        color: active ? RingdownColors.activeUnacked : RingdownColors.cleared,
      ),
      backgroundColor: (active
              ? RingdownColors.activeUnacked
              : RingdownColors.cleared)
          .withValues(alpha: 0.12),
    );
  }
}

class AckChip extends StatelessWidget {
  const AckChip({super.key, required this.alarm});

  final Alarm alarm;

  @override
  Widget build(BuildContext context) {
    if (alarm.acked) {
      return Chip(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        label: const Text('ACKED'),
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      );
    }
    if (alarm.isCleared) {
      return Chip(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        label: const Text('CLEARED, NEVER ACKED'),
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      label: const Text('UNACKED'),
      labelStyle: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: RingdownColors.unackedAmber,
      ),
      side: const BorderSide(color: RingdownColors.unackedAmber),
      backgroundColor: RingdownColors.unackedAmber.withValues(alpha: 0.12),
    );
  }
}
