import 'dart:io';
import 'dart:convert';

import 'package:dreamlight_companion/farm_model.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/planner.dart';
import 'package:dreamlight_companion/store.dart';

void main() {
  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('planner persists a crop on ${size.width}px screen', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('planner-test-');
      final store = Store();
      await tester.runAsync(() => store.open(directory: dir));
      final original = newLayout('Saved island', 'Plaza Island');
      original['wells'] = [
        {'x': 4, 'y': 8, 'w': 6, 'h': 6},
        {'x': 0, 'y': 0, 'w': 6, 'h': 6},
      ];
      await tester.runAsync(() => store.set('layouts', [original]));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Planner(store: store, crops: const ['Pumpkin']),
          ),
        ),
      );
      for (
        int attempt = 0;
        attempt < 50 && find.text('Add crop plot').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.text('Add crop plot'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Wishing well'), findsOneWidget);
      expect(find.text('Add well'), findsNothing);
      final backups = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('before-well-repair'))
          .toList();
      expect(backups.length, 1);
      expect(
        jsonDecode(backups.single.readAsStringSync())[0]['wells'].length,
        2,
      );
      await tester.longPress(find.text('Wishing well'));
      await tester.pumpAndSettle();
      expect(find.text('Wishing well'), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Wishing well')),
      );
      for (int i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add crop plot'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Pumpkin');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final saved = await tester.runAsync(() => store.get('layouts'));
      expect(saved[0]['plots'][0]['crop'], 'Pumpkin');
      expect(saved[0]['plots'][0]['w'], 4);
      expect(saved[0]['wells'].length, 1);
      expect(saved[0]['wells'][0]['x'], 6);
      expect(saved[0]['wells'][0]['y'], 8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => store.db.close());
      dir.deleteSync(recursive: true);
    });
  }
}
