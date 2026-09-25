import 'package:flutter/material.dart';

/// Telenium priority bands. Colors are the sheet's color names.
class PriorityCategory {
  const PriorityCategory(this.name, this.color);

  final String name;
  final Color color;

  Color get onColor =>
      color.computeLuminance() > 0.55 ? const Color(0xFF1A1A1A) : Colors.white;
}

const _bands = <(int, int, String, Color)>[
  (1, 10, 'Critical', Color(0xFFE53935)),
  (11, 20, 'Major', Color(0xFFFB8C00)),
  (21, 30, 'Escalated', Color(0xFFD81B60)),
  (31, 40, 'Minor', Color(0xFFFBC02D)),
  (41, 50, 'Warning', Color(0xFF00ACC1)),
  (51, 60, 'General', Color(0xFFBCAAA4)),
  (61, 70, 'Information', Color(0xFF00838F)),
  (71, 89, 'Other', Color(0xFF757575)),
  (90, 99, 'System', Color(0xFFB0C4DE)),
];

/// Lowest urgency still shown. A lower Telenium number is more urgent,
/// so Major and above keeps priorities 1–20.
enum PriorityFloor {
  any,
  critical,
  major,
  escalated,
  minor,
  warning,
  general,
  information,
  other,
  system,
}

extension PriorityFloorX on PriorityFloor {
  String get label => switch (this) {
        PriorityFloor.any => 'All',
        PriorityFloor.critical => 'Critical and above',
        PriorityFloor.major => 'Major and above',
        PriorityFloor.escalated => 'Escalated and above',
        PriorityFloor.minor => 'Minor and above',
        PriorityFloor.warning => 'Warning and above',
        PriorityFloor.general => 'General and above',
        PriorityFloor.information => 'Information and above',
        PriorityFloor.other => 'Other and above',
        PriorityFloor.system => 'System and above',
      };

  /// Highest priority number still included. Null shows every alarm.
  int? get maxPriority => switch (this) {
        PriorityFloor.any => null,
        PriorityFloor.critical => 10,
        PriorityFloor.major => 20,
        PriorityFloor.escalated => 30,
        PriorityFloor.minor => 40,
        PriorityFloor.warning => 50,
        PriorityFloor.general => 60,
        PriorityFloor.information => 70,
        PriorityFloor.other => 89,
        PriorityFloor.system => 99,
      };

  bool allows(int priority) {
    final max = maxPriority;
    if (max == null) return true;
    return priority >= 1 && priority <= max;
  }
}

PriorityCategory priorityCategory(int priority) {
  for (final band in _bands) {
    if (priority >= band.$1 && priority <= band.$2) {
      return PriorityCategory(band.$3, band.$4);
    }
  }
  return const PriorityCategory('Other', Color(0xFF757575));
}

Color? colorFromHex(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.replaceFirst('#', '').trim();
  if (cleaned.length != 6) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}
