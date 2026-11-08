import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/store.dart';
import 'package:dreamlight_companion/timetable.dart';
import 'package:dreamlight_companion/catalog_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final snapshot = jsonDecode(File('assets/catalog.json').readAsStringSync());
  final rows = (snapshot['records'] as List)
      .map((r) => Map<String, Object?>.from(r))
      .toList();
  Map<String, dynamic> details(String title) => jsonDecode(
    rows.firstWhere((r) => r['title'] == title)['details'] as String,
  );
  test(
    'collections do not leak Exhibition requirements into companion cards',
    () {
      final companions = rows
          .where(
            (r) => matchesSection(
              'Companions',
              r['title'] as String,
              r['categories'] as String,
            ),
          )
          .toList();
      expect(companions.length, 224);
      expect(
        companions.map((r) => r['title']).toSet().length,
        companions.length,
      );
      expect(
        rows.where((r) => r['title'] == 'Black Sea Turtle').length,
        greaterThan(1),
      );
      expect(
        companions.where((r) => r['title'] == 'Black Sea Turtle').length,
        1,
      );
      expect(
        matchesSection('Furniture', '', '["Crafting","Furniture Sets"]'),
        true,
      );
      expect(
        matchesSection('Crafting', '', '["Crafting","Furniture Sets"]'),
        true,
      );
    },
  );
  test('every ingredient, recipe and character has reference metadata', () {
    for (final pair in {
      'Ingredients': 'ingredient',
      'Recipes': 'recipe',
      'Characters': 'characterSchedule',
    }.entries) {
      final collection = rows.where(
        (r) => matchesSection(
          pair.key,
          r['title'] as String,
          r['categories'] as String,
        ),
      );
      expect(collection, isNotEmpty);
      for (final row in collection) {
        final d = jsonDecode(row['details'] as String);
        expect(d[pair.value], isNotNull, reason: row['title'] as String);
        if (pair.key == 'Characters') expect(d[pair.value]['hours'].length, 24);
      }
    }
    expect(details('Cabbage')['ingredient']['locations'], 'Wild Tangle');
    expect(details('Chocolate Ice Cream')['recipe']['ingredients'], [
      'Cocoa Bean',
      'Sugarcane',
      'Milk',
      'Slush Ice',
    ]);
  });
  test('events include Star Paths, permanent and dated records with inclusive end date', () {
    expect(
      rows
          .where(
            (r) => matchesSection(
              'Events',
              r['title'] as String,
              r['categories'] as String,
            ),
          )
          .length,
      greaterThan(40),
    );
    final path = details('Seafaring Star Path');
    expect(path['blocks'], isNotEmpty);
    expect(
      eventStatus(path['event'], DateTime(2026, 12, 1, 23, 59)),
      'Current',
    );
    expect(eventStatus(path['event'], DateTime(2026, 12, 2)), 'Past');
    expect(eventStatus(path['event'], DateTime(2026, 10, 20)), 'Upcoming');
    expect(
      eventStatus(
        details("Astronomer's Journey Star Path")['event'],
        DateTime(2030),
      ),
      'Permanent',
    );
  });
  for (final companion in [false, true]) {
    for (final size in [const Size(390, 600), const Size(1200, 700)]) {
      testWidgets(
        'timetable fits $size companions=$companion and highlights local hour',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final title = companion ? 'Classic Rabbit' : 'Aladdin';
          final row = rows.firstWhere(
            (r) =>
                r['title'] == title &&
                matchesSection(
                  companion ? 'Companions' : 'Characters',
                  title,
                  r['categories'] as String,
                ),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ActivityTimetable(
                  rows: [row],
                  companions: companion,
                  now: DateTime(2026, 11, 8, 14, 25),
                  zone: 'Device local',
                  onOpen: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Sunday 14:25'), findsOneWidget);
          expect(
            find.byKey(ValueKey('current-hour-${row['id']}')),
            findsOneWidget,
          );
          expect(
            tester
                .getRect(find.byKey(ValueKey('current-hour-${row['id']}')))
                .left,
            lessThan(size.width),
          );
          expect(
            find.textContaining(companion ? 'Peaceful Meadow' : 'Now:'),
            findsOneWidget,
          );
          if (companion) {
            await tester.tap(find.byType(DropdownButton<int>));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Monday').last);
            await tester.pumpAndSettle();
            expect(find.text('Sunday'), findsNothing);
            await tester.tap(find.text('Jump to now'));
            await tester.pumpAndSettle();
            expect(find.text('Sunday'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final title in ['Cabbage', 'Chocolate Ice Cream']) {
    testWidgets('$title card exposes zone or ingredients without opening', (
      tester,
    ) async {
      final ingredient = title == 'Cabbage';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 170,
              height: ingredient ? 160 : 184,
              child: CatalogCard(
                title: title,
                categories: '',
                section: ingredient ? 'Ingredients' : 'Recipes',
                data: details(title),
                image: null,
                now: DateTime(2026),
                collected: false,
                onOpen: () {},
                onCollected: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(
        find.textContaining(ingredient ? 'Wild Tangle' : 'Cocoa Bean'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
