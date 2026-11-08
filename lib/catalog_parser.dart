import 'dart:convert';

import 'package:html/parser.dart' as html;

List<Map<String, Object?>> parseCollection(String source, String markup) {
  final doc = html.parse(markup);
  final result = <Map<String, Object?>>[];
  for (final item in doc.querySelectorAll('.ct-item[data-ct-pid]')) {
    final id = item.attributes['data-ct-pid'];
    final title = item.attributes['data-ct-name'];
    if (id == null || title == null || title.isEmpty) continue;
    final image = item.querySelector('img')?.attributes['src'];
    final area = item.attributes['data-ct-area'] ?? 'Unknown area';
    final group = item.parent?.id.replaceFirst('ct-items-', '') ?? '';
    result.add({
      'id': id,
      'title': title,
      'categories': jsonEncode([source, area, group]),
      'details': jsonEncode({
        'fields': {'Collection:': source, 'Location / DLC:': area},
        'image': image == null
            ? null
            : Uri.parse('https://dreamlightvalleywiki.com')
                  .resolve(image)
                  .toString(),
        'blocks': [],
        'links': [],
        'schedule': [],
        'summary': true,
      }),
    });
  }
  return result;
}

class SyncReport {
  final int sources, records;
  final List<String> failures;
  const SyncReport(this.sources, this.records, this.failures);
  @override
  String toString() => failures.isEmpty
      ? 'Updated $records entries from $sources sources.'
      : 'Updated $records entries from $sources sources. Failed sources: ${failures.join(', ')}. Retry Refresh now.';
}

List<Map<String, String>> parsePlantableIngredients(String markup) {
  final doc = html.parse(markup);
  final crops = <Map<String, String>>[];
  String clean(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');
  for (final table in doc.querySelectorAll('table')) {
    final headings =
        table
            .querySelectorAll('tr')
            .firstOrNull
            ?.querySelectorAll('th')
            .map((h) => clean(h.text).toLowerCase())
            .toList() ??
        [];
    final sourceIndex = headings.indexOf('sources'),
        nameIndex = headings.indexOf('name'),
        locationIndex = headings.indexOf('location'),
        growthIndex = headings.indexOf('grow time');
    if (sourceIndex < 0 || nameIndex < 0) continue;
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.children.where((c) => c.localName == 'td').toList();
      if (cells.length <= sourceIndex || cells.length <= nameIndex) continue;
      if (!cells[sourceIndex]
          .querySelectorAll('a[title]')
          .any((a) => (a.attributes['title'] ?? '').endsWith(' Seed'))) {
        continue;
      }
      final image = cells[0].querySelector('img')?.attributes['src'];
      if (image == null) continue;
      final link = cells[nameIndex].querySelector('a[title]');
      final name = link?.attributes['title'] ?? clean(cells[nameIndex].text);
      crops.add({
        'name': name,
        'image': Uri.parse('https://dreamlightvalleywiki.com')
            .resolve(image)
            .toString(),
        'location': locationIndex < 0
            ? 'Unknown'
            : clean(cells[locationIndex].text),
        'growth': growthIndex < 0 ? 'Unknown' : clean(cells[growthIndex].text),
      });
    }
  }
  return crops;
}
