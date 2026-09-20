import 'package:flutter_test/flutter_test.dart';
import 'package:ringdown/utils/duration_format.dart';

void main() {
  test('formatCompactDuration smoke', () {
    expect(formatCompactDuration(Duration.zero), '0s');
  });
}
