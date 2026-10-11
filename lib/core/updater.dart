import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Set by the release workflow from the tag (`v1.2.0` -> `1.2.0`). Local and
/// CI test builds carry the default, which turns updating off.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.0.0',
);

/// Public and code-free: the source repository is private, and installed
/// widgets read releases without credentials.
const kReleasesRepo = 'saadramay/chup-desktop-widget-releases';

/// Test builds only: a URL serving the same JSON as GitHub's releases/latest,
/// so the updater can be exercised end to end without publishing anything.
const String kUpdateFeed = String.fromEnvironment('UPDATE_FEED');

/// Test builds only: install a found update without waiting for a click.
const bool kAutoUpdate = bool.fromEnvironment('AUTO_UPDATE');

Uri get latestReleaseUrl => kUpdateFeed.isNotEmpty
    ? Uri.parse(kUpdateFeed)
    : Uri.parse('https://api.github.com/repos/$kReleasesRepo/releases/latest');
const kZipAsset = 'chup-widget-windows.zip';
const kShaAsset = '$kZipAsset.sha256';

/// A published release the widget can update to.
class Release {
  const Release({
    required this.version,
    required this.zip,
    required this.sha256,
  });
  final String version;
  final Uri zip;
  final Uri sha256;
}

/// Compares dotted versions numerically ("1.10.0" > "1.9.2"). A leading `v`
/// and any `-pre` or `+build` suffix are ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Reads GitHub's `releases/latest` payload. Null for drafts, pre-releases or
/// a release missing either asset.
Release? parseRelease(Map<String, dynamic> j) {
  if (j['draft'] == true || j['prerelease'] == true) return null;
  final tag = '${j['tag_name'] ?? ''}';
  if (tag.isEmpty) return null;
  Uri? asset(String name) {
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is Map && a['name'] == name) {
        return Uri.tryParse('${a['browser_download_url']}');
      }
    }
    return null;
  }

  final zip = asset(kZipAsset), sha = asset(kShaAsset);
  if (zip == null || sha == null) return null;
  return Release(
    version: tag.replaceFirst(RegExp(r'^v'), ''),
    zip: zip,
    sha256: sha,
  );
}

/// A download failed in Windows' own HTTP stack; [detail] is its message.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.detail);
  final String detail;
  @override
  String toString() => 'UpdateDownloadException: $detail';
}

/// PowerShell that downloads [url] to [file] with Windows' own HTTP stack.
///
/// Dart's TLS trusts only the root certificates already in the Windows store.
/// Windows fetches missing roots on demand and goes through corporate proxies
/// that re-sign HTTPS; Dart does neither. On the WorkSpace that made every
/// download fail with CERTIFICATE_VERIFY_FAILED while the browser was fine.
@visibleForTesting
String downloadScript(Uri url, String file) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  return [
    r"$ErrorActionPreference = 'Stop'",
    r"$ProgressPreference = 'SilentlyContinue'",
    r'[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12',
    "Invoke-WebRequest -UseBasicParsing -Uri ${q(url.toString())} -OutFile ${q(file)} -Headers @{ 'User-Agent' = 'chup-widget/$kAppVersion' }",
  ].join('; ');
}

/// The PowerShell that finishes an update once the widget has exited: Windows
/// will not let a running exe be overwritten. It always restarts the widget,
/// old or new, so a failed copy never leaves the doctor without it.
@visibleForTesting
String updateScript({
  required int pid,
  required String zip,
  required String installDir,
  required String exe,
  required String log,
}) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  return '''
\$log = ${q(log)}
Set-Content -Path \$log -Value 'script started'
\$ErrorActionPreference = 'Stop'
function Log(\$m) { Add-Content -Path \$log -Value ("{0:s} {1}" -f (Get-Date), \$m) }
try {
  Log 'waiting for widget $pid to exit'
  try { Wait-Process -Id $pid -Timeout 60 } catch { }
  \$staging = Join-Path (Split-Path ${q(zip)}) 'new'
  if (Test-Path \$staging) { Remove-Item \$staging -Recurse -Force }
  Expand-Archive -Path ${q(zip)} -DestinationPath \$staging -Force
  Copy-Item -Path (Join-Path \$staging '*') -Destination ${q(installDir)} -Recurse -Force
  Log 'updated'
} catch {
  Log ("update failed: " + \$_)
} finally {
  Start-Process -FilePath ${q(exe)}
}
''';
}

