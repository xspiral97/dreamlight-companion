import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/store.dart';
import 'package:dreamlight_companion/wiki.dart';

void main() {
  test('live wiki parses actual ingredient and critter pages', () async {
    final dir = Directory.systemTemp.createTempSync('wiki-smoke-');
    final store = Store();
    await store.open(directory: dir);
    final wiki = Wiki(store);
    try {
      for (final title in ['Pumpkin', 'Classic Rabbit']) {
        final response = await wiki.api({
          'action': 'parse',
          'page': title,
          'prop': 'text',
        });
        final page = response['parse'];
        final row = <String, Object?>{
          'id': '${page['pageid']}',
          'title': title,
          'categories': '[]',
        };
        await store.db.insert('catalog', row);
        final details = await wiki.details(row);
        expect((details['fields'] as Map).isNotEmpty, true);
        if (title == 'Classic Rabbit') {
          expect((details['schedule'] as List).isNotEmpty, true);
          expect(details['fields']['Favorite food:'], 'Carrot');
        }
        if (title == 'Pumpkin') {
          expect(details['fields']['Growth Time:'], contains('4 hours'));
        }
      }
    } finally {
      wiki.client.close();
      await store.db.close();
      dir.deleteSync(recursive: true);
    }
  }, skip: !const bool.fromEnvironment('LIVE_WIKI'));
  test(
    'live collection refresh imports the current catalog',
    () async {
      final dir = Directory.systemTemp.createTempSync('wiki-full-sync-');
      final store = Store();
      await store.open(directory: dir);
      final wiki = Wiki(store);
      try {
        final report = await wiki.sync((_) {});
        expect(report.failures, isEmpty);
        expect(report.sources, 16);
        expect(report.records, greaterThan(7900));
        expect((await store.catalog()).length, greaterThan(7500));
      } finally {
        wiki.client.close();
        await store.db.close();
        dir.deleteSync(recursive: true);
      }
    },
    skip:
        !(const bool.fromEnvironment('LIVE_WIKI') ||
            const bool.fromEnvironment('LIVE_CATALOG')),
  );
}
