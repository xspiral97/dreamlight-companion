import 'package:html/dom.dart';

import 'store.dart';

const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
List<Map<String, int>> parseSchedule(Document doc) {
  final result = <Map<String, int>>[];
  for (final tr in doc.querySelectorAll('tr')) {
    final cells = tr.children;
    if (cells.length != 2) continue;
    final day = weekdays.indexOf(cells[0].text.trim()) + 1;
    if (day == 0) continue;
    final text = cells[1].text.trim();
    if (text.toLowerCase() == 'n/a') continue;
    if (text.toLowerCase() == 'all day') {
      result.add({'day': day, 'start': 0, 'end': 1440});
      continue;
    }
    final matches = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.length != 2) continue;
    int minute(RegExpMatch m) =>
        (int.parse(m[1]!) % 12 + (m[3]!.toUpperCase() == 'PM' ? 12 : 0)) * 60 +
        int.parse(m[2] ?? '0');
    result.add({
      'day': day,
      'start': minute(matches[0]),
      'end': minute(matches[1]),
    });
  }
  return result;
}

String availability(List<dynamic> windows, DateTime now) {
  if (windows.isEmpty) return 'Schedule unknown / not applicable';
  if (windows.any((w) => inWindow(now, w['day'], w['start'], w['end']))) {
    return 'Available now';
  }
  for (int i = 1; i <= 7 * 1440; i++) {
    final d = now.add(Duration(minutes: i));
    if (windows.any((w) => inWindow(d, w['day'], w['start'], w['end']))) {
      return 'Next: ${weekdays[d.weekday - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
  }
  return 'Schedule unknown';
}
