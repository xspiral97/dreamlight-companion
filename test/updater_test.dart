import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dreamlight_companion/updater.dart';

void main() {
  test('updater never downgrades or reinstalls same version', () {
    expect(newerVersion('v0.3.0', '0.2.0'), true);
    expect(newerVersion('v0.2.0', '0.2.0'), false);
    expect(newerVersion('v0.1.0', '0.2.0'), false);
    expect(newerVersion('invalid', '0.2.0'), false);
  });
  test('unpublished releases are a normal up-to-date state', () async {
    final updater = AppUpdater(
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await updater.check('0.2.0'), isNull);
    updater.client.close();
  });
  for (final unsafe in [false, true]) {
    test(
      'staging ${unsafe ? 'rejects zip traversal' : 'checks hash and does not modify installed files'}',
      () async {
        final dir = Directory.systemTemp.createTempSync('updater-test-'),
            app = Directory.systemTemp.createTempSync('updater-app-');
        final archive = Archive();
        for (final name in [
          'dreamlight_companion.exe',
          'flutter_windows.dll',
          'sqlite3.dll',
          'data/app.so',
        ]) {
          archive.addFile(ArchiveFile(name, 3, utf8.encode('new')));
        }
        if (unsafe) {
          archive.addFile(ArchiveFile('../escape.txt', 3, utf8.encode('bad')));
        }
        final bytes = ZipEncoder().encode(archive);
        final updater = AppUpdater(
          client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        );
        await File('${app.path}/dreamlight_companion.exe').writeAsString('old');
        final release = AppRelease('v0.3.0', '', '', {
          'browser_download_url':
              'https://github.com/$releaseRepository/releases/download/v0.3.0/$windowsAsset',
          'digest': 'sha256:${sha256.convert(bytes)}',
        });
        try {
          if (unsafe) {
            await expectLater(
              updater.stage(release, dir, (_) {}, application: app),
              throwsFormatException,
            );
          } else {
            final config = await updater.stage(
              release,
              dir,
              (_) {},
              application: app,
            );
            expect(await config.exists(), true);
          }
          expect(
            await File('${app.path}/dreamlight_companion.exe').readAsString(),
            'old',
          );
        } finally {
          updater.client.close();
          dir.deleteSync(recursive: true);
          app.deleteSync(recursive: true);
        }
      },
    );
  }
}
