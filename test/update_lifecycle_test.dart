import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/updater.dart';

void main() {
  test('helper startup failure returns an error before app shutdown', () async {
    final dir = Directory.systemTemp.createTempSync('helper startup failure ');
    final updater = AppUpdater();
    try {
      final original = File(p.join(dir.path, 'installed.exe'))
        ..writeAsStringSync('original');
      File(p.join(dir.path, 'apply-update.ps1'))
          .writeAsStringSync("throw 'Intentional startup failure'");
      final config = File(p.join(dir.path, 'update.json'))
        ..writeAsStringSync('{}');
      await expectLater(
        updater.apply(config, startupTimeout: const Duration(seconds: 3)),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('app will stay open'),
          ),
        ),
      );
      expect(original.readAsStringSync(), 'original');
      expect(File(p.join(dir.path, 'cancelled')).existsSync(), true);
      expect(File(p.join(dir.path, 'helper-ready.json')).existsSync(), false);
    } finally {
      updater.client.close();
      expect(
        p.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path),
        true,
      );
      dir.deleteSync(recursive: true);
    }
  }, skip: !Platform.isWindows);
  for (final crash in [false, true]) {
    test(
      'Windows updater survives parent exit and ${crash ? 'rolls back a failed restart' : 'restarts the installed executable'}',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'update lifecycle ș-test ',
        );
        try {
          final app = Directory(p.join(dir.path, 'app with spaces'))
            ..createSync();
          final staged = Directory(p.join(dir.path, 'staged'))..createSync();
          final fixture = File(p.join(dir.path, 'fixtures.ps1'));
          String source(String version, bool broken) =>
              '''
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
public class UpdateFixture {
 public static void Main(string[] args) {
  File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"restarted.txt"),"$version");
  if(Boolean.Parse("${broken ? 'True' : 'False'}")) { Environment.Exit(7); return; }
  foreach(string arg in args) if(arg.StartsWith("--update-ready=")) {
    File.WriteAllText(arg.Substring(15),"{\\"pid\\":"+Process.GetCurrentProcess().Id+"}");
  }
  Thread.Sleep(1200);
 }
}
''';
          fixture.writeAsStringSync(
            '\ufeff'
            '''
\$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
${source('old', false)}
"@ -OutputAssembly ${powershellLiteral(p.join(app.path, 'dreamlight_companion.exe'))} -OutputType WindowsApplication
Add-Type -TypeDefinition @"
${source('new', crash).replaceAll('UpdateFixture', 'NewFixture')}
"@ -OutputAssembly ${powershellLiteral(p.join(staged.path, 'dreamlight_companion.exe'))} -OutputType WindowsApplication
''',
          );
          final compiler = await Process.run('powershell.exe', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            fixture.path,
          ]);
          expect(
            compiler.exitCode,
            0,
            reason: '${compiler.stdout}\n${compiler.stderr}',
          );
          final old = File(p.join(app.path, 'dreamlight_companion.exe'))
              .readAsBytesSync();
          File(p.join(staged.path, 'new-only.txt')).writeAsStringSync('new');
          File(p.join(dir.path, 'apply-update.ps1'))
              .writeAsStringSync(updateHelper);
          final config = File(p.join(dir.path, 'update.json'));
          config.writeAsStringSync(
            jsonEncode({
              'application': app.path,
              'staged': staged.path,
              'backup': p.join(dir.path, 'backup'),
              'log': p.join(dir.path, 'update.log'),
              'startupReady': p.join(dir.path, 'application-started.json'),
              'files': ['dreamlight_companion.exe', 'new-only.txt'],
            }),
          );
          final driver = File(p.join(dir.path, 'driver.dart'))
            ..writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'package:dreamlight_companion/updater.dart';
Future<void> main(List<String> arguments) async {
 final file=File(arguments.single);
 final config=jsonDecode(file.readAsStringSync());config['pid']=pid;
 file.writeAsStringSync(jsonEncode(config));
 await AppUpdater().apply(file);
 exit(0);
}
''');
          final sdk = Platform.environment['FLUTTER_ROOT'];
          final dart = sdk == null
              ? p.normalize(
                  p.join(
                    p.dirname(Platform.resolvedExecutable),
                    '..',
                    '..',
                    '..',
                    'dart-sdk',
                    'bin',
                    'dart.exe',
                  ),
                )
              : p.join(sdk, 'bin', 'cache', 'dart-sdk', 'bin', 'dart.exe');
          expect(File(dart).existsSync(), true, reason: dart);
          final parent = await Process.run(dart, [
            '--packages=${p.absolute('.dart_tool/package_config.json')}',
            driver.path,
            config.path,
          ]).timeout(const Duration(seconds: 35));
          expect(
            parent.exitCode,
            0,
            reason: '${parent.stdout}\n${parent.stderr}',
          );
          Map<String, dynamic> state = {};
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (DateTime.now().isBefore(deadline)) {
            final status = File(p.join(dir.path, 'status.json'));
            if (status.existsSync()) {
              try {
                state = Map<String, dynamic>.from(
                  jsonDecode(status.readAsStringSync()),
                );
              } on FormatException {
                // Retry while the helper completes its status file.
              }
              if (['restarted', 'rolled_back'].contains(state['phase'])) {
                break;
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(
            state['phase'],
            crash ? 'rolled_back' : 'restarted',
            reason: File(p.join(dir.path, 'update.log')).readAsStringSync(),
          );
          final marker = File(p.join(app.path, 'restarted.txt'));
          for (
            int i = 0;
            i < 30 &&
                (!marker.existsSync() ||
                    marker.readAsStringSync() != (crash ? 'old' : 'new'));
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(marker.readAsStringSync(), crash ? 'old' : 'new');
          if (crash) {
            expect(
              File(p.join(app.path, 'dreamlight_companion.exe'))
                  .readAsBytesSync(),
              old,
            );
            expect(File(p.join(app.path, 'new-only.txt')).existsSync(), false);
          }
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        } finally {
          expect(
            p.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path),
            true,
          );
          for (int attempt = 0; attempt < 30 && dir.existsSync(); attempt++) {
            try {
              dir.deleteSync(recursive: true);
            } on FileSystemException {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
        }
      },
      skip: !Platform.isWindows,
    );
  }
}
