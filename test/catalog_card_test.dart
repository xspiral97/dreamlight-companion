import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/catalog_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> rabbit, kingfish;
  setUpAll(() {
    final data = jsonDecode(File('assets/catalog.json').readAsStringSync());
    rabbit = Map<String, dynamic>.from(
      jsonDecode(
        (data['records'] as List).firstWhere(
          (r) => r['title'] == 'Classic Rabbit',
        )['details'],
      ),
    );
    kingfish = Map<String, dynamic>.from(
      jsonDecode(
        (data['records'] as List).firstWhere(
          (r) => r['title'] == 'Kingfish',
        )['details'],
      ),
    );
  });
  test('companion schedule classifies now and before opening correctly', () {
    expect(
      companionAvailability(rabbit, DateTime(2026, 11, 8, 14)),
      CompanionAvailability.available,
    );
    expect(
      companionAvailability(rabbit, DateTime(2026, 11, 8, 11)),
      CompanionAvailability.unavailable,
    );
    expect(todayHours(rabbit, DateTime(2026, 11, 8, 14)), '12 PM to 12 AM');
    expect(
      companionAvailability({}, DateTime.now()),
      CompanionAvailability.unknown,
    );
  });
  for (final section in ['Furniture', 'Fish', 'Companions']) {
    testWidgets('compact $section card fits a narrow mobile column', (
      tester,
    ) async {
      final data = section == 'Fish'
          ? kingfish
          : section == 'Companions'
          ? rabbit
          : <String, dynamic>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 170,
                height: section == 'Furniture' ? 128 : 216,
                child: CatalogCard(
                  title: section == 'Fish'
                      ? 'Kingfish'
                      : section == 'Companions'
                      ? 'Classic Rabbit'
                      : 'Acorn Lantern',
                  categories: 'Furniture · Honeyglow Woods',
                  section: section,
                  data: data,
                  image: null,
                  now: DateTime(2026, 11, 8, 14),
                  collected: false,
                  onOpen: () {},
                  onCollected: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (section == 'Fish') {
        expect(find.textContaining('Ripple:'), findsOneWidget);
        expect(find.textContaining('Weather:'), findsOneWidget);
        expect(find.textContaining('Zone:'), findsOneWidget);
      }
      if (section == 'Companions') {
        expect(find.text('Available now'), findsOneWidget);
        expect(find.textContaining('Peaceful Meadow'), findsOneWidget);
      }
    });
  }
}
