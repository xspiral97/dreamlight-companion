import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/updater.dart';

void main() {
  test(
    'published release can be discovered, downloaded, verified and staged',
    () async {
      final work = Directory.systemTemp.createTempSync('release-check-'),
          app = Directory.systemTemp.createTempSync('release-app-');
      final updater = AppUpdater();
      try {
        final release = await updater.check('0.1.0');
        expect(release, isNotNull);
        expect(newerVersion(release!.version, '0.1.0'), true);
        final config = await updater.stage(
          release,
          work,
          (_) {},
          application: app,
        );
        expect(config.existsSync(), true);
        expect(
          await updater.check(release.version.replaceFirst('v', '')),
          isNull,
        );
      } finally {
        updater.client.close();
        work.deleteSync(recursive: true);
        app.deleteSync(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('LIVE_RELEASE'),
  );
}
