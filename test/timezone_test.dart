import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:dreamlight_companion/store.dart';

void main() {
  test('weekly wall clock intervals survive DST transitions', () {
    initializeTimeZones();
    final zone = tz.getLocation('Europe/Bucharest');
    final before = tz.TZDateTime.from(DateTime.utc(2026, 10, 25, 0, 30), zone);
    final after = tz.TZDateTime.from(DateTime.utc(2026, 10, 25, 1, 30), zone);
    expect(before.hour, 3);
    expect(after.hour, 3);
    expect(inWindow(before, 7, 180, 240), true);
    expect(inWindow(after, 7, 180, 240), true);
    final spring = tz.TZDateTime.from(DateTime.utc(2026, 3, 29, 1, 30), zone);
    expect(spring.hour, 4);
    expect(inWindow(spring, 7, 180, 240), false);
  });
}
