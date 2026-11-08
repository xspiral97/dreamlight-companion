import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dreamlight_companion/wiki.dart';
import 'package:dreamlight_companion/store.dart';
import 'package:dreamlight_companion/catalog_parser.dart';
import 'package:dreamlight_companion/item_image.dart';
import 'package:dreamlight_companion/wiki_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('hero image selects the item rather than its universe badge', () {
    final doc = parse(
      '<div id="infobox-image"><span><img src="/badge.png" width="24"></span><figure><img src="/Acorn_Lantern.png" width="140"></figure></div>',
    );
    expect(itemImage(doc), '/Acorn_Lantern.png');
    expect(
      imageCandidates(
        'https://dreamlightvalleywiki.com/images/thumb/6/6d/Acorn_Lantern.png/66px-Acorn_Lantern.png',
      ).last,
      'https://dreamlightvalleywiki.com/images/6/6d/Acorn_Lantern.png',
    );
  });
  test('retry-after supports seconds and HTTP dates', () {
    expect(retryDelay('120'), const Duration(seconds: 120));
    expect(retryDelay('3600'), const Duration(hours: 1));
    expect(
      retryDelay(
        'Sun, 08 Nov 2026 15:01:00 GMT',
        now: DateTime.utc(2026, 11, 8, 15),
      ),
      const Duration(minutes: 1),
    );
  });
  test('collection thumbnails preserve page IDs', () {
    final row = parseCollection(
      'Ingredients',
      '<li class="ct-item" data-ct-pid="549" data-ct-name="Pumpkin" data-ct-area="Dreamlight Valley"><img src="/images/pumpkin.png"></li>',
    ).single;
    expect(row['id'], '549');
  });
  test('refresh makes one feed request and repairs cached badge without clearing progress', () async {
    final dir = Directory.systemTemp.createTempSync('shared-feed-test-');
    final store = Store();
    await store.open(directory: dir);
    int requests = 0;
    final snapshot = {
      'schemaVersion': 2,
      'generatedAt': '2026-11-08T15:00:00Z',
      'sources': ['Furniture Sets'],
      'records': [
        {
          'id': '549',
          'title': 'Acorn Lantern',
          'image': 'https://dreamlightvalleywiki.com/images/Acorn_Lantern.png',
          'categories': '["Furniture Sets"]',
          'details': jsonEncode({
            'fields': {'Collection:': 'Furniture Sets'},
            'image':
                'https://dreamlightvalleywiki.com/images/Acorn_Lantern.png',
            'summary': true,
          }),
        },
      ],
    };
    final wiki = Wiki(
      store,
      client: MockClient((request) async {
        requests++;
        expect(request.url.host, 'raw.githubusercontent.com');
        return http.Response.bytes(
          gzip.encode(utf8.encode(jsonEncode(snapshot))),
          200,
        );
      }),
    );
    try {
      await store.set('progress', {'549': true});
      await store.db.insert('catalog', {
        'id': '549',
        'title': 'Acorn Lantern',
        'categories': '["Crafting"]',
        'details': jsonEncode({
          'fields': {'Type:': 'Crafted Furniture'},
          'image': 'https://dreamlightvalleywiki.com/images/badge.png',
          'summary': false,
          'blocks': [
            {'type': 'p', 'text': 'Cached article'},
          ],
        }),
      });
      final report = await wiki.sync((_) {});
      expect(requests, 1);
      expect(report.failures, isEmpty);
      final row = (await store.catalog()).single;
      expect(row['image'], contains('Acorn_Lantern'));
      final details = jsonDecode(row['details'] as String);
      expect(details['fields']['Type:'], 'Crafted Furniture');
      expect(details['image'], contains('Acorn_Lantern'));
      expect(details['blocks'].single['text'], 'Cached article');
      expect((await store.get('progress'))['549'], true);
    } finally {
      wiki.client.close();
      await store.db.close();
      dir.deleteSync(recursive: true);
    }
  });
  test(
    'failed or invalid feed leaves catalog and last-sync unchanged',
    () async {
      final dir = Directory.systemTemp.createTempSync('feed-failure-test-');
      final store = Store();
      await store.open(directory: dir);
      final wiki = Wiki(
        store,
        client: MockClient(
          (_) async => http.Response('{"schemaVersion":2,"records":[]}', 200),
        ),
      );
      try {
        await store.db.insert('catalog', {
          'id': '1',
          'title': 'Saved',
          'categories': '[]',
        });
        await expectLater(wiki.sync((_) {}), throwsFormatException);
        expect((await store.catalog()).single['title'], 'Saved');
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
