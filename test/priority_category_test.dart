import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringdown/priority_category.dart';

void main() {
  test('priority bands match the Telenium table', () {
    expect(priorityCategory(5).name, 'Critical');
    expect(priorityCategory(10).name, 'Critical');
    expect(priorityCategory(20).name, 'Major');
    expect(priorityCategory(20).color, const Color(0xFFFB8C00));
    expect(priorityCategory(48).name, 'Warning');
    expect(priorityCategory(72).name, 'Other');
    expect(priorityCategory(89).name, 'Other');
    expect(priorityCategory(90).name, 'System');
    expect(priorityCategory(0).name, 'Other');
    expect(colorFromHex('#00ACC1'), const Color(0xFF00ACC1));
  });

  test('every band, both edges: 1-10 Critical, 11-20 Major, 21-30 Escalated, '
      '31-40 Minor, 41-50 Warning, 51-60 General, 61-70 Information, '
      '71-89 Other, 90-99 System', () {
    const bands = <(int, int, String)>[
      (1, 10, 'Critical'),
      (11, 20, 'Major'),
      (21, 30, 'Escalated'),
      (31, 40, 'Minor'),
      (41, 50, 'Warning'),
      (51, 60, 'General'),
      (61, 70, 'Information'),
      (71, 89, 'Other'),
      (90, 99, 'System'),
    ];
    for (final band in bands) {
      expect(priorityCategory(band.$1).name, band.$3,
          reason: 'low edge ${band.$1}');
      expect(priorityCategory(band.$2).name, band.$3,
          reason: 'high edge ${band.$2}');
    }
  });

  test('every adjacent pair of bands flips category exactly at the boundary',
      () {
    const boundaries = <(int, String, int, String)>[
      (10, 'Critical', 11, 'Major'),
      (20, 'Major', 21, 'Escalated'),
      (30, 'Escalated', 31, 'Minor'),
      (40, 'Minor', 41, 'Warning'),
      (50, 'Warning', 51, 'General'),
      (60, 'General', 61, 'Information'),
      (70, 'Information', 71, 'Other'),
      (89, 'Other', 90, 'System'),
    ];
    for (final b in boundaries) {
      expect(priorityCategory(b.$1).name, b.$2,
          reason: '${b.$1} should still be ${b.$2}');
      expect(priorityCategory(b.$3).name, b.$4,
          reason: '${b.$3} should already be ${b.$4}');
    }
  });

  test('out-of-table priorities (0, negative, and above 99) fall back to '
      'Other rather than throwing or matching a band by accident', () {
    expect(priorityCategory(0).name, 'Other');
    expect(priorityCategory(-5).name, 'Other');
    expect(priorityCategory(100).name, 'Other');
    expect(priorityCategory(1000).name, 'Other');
  });

  test('priority floor keeps the chosen band and anything more urgent', () {
    expect(PriorityFloor.any.allows(72), isTrue);
    expect(PriorityFloor.any.allows(0), isTrue);
    expect(PriorityFloor.critical.allows(5), isTrue);
    expect(PriorityFloor.critical.allows(11), isFalse);
    expect(PriorityFloor.major.allows(20), isTrue);
    expect(PriorityFloor.major.allows(21), isFalse);
    expect(PriorityFloor.warning.allows(48), isTrue);
    expect(PriorityFloor.warning.allows(72), isFalse);
    expect(PriorityFloor.other.allows(89), isTrue);
    expect(PriorityFloor.other.allows(90), isFalse);
    expect(PriorityFloor.system.allows(99), isTrue);
    expect(PriorityFloor.system.allows(100), isFalse);
  });

  test('priority floor: every band boundary is respected by its own floor',
      () {
    expect(PriorityFloor.escalated.allows(30), isTrue);
    expect(PriorityFloor.escalated.allows(31), isFalse);
    expect(PriorityFloor.minor.allows(40), isTrue);
    expect(PriorityFloor.minor.allows(41), isFalse);
    expect(PriorityFloor.general.allows(60), isTrue);
    expect(PriorityFloor.general.allows(61), isFalse);
    expect(PriorityFloor.information.allows(70), isTrue);
    expect(PriorityFloor.information.allows(71), isFalse);
  });
}
