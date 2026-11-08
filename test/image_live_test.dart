import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/wiki_http.dart';

void main() {
  test('actual item photographs download and decode as images', () async {
    final dataset = jsonDecode(File('assets/catalog.json').readAsStringSync());
    final client = WikiPacedClient();
    try {
      for (final name in ['Acorn Lantern', 'Fugu', 'Classic Rabbit']) {
        final row = (dataset['records'] as List).firstWhere(
          (r) => r['title'] == name,
        );
        final details = jsonDecode(row['details']);
        final url = name == 'Acorn Lantern' ? details['image'] : row['image'];
        final response = await client.get(Uri.parse(url));
        expect(response.statusCode, 200, reason: 'Image for $name');
        final codec = await ui.instantiateImageCodec(response.bodyBytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThanOrEqualTo(48), reason: name);
        frame.image.dispose();
        codec.dispose();
      }
    } finally {
      client.close();
    }
  }, skip: !const bool.fromEnvironment('LIVE_IMAGES'));
}
