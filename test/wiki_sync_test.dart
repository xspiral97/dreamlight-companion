import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dreamlight_companion/wiki.dart';
import 'package:dreamlight_companion/store.dart';
import 'package:dreamlight_companion/catalog_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const markup =
      '<ul><li class="ct-item" data-ct-pid="549" data-ct-name="Pumpkin" data-ct-area="Dreamlight Valley"><img src="/images/pumpkin.png"></li></ul>';
  test('collection parser keeps stable IDs, area and thumbnail', () {
    final row = parseCollection('Ingredients', markup).single;
    expect(row['id'], '549');
    expect(
      jsonDecode(row['categories'] as String),
      contains('Dreamlight Valley'),
    );
    expect(
      jsonDecode(row['details'] as String)['image'],
      'https://dreamlightvalleywiki.com/images/pumpkin.png',
    );
  });
  test(
    'one blocked source preserves personal data and imports successful sources',
    () async {
      final dir = Directory.systemTemp.createTempSync('wiki-sync-test-');
      final store = Store();
      await store.open(directory: dir);
      final wiki = Wiki(
        store,
        client: MockClient((request) async {
          expect(request.url.queryParameters['generator'], isNull);
          if (request.url.queryParameters['page'] ==
              'Collections/Ingredients') {
            return http.Response(
              jsonEncode({
                'parse': {
                  'text': {'*': markup},
                },
              }),
              200,
            );
          }
          return http.Response('Blocked by site', 403);
        }),
      );
      try {
        await store.set('progress', {'549': true});
        final report = await wiki.sync((_) {});
        expect(report.sources, 1);
        expect(report.failures, isNotEmpty);
        expect((await store.catalog()).single['title'], 'Pumpkin');
        expect((await store.get('progress'))['549'], true);
        expect(
          await store.db.query('meta', where: 'key=?', whereArgs: ['lastSync']),
          isEmpty,
        );
      } finally {
        wiki.client.close();
        await store.db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
