import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';
import 'package:dreamlight_companion/schedule.dart';
import 'package:dreamlight_companion/store.dart';

void main() {
  test('overnight schedule belongs to start day and excludes end', () {
    expect(inWindow(DateTime(2026, 11, 9, 23), 1, 1320, 120), true);
    expect(inWindow(DateTime(2026, 11, 10, 1), 1, 1320, 120), true);
    expect(inWindow(DateTime(2026, 11, 10, 2), 1, 1320, 120), false);
    expect(inWindow(DateTime(2026, 11, 11, 1), 1, 1320, 120), false);
  });
  test('wiki day rows parse noon midnight and inactive days', () {
    final rows = parseSchedule(
      parse(
        '<table><tr><th>Sunday</th><td>12 PM to 12 AM</td></tr><tr><th>Monday</th><td>All day</td></tr><tr><th>Tuesday</th><td>n/a</td></tr></table>',
      ),
    );
    expect(rows.length, 2);
    expect(rows[0], {'day': 7, 'start': 720, 'end': 0});
    expect(availability(rows, DateTime(2026, 11, 8, 14)), 'Available now');
    expect(availability(rows, DateTime(2026, 11, 10, 14)), startsWith('Next:'));
  });
  test('new collection categories remain browsable', () {
    expect(sectionFor('New DLC Item', '["Unknown new category"]'), 'Guides');
    expect(sectionFor('Pumpkin', '["Ingredients"]'), 'Ingredients');
  });
}
