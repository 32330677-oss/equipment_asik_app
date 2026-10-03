// Pure unit tests (no server needed). Run: flutter test
import 'package:equipment_asik_app/core/fmt.dart';
import 'package:equipment_asik_app/core/json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fmt slices wall-clock strings without time-zone conversion', () {
    expect(Fmt.time('2026-10-20 07:05:00'), '07:05');
    expect(Fmt.timeOn('2026-10-21 02:30:00', '2026-10-20'), '02:30 +1');
    expect(Fmt.date('2026-10-20'), '20/10/2026');
    expect(Fmt.duration(125), '2h 5m');
    expect(Fmt.hoursFromMinutes(90), '1.50');
  });

  test('JsonRead reads MySQL decimals and flags safely', () {
    final Json j = {'a': '12.50', 'b': 1, 'c': null, 'd': '7'};
    expect(j.dbl('a'), 12.5);
    expect(j.flag('b'), isTrue);
    expect(j.strOrNull('c'), isNull);
    expect(j.intv('d'), 7);
    expect(j.list('missing'), isEmpty);
  });
}
