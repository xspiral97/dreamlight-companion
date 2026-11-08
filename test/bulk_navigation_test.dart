import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dreamlight_companion/main.dart';
import 'package:dreamlight_companion/store.dart';

void main() {
  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets(
      'recipe categories and filtered mark all persist on ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        PackageInfo.setMockInitialValues(
          appName: 'Dreamlight Companion',
          packageName: 'test',
          version: '0.5.0',
          buildNumber: '6',
          buildSignature: 'test',
        );
        final dir = Directory.systemTemp.createTempSync('bulk-ui-');
        final store = Store();
        await tester.runAsync(() async {
          await store.open(directory: dir);
          await store.db.insert('meta', {
            'key': 'lastSync',
            'value': DateTime.now().toIso8601String(),
          });
          await store.set('progress', {'unrelated': true});
          await store.set('fed:fox:2026-11-08', true);
          for (final item in [
            ['starter', 'Starter Recipe', 'Meals', 'Appetizers'],
            ['main', 'Main Recipe', 'Meals', 'Entrées'],
            ['sweet', 'Sweet Recipe', 'Meals', 'Desserts'],
            ['carrot', 'Carrot', 'Ingredients', ''],
            ['wood', 'Wood', 'Foraging', ''],
            ['character', 'Mickey Mouse', 'Characters', ''],
          ]) {
            await store.db.insert('catalog', {
              'id': item[0],
              'title': item[1],
              'categories': jsonEncode([item[2], 'Dreamlight Valley']),
              'details': jsonEncode({
                'recipe': {
                  'category': item[3],
                  'ingredients': ['Test ingredient'],
                },
                'ingredient': {'locations': 'Peaceful Meadow'},
              }),
            });
          }
        });
        await tester.pumpWidget(CompanionApp(store: store));
        Future<void> settleIo() async {
          for (int i = 0; i < 8; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }

        await settleIo();
        Future<void> navigate(String section) async {
          if (size.width < 800) {
            tester
                .state<ScaffoldState>(find.byType(Scaffold).first)
                .openDrawer();
            await tester.pumpAndSettle();
          }
          final target = find.widgetWithText(ListTile, section);
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        await navigate('Recipes');
        await tester.tap(find.widgetWithText(ChoiceChip, 'Appetizers'));
        await tester.pumpAndSettle();
        expect(find.text('Starter Recipe'), findsOneWidget);
        expect(find.text('Sweet Recipe'), findsNothing);
        expect(find.text('Main Recipe'), findsNothing);
        await tester.tap(find.text('Mark all'));
        await settleIo();
        final first = await tester.runAsync(() => store.get('progress'));
        expect(first['starter'], true);
        expect(first['sweet'], isNull);
        expect(first['main'], isNull);
        expect(first['unrelated'], true);
        await tester.tap(find.text('Undo'));
        await settleIo();
        expect(
          (await tester.runAsync(() => store.get('progress')))['starter'],
          false,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Desserts'));
        await tester.pumpAndSettle();
        expect(find.text('Sweet Recipe'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Entrées'));
        await tester.pumpAndSettle();
        expect(find.text('Main Recipe'), findsOneWidget);
        for (final category in ['Ingredients', 'Foraging', 'Characters']) {
          await navigate(category);
          await tester.tap(find.text('Mark all'));
          await settleIo();
        }
        final progress = await tester.runAsync(() => store.get('progress'));
        expect(progress['carrot'], true);
        expect(progress['wood'], true);
        expect(progress['character'], true);
        expect(progress['main'], isNull);
        expect(
          await tester.runAsync(() => store.get('fed:fox:2026-11-08')),
          true,
        );
        await tester.tap(find.text('Unmark all'));
        await settleIo();
        expect(
          (await tester.runAsync(() => store.get('progress')))['character'],
          false,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => store.db.close());
        dir.deleteSync(recursive: true);
      },
    );
  }
}
