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
}
