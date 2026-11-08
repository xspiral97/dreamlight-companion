import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/updater.dart';

void main() {
  for (final fail in [false, true]) {
    test(
      'Windows update helper ${fail ? 'restores existing files on copy failure' : 'replaces files after process exit'}',
      () async {
        final dir = Directory.systemTemp.createTempSync('helper-test-');
        try {
          final app = Directory('${dir.path}/app')..createSync(),
              stage = Directory('${dir.path}/staged')..createSync();
          File('${app.path}/dreamlight_companion.exe').writeAsStringSync('old');
          File('${stage.path}/dreamlight_companion.exe')
              .writeAsStringSync('new');
          final script = File('${dir.path}/helper.ps1')
            ..writeAsStringSync(updateHelper);
          final config = File('${dir.path}/config.json')
            ..writeAsStringSync(
              jsonEncode({
                'pid': 2147483647,
                'application': app.path,
                'staged': stage.path,
                'backup': '${dir.path}/backup',
                'log': '${dir.path}/update.log',
                'files': ['dreamlight_companion.exe', if (fail) 'missing.dll'],
                'restart': false,
              }),
            );
          final result = await Process.run('powershell.exe', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            script.path,
            '-ConfigPath',
            config.path,
          ]);
          expect(result.exitCode, 0, reason: result.stderr.toString());
          expect(
            File('${app.path}/dreamlight_companion.exe').readAsStringSync(),
            fail ? 'old' : 'new',
          );
          expect(
            File('${dir.path}/update.log').readAsStringSync(),
            contains(fail ? 'restored' : 'successfully'),
          );
        } finally {
          dir.deleteSync(recursive: true);
        }
      },
      skip: !Platform.isWindows,
    );
  }
}
