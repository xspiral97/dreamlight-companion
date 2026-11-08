import 'dart:convert';
import 'dart:io';

import 'catalog_data.dart';
import 'item_image.dart';
import 'wiki_http.dart';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'store.dart';
import 'schedule.dart';
import 'catalog_parser.dart';

class Wiki {
  final Store store;
  Wiki(this.store, {http.Client? client})
    : client = client ?? WikiPacedClient();
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
    if (response.statusCode == 429) {
      throw Exception(
        'The wiki is rate-limiting page requests. Catalog refresh uses the shared feed; wait before retrying this page.',
      );
    }
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

  static const feedUrl =
      'https://raw.githubusercontent.com/xspiral97/dreamlight-companion/main/data/catalog.json.gz';
  Future<SyncReport> sync(void Function(String) report) async {
    report('Downloading shared catalog (one request; no wiki crawl)...');
    final response = await client
        .get(Uri.parse(feedUrl))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception(
        'Catalog feed HTTP ${response.statusCode}. Your cached catalog is unchanged.',
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.length > 25 * 1024 * 1024) {
      throw const FormatException('Catalog feed is too large');
    }
    final decoded = bytes.length > 2 && bytes[0] == 31 && bytes[1] == 139
        ? gzip.decode(bytes)
        : bytes;
    if (decoded.length > 100 * 1024 * 1024) {
      throw const FormatException('Expanded catalog is too large');
    }
    final snapshot = validateCatalogSnapshot(jsonDecode(utf8.decode(decoded)));
    report('Saving ${snapshot['records'].length} catalog entries...');
    await store.importCatalog(snapshot);
    final date = DateTime.now().toUtc().toIso8601String();
    final failures = (snapshot['failures'] as List? ?? [])
        .map((s) => s.toString())
        .toList();
    final result = SyncReport(
      (snapshot['sources'] as List).length,
      (snapshot['records'] as List).length,
      failures,
    );
    await store.db.insert('meta', {
      'key': 'lastSync',
      'value': date,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await store.db.insert('meta', {
      'key': 'syncReport',
      'value': '$result Data published ${snapshot['generatedAt']}.',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    report('$result Data published ${snapshot['generatedAt']}.');
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
    final image = itemImage(doc);
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
    final previous = row['details'] == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(row['details'] as String));
    final result = <String, dynamic>{
      ...previous,
      'metadataVersion': 2,
      'summary': false,
      'schedule': parseSchedule(doc).isNotEmpty
          ? parseSchedule(doc)
          : previous['schedule'] ?? [],
      'fields': {...?(previous['fields'] as Map?), ...fields},
      'image': image == null ? null : Uri.parse(base).resolve(image).toString(),
      'blocks': blocks,
      'links': links,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'revision': data['parse']['revid'],
    };
    if (previous['fishing'] is Map || fields.containsKey('Ripple Color:')) {
      final previousFish = Map<String, dynamic>.from(previous['fishing'] ?? {});
      final paragraphs = doc
          .querySelectorAll('.mw-parser-output > p')
          .take(5)
          .map((p) => p.text.trim().replaceAll(RegExp(r'\s+'), ' '))
          .toList();
      final timeParagraph = paragraphs
          .where(
            (p) => RegExp(r'\d\s*(am|pm)', caseSensitive: false).hasMatch(p),
          )
          .join(' ');
      final ranges = RegExp(
        r'(\d{1,2}(?::\d{2})?\s*(?:am|pm))\s*(?:-|–|to|and)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm))',
        caseSensitive: false,
      ).allMatches(timeParagraph).map((m) => '${m[1]} – ${m[2]}').join('; ');
      result['fishing'] = {
        ...previousFish,
        'ripples':
            fields['Ripple Color:'] ?? previousFish['ripples'] ?? 'Unknown',
        'weather':
            fields['Weather:'] ??
            previousFish['weather'] ??
            'No weather restriction listed',
        'locations': fields['Found:'] ?? previousFish['locations'] ?? 'Unknown',
        'time': ranges.isEmpty
            ? previousFish['time'] ?? 'No time restriction listed'
            : ranges,
        'conditions': paragraphs.join('\n\n'),
      };
    }
    await store.db.update(
      'catalog',
      {'details': jsonEncode(result)},
      where: 'id=?',
      whereArgs: [row['id']],
    );
    return result;
  }
}
