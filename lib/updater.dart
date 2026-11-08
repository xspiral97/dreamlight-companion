import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

const releaseRepository = 'xspiral97/dreamlight-companion';
const windowsAsset = 'DreamlightCompanion-Windows.zip';
const androidAsset = 'DreamlightCompanion-Android.apk';
bool newerVersion(String candidate, String current) {
  try {
    return Version.parse(candidate.replaceFirst(RegExp(r'^v'), '')) >
        Version.parse(current);
  } catch (_) {
    return false;
  }
}

class AppRelease {
  final String version, notes, url;
  final Map<String, dynamic> asset;
  AppRelease(this.version, this.notes, this.url, this.asset);
}

class AppUpdater {
  final http.Client client;
  AppUpdater({http.Client? client}) : client = client ?? http.Client();
  Future<AppRelease?> check(String current) async {
    final response = await client
        .get(
          Uri.https(
            'api.github.com',
            '/repos/$releaseRepository/releases/latest',
          ),
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'DreamlightCompanion',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception(
        'GitHub update check failed (${response.statusCode}). Try again later.',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['draft'] == true ||
        data['prerelease'] == true ||
        !newerVersion(data['tag_name'], current)) {
      return null;
    }
    final assets = (data['assets'] as List)
        .where(
          (a) =>
              a['name'] == (Platform.isAndroid ? androidAsset : windowsAsset),
        )
        .toList();
    if (assets.length != 1) {
      throw Exception(
        'This release has no update package for this platform yet.',
      );
    }
    return AppRelease(
      data['tag_name'],
      data['body'] ?? '',
      data['html_url'],
      Map<String, dynamic>.from(assets.single),
    );
  }

  Future<File> stage(
    AppRelease release,
    Directory support,
    void Function(String) report, {
    Directory? application,
  }) async {
    if (!Platform.isWindows && application == null) {
      throw UnsupportedError('In-app replacement is supported on Windows.');
    }
    final app = application ?? File(Platform.resolvedExecutable).parent;
    final probe = File(p.join(app.path, '.dreamlight-update-write-test'));
    try {
      await probe.writeAsString('test', flush: true);
      await probe.delete();
    } catch (_) {
      throw Exception(
        'The application folder is read-only. Move the portable app to a writable folder.',
      );
    }
    final url = Uri.parse(release.asset['browser_download_url']);
    if (url.scheme != 'https' ||
        url.host != 'github.com' ||
        !url.path.startsWith('/$releaseRepository/releases/download/')) {
      throw const FormatException('Unexpected update source');
    }
    final digest = release.asset['digest']?.toString() ?? '';
    if (!RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'The release has no verifiable SHA-256 digest.',
      );
    }
    final work = await Directory(p.join(support.path, 'updates'))
        .create(recursive: true);
    final dir = await Directory(
      p.join(work.path, 'update-${DateTime.now().microsecondsSinceEpoch}'),
    ).create();
    final zip = File(p.join(dir.path, 'release.zip'));
    final response = await client
        .send(http.Request('GET', url))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }
    int received = 0;
    final sink = zip.openWrite();
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received > 250 * 1024 * 1024) {
          throw const FormatException('Update package is too large');
        }
        sink.add(chunk);
        report(
          'Downloading update: ${(received / 1048576).toStringAsFixed(1)} MB',
        );
      }
    } finally {
      await sink.close();
    }
    if (sha256.convert(await zip.readAsBytes()).toString().toLowerCase() !=
        digest.substring(7).toLowerCase()) {
      throw const FormatException(
        'Update checksum failed. The installed application was not changed.',
      );
    }
    report('Verified download. Preparing update…');
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final stage = Directory(p.join(dir.path, 'staged'));
    await stage.create();
    final names = <String>[];
    int total = 0;
    for (final entry in archive.files) {
      final name = entry.name.replaceAll('\\', '/');
      final destination = p.normalize(p.join(stage.path, name));
      if (entry.isSymbolicLink ||
          p.isAbsolute(name) ||
          !p.isWithin(stage.path, destination) ||
          name.split('/').contains('..') ||
          name.contains(':')) {
        throw const FormatException('Unsafe update archive path');
      }
      if (!entry.isFile) continue;
      total += entry.size;
      if (total > 500 * 1024 * 1024) {
        throw const FormatException('Expanded update is too large');
      }
      final file = File(destination);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content);
      names.add(name);
    }
    for (final required in [
      'dreamlight_companion.exe',
      'flutter_windows.dll',
      'data/app.so',
      'sqlite3.dll',
    ]) {
      if (!names.contains(required)) {
        throw FormatException('Incomplete update: missing $required');
      }
    }
    final config = File(p.join(dir.path, 'update.json'));
    await config.writeAsString(
      jsonEncode({
        'pid': pid,
        'application': app.path,
        'staged': stage.path,
        'backup': p.join(dir.path, 'backup'),
        'log': p.join(dir.path, 'update.log'),
        'files': names,
      }),
    );
    await File(p.join(dir.path, 'apply-update.ps1'))
        .writeAsString(updateHelper);
    return config;
  }

  Future<File> downloadAndroid(
    AppRelease release,
    Directory support,
    void Function(String) report,
  ) async {
    final uri = Uri.parse(release.asset['browser_download_url']);
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        !uri.path.startsWith('/$releaseRepository/releases/download/')) {
      throw const FormatException('Unexpected update source');
    }
    final digest = release.asset['digest']?.toString() ?? '';
    if (!RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Missing update checksum');
    }
    final directory = await Directory(p.join(support.path, 'updates'))
        .create(recursive: true);
    final apk = File(
      p.join(
        directory.path,
        'update-${DateTime.now().microsecondsSinceEpoch}.apk',
      ),
    );
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200) {
      throw Exception('APK download failed (${response.statusCode})');
    }
    final sink = apk.openWrite();
    int received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received > 250 * 1024 * 1024) {
          throw const FormatException('Update is too large');
        }
        sink.add(chunk);
        report(
          'Downloading update: ${(received / 1048576).toStringAsFixed(1)} MB',
        );
      }
    } finally {
      await sink.close();
    }
    if (sha256.convert(await apk.readAsBytes()).toString() !=
        digest.substring(7).toLowerCase()) {
      throw const FormatException('APK checksum mismatch');
    }
    return apk;
  }

  Future<void> apply(File config) async {
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      p.join(config.parent.path, 'apply-update.ps1'),
      '-ConfigPath',
      config.path,
    ], mode: ProcessStartMode.detached);
  }
}

const updateHelper = r'''
param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference='Stop'
$config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$changed=@()
try {
 Wait-Process -Id $config.pid -Timeout 90 -ErrorAction SilentlyContinue
 if(Get-Process -Id $config.pid -ErrorAction SilentlyContinue){throw 'Application did not exit; no files were replaced.'}
 foreach($name in $config.files){
  $source=Join-Path $config.staged $name
  $target=Join-Path $config.application $name
  $backup=Join-Path $config.backup $name
  if(Test-Path -LiteralPath $target){
   New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
   Copy-Item -LiteralPath $target -Destination $backup -Force
   $changed+=@{Target=$target;Backup=$backup}
  }
  New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Force
 }
 'Update installed successfully.' | Set-Content -LiteralPath $config.log
}catch{
 $failure=$_.Exception.Message
 foreach($entry in $changed){Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force -ErrorAction Continue}
 "Update failed and existing files were restored: $failure" | Set-Content -LiteralPath $config.log
}finally{
 if($config.restart -ne $false -and -not(Get-Process -Id $config.pid -ErrorAction SilentlyContinue)){
  Start-Process -FilePath (Join-Path $config.application 'dreamlight_companion.exe') -WorkingDirectory $config.application -WindowStyle Normal
 }
}
''';
