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
        'ready': p.join(dir.path, 'helper-ready.json'),
        'status': p.join(dir.path, 'status.json'),
        'startupReady': p.join(dir.path, 'application-started.json'),
        'version': release.version,
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

  Future<void> apply(
    File config, {
    Duration startupTimeout = const Duration(seconds: 15),
  }) async {
    final shell = p.join(
      Platform.environment['SystemRoot'] ?? r'C:\Windows',
      'System32',
      'WindowsPowerShell',
      'v1.0',
      'powershell.exe',
    );
    final ready = File(p.join(config.parent.path, 'helper-ready.json'));
    final stderr = File(p.join(config.parent.path, 'launch.stderr.log'));
    final stdout = File(p.join(config.parent.path, 'launch.stdout.log'));
    if (await ready.exists()) await ready.delete();
    final cancelled = File(p.join(config.parent.path, 'cancelled'));
    if (await cancelled.exists()) await cancelled.delete();
    final invocation = powershellEncodedCommand(
      "\$ProgressPreference='SilentlyContinue'; & ${powershellLiteral(p.join(config.parent.path, 'apply-update.ps1'))} -ConfigPath ${powershellLiteral(config.path)}",
    );
    // A normal broker gives PowerShell valid standard handles. Launching it
    // directly with Dart's Windows detached modes can exit before the script runs.
    final broker =
        "\$ErrorActionPreference='Stop'; \$ProgressPreference='SilentlyContinue'; "
        "\$child=Start-Process -FilePath ${powershellLiteral(shell)} "
        "-ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand','$invocation') "
        "-WindowStyle Hidden -WorkingDirectory ${powershellLiteral(config.parent.path)} "
        "-RedirectStandardOutput ${powershellLiteral(stdout.path)} "
        "-RedirectStandardError ${powershellLiteral(stderr.path)} -PassThru; \$child.Id";
    final launch = await Process.start(shell, [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-EncodedCommand',
      powershellEncodedCommand(broker),
    ]);
    final launchOutput = StringBuffer();
    final launchErrors = StringBuffer();
    launch.stdout.transform(utf8.decoder).listen(launchOutput.write);
    launch.stderr.transform(utf8.decoder).listen(launchErrors.write);
    await launch.stdin.close();
    // Do not await the broker's exit: PowerShell may keep redirected stream
    // readers alive while the helper waits for this application to exit.
    final deadline = DateTime.now().add(startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await ready.exists()) {
        try {
          final result = jsonDecode(await ready.readAsString());
          if (result['pid'] is int &&
              result['pid'] > 0 &&
              result['phase'] == 'waiting_for_exit') {
            return;
          }
        } on FormatException {
          // The helper may still be completing the small acknowledgement file.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await cancelled.writeAsString('Helper startup was not acknowledged.');
    final error = await stderr.exists() ? await stderr.readAsString() : '';
    throw Exception(
      'Update helper did not confirm startup. The app will stay open. '
      '$error ${launchErrors.toString()} Logs: ${config.parent.path}',
    );
  }
}

String powershellLiteral(String value) => "'${value.replaceAll("'", "''")}'";
String powershellEncodedCommand(String value) => base64Encode([
  for (final unit in value.codeUnits) ...[unit & 255, unit >> 8],
]);

const updateHelper = r'''
param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$work=Split-Path -LiteralPath $ConfigPath
$readyPath=Join-Path $work 'helper-ready.json'
$statusPath=Join-Path $work 'status.json'
$changes=@()
$restarted=$null
$utf8=New-Object System.Text.UTF8Encoding($false)
function Status([string]$phase,[string]$message) {
 $state=@{pid=$PID;phase=$phase;message=$message;time=[DateTime]::UtcNow.ToString('o')}
 [IO.File]::WriteAllText($statusPath,($state|ConvertTo-Json -Compress),$utf8)
 Add-Content -LiteralPath $config.log -Encoding UTF8 -Value ("{0} [{1}] {2}" -f $state.time,$phase,$message)
}
function ChildPath([string]$root,[string]$name) {
 if([IO.Path]::IsPathRooted($name) -or $name.Contains(':') -or ($name -split '[/\\]') -contains '..'){throw "Unsafe update path: $name"}
 $base=[IO.Path]::GetFullPath($root).TrimEnd('\')+'\'
 $result=[IO.Path]::GetFullPath((Join-Path $root $name))
 if(-not $result.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw "Path outside update folder: $name"}
 return $result
}
try {
 if(-not $config.application -or -not $config.staged -or -not $config.files -or -not $config.log){throw 'Incomplete update configuration.'}
 Status 'waiting_for_exit' 'Helper started; waiting for the application to exit.'
 [IO.File]::WriteAllText($readyPath,(@{pid=$PID;phase='waiting_for_exit'}|ConvertTo-Json -Compress),$utf8)
 Wait-Process -Id $config.pid -Timeout 90 -ErrorAction SilentlyContinue
 if(Get-Process -Id $config.pid -ErrorAction SilentlyContinue){throw 'Application did not exit; no files were replaced.'}
 if(Test-Path -LiteralPath (Join-Path $work 'cancelled')){throw 'Update cancelled because startup was not acknowledged.'}
 Status 'installing' 'Application exited. Backing up and replacing files.'
 foreach($name in $config.files){
  $source=ChildPath $config.staged $name
  $target=ChildPath $config.application $name
  $backup=ChildPath $config.backup $name
  $existed=Test-Path -LiteralPath $target
  if($existed){
   New-Item -ItemType Directory -Force (Split-Path $backup) | Out-Null
   Copy-Item -LiteralPath $target -Destination $backup -Force
  }
  $changes+=@{Target=$target;Backup=$backup;Existed=$existed}
  New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
  Copy-Item -LiteralPath $source -Destination $target -Force
 }
 Status 'installed' 'Update installed successfully.'
 if($config.restart -ne $false){
  Status 'restarting' 'Starting the updated application.'
  $start=@{FilePath=(Join-Path $config.application 'dreamlight_companion.exe');WorkingDirectory=$config.application;PassThru=$true;WindowStyle='Normal'}
  if($config.startupReady){
   if(Test-Path -LiteralPath $config.startupReady){Remove-Item -LiteralPath $config.startupReady -Force}
   # Start-Process joins arguments into a command line; quote paths containing spaces.
   $start.ArgumentList=@('"--update-ready='+$config.startupReady+'"')
  }
  $restarted=Start-Process @start
  $deadline=[DateTime]::UtcNow.AddSeconds(40)
  $healthy=$false
  do {
   $restarted.Refresh()
   if($restarted.HasExited){throw "Updated application exited during startup (code $($restarted.ExitCode))."}
   if($config.startupReady -and (Test-Path -LiteralPath $config.startupReady)){
    try {$ack=Get-Content -LiteralPath $config.startupReady -Raw -Encoding UTF8 | ConvertFrom-Json; $healthy=($ack.pid -eq $restarted.Id)}catch{}
   }elseif(-not $config.startupReady){$healthy=$true}
   if(-not $healthy){Start-Sleep -Milliseconds 200}
  }while(-not $healthy -and [DateTime]::UtcNow -lt $deadline)
  if(-not $healthy){throw 'Updated application did not confirm its first rendered frame.'}
  Status 'restarted' "Updated application is ready (PID $($restarted.Id))."
 }
}catch{
 $failure=$_.Exception.Message
 $rollbackErrors=@()
 if($restarted){
  try {$restarted.Refresh(); if(-not $restarted.HasExited){$restarted.Kill();$restarted.WaitForExit(10000)|Out-Null}}catch{$rollbackErrors+=$_.Exception.Message}
 }
 foreach($entry in $changes){
  try {
   if($entry.Existed){Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force}
   elseif(Test-Path -LiteralPath $entry.Target){Remove-Item -LiteralPath $entry.Target -Force}
  }catch{$rollbackErrors+=$_.Exception.Message}
 }
 $message="Update failed and existing files were restored: $failure"
 if($rollbackErrors.Count -gt 0){$message+=" Rollback errors: $($rollbackErrors -join '; ')"}
 Status 'failed' $message
 if($changes.Count -gt 0 -and $config.restart -ne $false -and -not(Get-Process -Id $config.pid -ErrorAction SilentlyContinue)){
  try {
   $old=Start-Process -FilePath (Join-Path $config.application 'dreamlight_companion.exe') -WorkingDirectory $config.application -WindowStyle Normal -PassThru
   Status 'rolled_back' "$message Previous application restarted (PID $($old.Id))."
  }catch{Status 'failed' "$message Previous application could not restart: $($_.Exception.Message)"}
 }
}
''';
