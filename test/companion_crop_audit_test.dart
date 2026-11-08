import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/catalog_card.dart';
import 'package:dreamlight_companion/farm_model.dart';
import 'package:dreamlight_companion/item_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final snapshot = jsonDecode(File('assets/catalog.json').readAsStringSync());
  final companions = (snapshot['records'] as List)
      .where(
        (r) => (jsonDecode(r['categories']) as List).contains('Companions'),
      )
      .toList();
  Map<String, dynamic> data(String name) =>
      jsonDecode(companions.firstWhere((r) => r['title'] == name)['details']);
  test('all 90 wild companions have verified favorite and liked food', () {
    final wild = companions.where(
      (r) => jsonDecode(r['details'])['companion']['scheduled'] == true,
    );
    expect(wild.length, 90);
    for (final row in wild) {
      final value = jsonDecode(row['details']) as Map<String, dynamic>;
      expect(
        companionFood(value, 'Favorite'),
        isNot('Unknown'),
        reason: row['title'],
      );
      expect(
        companionFood(value, 'Liked'),
        isNot('Unknown'),
        reason: row['title'],
      );
      expect(value['companion']['feedingMethod'], isNotEmpty);
    }
    expect(
      companionFood(data('Golden Sunbird'), 'Favorite'),
      'Orange and Yellow Flowers',
    );
    expect(
      companionFood(data('Orchid Sunbird'), 'Favorite'),
      'Pink and Purple Flowers',
    );
    expect(
      companionFood(data('Red Sunbird'), 'Favorite'),
      'Blue and Red Flowers',
    );
    expect(
      companionFood(data('Turquoise Sunbird'), 'Favorite'),
      'Green and Pink Flowers',
    );
  });
  test('paid, path, quest and DLC acquisitions stay distinct', () {
    expect(data('BB-8')['companion']['acquisition']['tags'], ['Premium']);
    expect(data('Anger Raccoon')['companion']['acquisition']['tags'], [
      'Premium · Edition / Bundle',
    ]);
    expect(data('Butterfly Companion')['companion']['acquisition']['tags'], [
      'Star Path',
    ]);
    expect(data('Pua')['companion']['acquisition']['tags'], ['Quest']);
    expect(data('Ancient Robot')['companion']['acquisition']['tags'], [
      'Crafting',
    ]);
    expect(
      data('Black and White Capybara')['companion']['acquisition']['tags'],
      ['DLC'],
    );
    expect(data('Anxiety Squirrel')['companion']['acquisition']['tags'], [
      'Event / Promotion',
    ]);
    for (final row in companions) {
      final info = jsonDecode(row['details'])['companion']['acquisition'];
      expect(info['tags'], isNot(contains('Unknown')), reason: row['title']);
      expect(info['source'], startsWith('https://dreamlightvalleywiki.com/'));
    }
  });
  test(
    'all 58 audited crops have bundled decodable images and feed parity',
    () async {
      final crops =
          jsonDecode(File('assets/crops.json').readAsStringSync()) as List;
      expect(crops.length, 58);
      expect((await Crop.load()).length, 58);
      expect(
        crops.map((r) => r['name']).toSet(),
        (snapshot['plantableCrops'] as List).map((r) => r['name']).toSet(),
      );
      await initializeItemImages();
      for (final crop in crops) {
        expect(localItemImage(crop['imageSource']), crop['image']);
        final codec = await ui.instantiateImageCodec(
          File(crop['image']).readAsBytesSync(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0));
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
  for (final name in ['BB-8', 'Pua', 'Classic Rabbit', 'Golden Sunbird']) {
    testWidgets('$name shows food or acquisition on its card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 170,
              height: 304,
              child: CatalogCard(
                title: name,
                categories: '',
                section: 'Companions',
                data: data(name),
                image: null,
                now: DateTime(2026, 11, 8, 14),
                collected: false,
                onOpen: () {},
                onCollected: (_) {},
              ),
            ),
          ),
        ),
      );
      if (data(name)['companion']['scheduled'] == true) {
        expect(find.textContaining('Favorite:'), findsOneWidget);
        expect(find.textContaining('Liked:'), findsOneWidget);
      } else {
        expect(find.textContaining('Obtain:'), findsOneWidget);
        expect(find.text('Unlocked without wild feeding.'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
