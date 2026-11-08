import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:sqflite/sqflite.dart' as mobile;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Store {
  late Database db;
  late Directory home;
  Future<void> open({Directory? directory}) async {
    home = directory ?? await getApplicationSupportDirectory();
    await home.create(recursive: true);
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      databaseFactory = mobile.databaseFactory;
    }
    db = await openDatabase(
      p.join(home.path, 'companion.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute(
          'CREATE TABLE catalog(id TEXT PRIMARY KEY, title TEXT, categories TEXT, details TEXT)',
        );
        await d.execute(
          'CREATE TABLE personal(key TEXT PRIMARY KEY, value TEXT)',
        );
        await d.execute('CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT)');
      },
    );
  }

  Future<void> seedCatalog() async {
    final count = await db.rawQuery('SELECT COUNT(*) AS n FROM catalog');
    if ((count.first['n'] as int) > 0) return;
    final snapshot = jsonDecode(
      await rootBundle.loadString('assets/catalog.json'),
    );
    await db.transaction((t) async {
      final batch = t.batch();
      for (final row in snapshot['records']) {
        batch.insert(
          'catalog',
          Map<String, Object?>.from(row),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<dynamic> get(String key, [dynamic fallback]) async {
    final rows = await db.query('personal', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? fallback : jsonDecode(rows.first['value'] as String);
  }

  Future<void> set(String key, dynamic value) async {
    await db.insert('personal', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> catalog() =>
      db.query('catalog', orderBy: 'title COLLATE NOCASE');
  Future<String> export() async => jsonEncode({
    'version': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'personal': await db.query('personal'),
  });
  Future<void> restore(String content) async {
    final data = jsonDecode(content);
    if (data is! Map || data['version'] != 1 || data['personal'] is! List) {
      throw const FormatException('Unsupported backup');
    }
    final rows = <Map<String, Object?>>[];
    for (final row in data['personal']) {
      if (row is! Map || row['key'] is! String || row['value'] is! String) {
        throw const FormatException('Invalid backup record');
      }
      final value = jsonDecode(row['value']);
      if (row['key'] == 'layouts') validateLayouts(value);
      if (row['key'] == 'progress' &&
          (value is! Map || value.values.any((v) => v is! bool))) {
        throw const FormatException('Invalid progress');
      }
      rows.add({'key': row['key'], 'value': row['value']});
    }
    await File(
      p.join(
        home.path,
        'before-import-${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    ).writeAsString(await export(), flush: true);
    await db.transaction((t) async {
      await t.delete('personal');
      for (final row in rows) {
        await t.insert(
          'personal',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}

const sections = [
  'All',
  'Companions',
  'Recipes',
  'Ingredients',
  'Foraging',
  'Characters',
  'Fish',
  'Gems',
  'Crafting',
  'Clothing',
  'Furniture',
  'Memories',
  'Timebending',
  'Board Game',
  'Snippets',
  'Mounts',
  'Exhibition',
  'Quests',
  'Events',
  'Star Paths',
  'Shops',
  'Guides',
];
String sectionFor(String title, String categories) {
  final s = categories.toLowerCase();
  const mapping = {
    'Companions': ['critter', 'companion'],
    'Recipes': ['meal', 'recipe', 'appetizer', 'entrée', 'dessert'],
    'Ingredients': ['ingredient', 'vegetable', 'fruit', 'grain', 'spice'],
    'Foraging': ['foraging', 'flower', 'wood'],
    'Characters': ['character'],
    'Fish': ['fish', 'seafood'],
    'Gems': ['gem'],
    'Crafting': ['crafting', 'refined material'],
    'Clothing': ['clothing', 'costume'],
    'Furniture': ['furniture'],
    'Memories': ['memor'],
    'Timebending': ['timebending'],
    'Board Game': ['scramblecoin', 'board game'],
    'Snippets': ['snippet'],
    'Mounts': ['mount'],
    'Exhibition': ['exhibition'],
    'Quests': ['quest'],
    'Events': ['event'],
    'Star Paths': ['star path'],
    'Shops': ['shop', 'stall'],
  };
  for (final e in mapping.entries) {
    if (e.value.any(s.contains)) return e.key;
  }
  return 'Guides';
}

// Weekly intervals use local wall-clock minutes. Overnight windows spill into the next day.
bool inWindow(DateTime date, int weekday, int start, int end) {
  final minute = date.hour * 60 + date.minute;
  if (end > start) {
    return date.weekday == weekday && minute >= start && minute < end;
  }
  return (date.weekday == weekday && minute >= start) ||
      (date.weekday == weekday % 7 + 1 && minute < end);
}

void validateLayouts(dynamic value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException('Invalid layouts');
  }
  for (final layout in value) {
    if (layout is! Map ||
        layout['name'] is! String ||
        layout['plots'] is! List) {
      throw const FormatException('Invalid layout');
    }
    final width = layout['width'] ?? 32, height = layout['height'] ?? 32;
    if (width is! int ||
        height is! int ||
        width < 1 ||
        width > 256 ||
        height < 1 ||
        height > 256) {
      throw const FormatException('Invalid map dimensions');
    }
    if (layout['blocked'] != null &&
        (layout['blocked'] is! List ||
            (layout['blocked'] as List).any(
              (v) => v is! int || v < 0 || v >= width * height,
            ))) {
      throw const FormatException('Invalid blocked cells');
    }
    for (final well in layout['wells'] ?? []) {
      if (well is! Map || ['x', 'y', 'w', 'h'].any((k) => well[k] is! num)) {
        throw const FormatException('Invalid well');
      }
      if (well['x'] < 0 ||
          well['y'] < 0 ||
          well['w'] < 1 ||
          well['h'] < 1 ||
          well['x'] + well['w'] > width ||
          well['y'] + well['h'] > height) {
        throw const FormatException('Well outside map');
      }
    }
    for (final plot in layout['plots']) {
      if (plot is! Map || plot['crop'] is! String || plot['notes'] is! String) {
        throw const FormatException('Invalid plot');
      }
      for (final key in ['x', 'y', 'w', 'h', 'color']) {
        if (plot[key] is! num) {
          throw const FormatException('Invalid plot coordinate');
        }
      }
      if (plot['w'] < 1 ||
          plot['h'] < 1 ||
          plot['x'] < 0 ||
          plot['y'] < 0 ||
          plot['x'] + plot['w'] > (layout['width'] ?? 32) ||
          plot['y'] + plot['h'] > (layout['height'] ?? 32) ||
          plot['color'] < 0 ||
          plot['color'] > 4 ||
          plot['color'] is! int) {
        throw const FormatException('Plot outside grid');
      }
    }
  }
}
