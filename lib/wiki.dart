import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'store.dart';
import 'schedule.dart';
import 'catalog_parser.dart';

class Wiki {
  final Store store;
  Wiki(this.store, {http.Client? client}) : client = client ?? http.Client();
  static const base = 'https://dreamlightvalleywiki.com';
  final http.Client client;
  Future<Map<String, dynamic>> api(Map<String, String> params) async {
    final response = await client
        .get(
          Uri.parse('$base/api.php')
              .replace(queryParameters: {...params, 'format': 'json'}),
          headers: {
            'User-Agent':
                'DreamlightCompanion/0.2 (personal offline encyclopedia)',
          },
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw Exception(
        response.statusCode == 403
            ? 'Wiki blocked this request (HTTP 403). Your saved data is safe. Try again later or open the source in your browser.'
            : 'Wiki HTTP ${response.statusCode}',
      );
    }
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (result.containsKey('error')) throw Exception(result['error']);
    return result;
  }

  Future<SyncReport> sync(void Function(String) report) async {
    final sources = <String>{
      'Memories',
      'Characters',
      'Crafting',
      'Companions',
      'Fish',
      'Foraging',
      'Ingredients',
      'Meals',
      'Gems',
      'Clothing Sets',
      'Furniture Sets',
      'Timebending',
      'Board Game',
      'Snippets',
      'Mounts',
      'Exhibition',
    };
    try {
      final hub = await api({
        'action': 'parse',
        'page': 'Collections',
        'prop': 'text',
      });
      for (final card
          in html
              .parse(hub['parse']['text']['*'])
              .querySelectorAll('[data-ct-section]')) {
        final name = card.attributes['data-ct-section'];
        if (name != null && name.isNotEmpty) sources.add(name);
      }
    } catch (_) {
      /* Use the established collection pages if discovery is temporarily unavailable. */
    }
    final knownCategories = <String, Set<String>>{};
    for (final row in await store.catalog()) {
      knownCategories[row['id'] as String] = (jsonDecode(
        row['categories'] as String,
      ) as List).cast<String>().toSet();
    }
    final failures = <String>[];
    int records = 0, successful = 0;
    for (final source in sources) {
      report(
        'Refreshing $source ($successful/${sources.length} sources) · $records entries',
      );
      try {
        final data = await api({
          'action': 'parse',
          'page': 'Collections/$source',
          'prop': 'text',
        });
        final entries = parseCollection(source, data['parse']['text']['*']);
        if (entries.isEmpty) {
          throw const FormatException('Unrecognized collection structure');
        }
        await store.db.transaction((t) async {
          final batch = t.batch();
          for (final row in entries) {
            final id = row['id'] as String;
            final combined = knownCategories.putIfAbsent(id, () => {});
            combined.addAll(
              (jsonDecode(row['categories'] as String) as List).cast<String>(),
            );
            row['categories'] = jsonEncode(combined.toList());
            batch.rawInsert(
              'INSERT INTO catalog(id,title,categories,details) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,categories=excluded.categories,details=COALESCE(catalog.details,excluded.details)',
              [row['id'], row['title'], row['categories'], row['details']],
            );
          }
          await batch.commit(noResult: true);
        });
        successful++;
        records += entries.length;
      } catch (e) {
        failures.add('$source: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    try {
      final ingredients = await api({
        'action': 'parse',
        'page': 'Ingredients',
        'prop': 'text',
      });
      final crops = parsePlantableIngredients(
        ingredients['parse']['text']['*'],
      );
      if (crops.isEmpty) throw const FormatException('Unrecognized crop table');
      await store.db.insert('meta', {
        'key': 'plantableCrops',
        'value': jsonEncode(crops),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      failures.add('Plantable ingredients: $e');
    }
    final result = SyncReport(successful, records, failures);
    await store.db.insert('meta', {
      'key': 'syncReport',
      'value': result.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (successful == 0) {
      throw Exception(
        'No wiki sources could be refreshed. ${failures.take(2).join('; ')}',
      );
    }
    if (failures.isEmpty) {
      await store.db.insert('meta', {
        'key': 'lastSync',
        'value': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    report(result.toString());
    return result;
  }

  Future<Map<String, dynamic>> details(Map<String, Object?> row) async {
    final data = await api({
      'action': 'parse',
      'page': row['title'].toString(),
      'prop': 'text',
    });
    final doc = html.parse(data['parse']['text']['*']);
    final fields = <String, String>{};
    for (final tr in doc.querySelectorAll('#infobox tr')) {
      final cells = tr.children;
      if (cells.length == 2) {
        fields[cells[0].text.trim()] = cells[1].text.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
      }
    }
    for (final tr in doc.querySelectorAll('tr')) {
      final cells = tr.children;
      if (cells.length >= 2 &&
          ['Favorite', 'Liked'].contains(cells[0].text.trim())) {
        fields['${cells[0].text.trim()} food:'] = cells[1].text
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
      }
    }
    final image = doc.querySelector('#infobox-image img')?.attributes['src'];
    final blocks = <Map<String, String>>[];
    for (final el in doc.querySelectorAll(
      '.mw-parser-output > p, .mw-parser-output > h2, .mw-parser-output > h3, .mw-parser-output > ul, .mw-parser-output > ol, .mw-parser-output > table',
    )) {
      if (el.id == 'infobox') continue;
      final text = el.text.trim().replaceAll(RegExp(r'[ \t]+'), ' ');
      if (text.isNotEmpty) {
        blocks.add({'type': el.localName ?? 'p', 'text': text});
      }
    }
    final links = doc
        .querySelectorAll('a[title]')
        .where(
          (a) =>
              (a.attributes['href'] ?? '').startsWith('/') &&
              !(a.attributes['title'] ?? '').contains(':'),
        )
        .map((a) => a.attributes['title']!)
        .toSet()
        .toList();
    final result = <String, dynamic>{
      'schedule': parseSchedule(doc),
      'fields': fields,
      'image': image == null ? null : Uri.parse(base).resolve(image).toString(),
      'blocks': blocks,
      'links': links,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'revision': data['parse']['revid'],
    };
    await store.db.update(
      'catalog',
      {'details': jsonEncode(result)},
      where: 'id=?',
      whereArgs: [row['id']],
    );
    return result;
  }
}