class Updater {
  /// Where a failed update leaves its details: %TEMP%\chup-widget-update-error.log.
  static File get failureLog => File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}chup-widget-update-error.log',
  );

  static Future<void> logFailure(Object e, StackTrace st) async {
    try {
      await failureLog.writeAsString(
        '${DateTime.now().toIso8601String()} $kAppVersion\n$e\n$st\n\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  /// A short reason for the resting line; the log has the rest.
  static String describeFailure(Object e) {
    if (e is SocketException ||
        e is http.ClientException ||
        e is HandshakeException ||
        e is UpdateDownloadException) {
      return "Update failed: can't download from GitHub";
    }
    if (e is TimeoutException) return 'Update failed: the download timed out';
    if (e is FileSystemException && '$e'.contains('checksum')) {
      return 'Update failed: the download was damaged';
    }
    if (e is ProcessException) {
      return "Update failed: couldn't start the installer";
    }
    return 'Update failed. Try again later.';
  }

  /// Release builds on Windows only: a debug run from `flutter run` must never
  /// replace itself, and a build without APP_VERSION has nothing to compare.
  static bool get enabled =>
      !kIsWeb && Platform.isWindows && kReleaseMode && kAppVersion != '0.0.0';

  /// The latest release when it is newer than this build, else null.
  static Future<Release?> check({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(
            latestReleaseUrl,
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'chup-widget/$kAppVersion',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      return _newer(jsonDecode(r.body) as Map<String, dynamic>);
    } on HandshakeException {
      // Same certificate problem as downloads; ask Windows instead.
      if (client != null || !Platform.isWindows) rethrow;
      final dir = await Directory.systemTemp.createTemp('chup-widget-check-');
      try {
        final f = File('${dir.path}${Platform.pathSeparator}latest.json');
        await windowsDownload(latestReleaseUrl, f);
        return _newer(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    } finally {
      if (client == null) c.close();
    }
  }

  static Release? _newer(Map<String, dynamic> json) {
    final release = parseRelease(json);
    if (release == null || compareVersions(release.version, kAppVersion) <= 0) {
      return null;
    }
    return release;
  }

  /// Downloads [url] to [file] through PowerShell (see [downloadScript]).
  static Future<void> windowsDownload(Uri url, File file) async {
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      downloadScript(url, file.path),
    ]).timeout(const Duration(minutes: 5));
    if (r.exitCode != 0 || !await file.exists()) {
      final err = '${r.stderr}'.trim();
      throw UpdateDownloadException(
        err.isEmpty ? 'exit code ${r.exitCode}' : err.split('\n').first,
      );
    }
  }

  /// Downloads [r], checks its SHA-256 against the published one, and starts
  /// the swap script. The caller exits the app straight after.
  static Future<void> install(Release r) async {
    final dir = await Directory.systemTemp.createTemp('chup-widget-update-');
    final zip = File('${dir.path}${Platform.pathSeparator}$kZipAsset');
    final shaFile = File('${dir.path}${Platform.pathSeparator}$kShaAsset');
    // Windows downloads, Dart verifies.
    await windowsDownload(r.zip, zip);
    await windowsDownload(r.sha256, shaFile);
    final expected = (await shaFile.readAsString())
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    final actual = sha256.convert(await zip.readAsBytes()).toString();
    if (expected.length != 64 || actual != expected) {
      await zip.delete();
      throw const FileSystemException(
        'The download did not match its checksum',
      );
    }

    final exe = Platform.resolvedExecutable;
    final script = File('${dir.path}${Platform.pathSeparator}update.ps1');
    await script.writeAsString(
      updateScript(
        pid: pid,
        zip: zip.path,
        installDir: File(exe).parent.path,
        exe: exe,
        log: '${dir.path}${Platform.pathSeparator}update.log',
      ),
    );
    // Through `cmd /c start /min`: a detached process has no console, and
    // Windows PowerShell started without one can exit before running the
    // script. `start` gives it a console of its own, minimised and hidden.
    final launcher = File('${dir.path}${Platform.pathSeparator}launcher.log');
    final p = await Process.start('cmd.exe', [
      '/c',
      'start',
      '/min',
      'powershell.exe',
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
    ], mode: ProcessStartMode.detached);
    await launcher.writeAsString(
      'widget pid $pid started cmd pid ${p.pid} for ${script.path}\n',
    );
  }
}
