import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dreamlight_companion/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('version-one databases migrate and repair old image badges without losing layouts', () async {
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('catalog-migration-');
    final old = await databaseFactoryFfi.openDatabase(
      '${dir.path}/companion.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE catalog(id TEXT PRIMARY KEY,title TEXT,categories TEXT,details TEXT)',
          );
          await db.execute(
            'CREATE TABLE personal(key TEXT PRIMARY KEY,value TEXT)',
          );
          await db.execute(
            'CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT)',
          );
        },
      ),
    );
    final bundle = jsonDecode(
      await rootBundle.loadString('assets/catalog.json'),
    );
    final acorn = (bundle['records'] as List).firstWhere(
      (r) => r['title'] == 'Acorn Lantern',
    );
    await old.insert('catalog', {
      'id': acorn['id'],
      'title': 'Acorn Lantern',
      'categories': '["Furniture Sets"]',
      'details': jsonEncode({
        'fields': {'Type:': 'Crafted Furniture'},
        'summary': false,
        'image': 'https://dreamlightvalleywiki.com/images/badge.png',
        'blocks': [],
      }),
    });
    await old.insert('personal', {
      'key': 'layouts',
      'value': '[{"name":"Saved island","plots":[]}]',
    });
    await old.close();
    final store = Store();
    await store.open(directory: dir);
    try {
      await store.seedCatalog();
      final row = (await store.db.query(
        'catalog',
        where: 'id=?',
        whereArgs: [acorn['id']],
      )).single;
      expect(row['image'], contains('Acorn_Lantern'));
      expect(
        jsonDecode(row['details'] as String)['image'],
        contains('Acorn_Lantern'),
      );
      expect((await store.get('layouts'))[0]['name'], 'Saved island');
      expect((await store.catalog()).length, greaterThan(7500));
    } finally {
      await store.db.close();
      dir.deleteSync(recursive: true);
    }
  });
}
