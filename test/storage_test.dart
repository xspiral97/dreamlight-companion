import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'backup roundtrip, invalid import, pre-import backup and catalog isolation',
    () async {
      final dir = await Directory.systemTemp.createTemp('dreamlight-test-');
      final store = Store();
      await store.open(directory: dir);
      try {
        await store.set('progress', {'42': true});
        await store.set('layouts', [
          {
            'name': 'Pumpkin island',
            'plots': [
              {
                'crop': 'Pumpkin',
                'notes': 'north',
                'x': 2,
                'y': 3,
                'w': 4,
                'h': 5,
                'color': 0,
              },
            ],
          },
        ]);
        await store.db.insert('catalog', {
          'id': '42',
          'title': 'Pumpkin',
          'categories': '["Ingredients"]',
        });
        final saved = await store.export();
        await store.set('progress', {'42': false});
        await store.restore(saved);
        expect((await store.get('progress'))['42'], true);
        expect((await store.get('layouts'))[0]['plots'][0]['w'], 4);
        expect((await store.catalog()).length, 1);
        expect(
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('before-import'))
              .length,
          1,
        );
        final invalid = jsonEncode({
          'version': 1,
          'personal': [
            {'key': 'layouts', 'value': '[]'},
          ],
        });
        await expectLater(store.restore(invalid), throwsFormatException);
        expect((await store.get('progress'))['42'], true);
      } finally {
        await store.db.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
