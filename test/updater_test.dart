import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chup_widget/core/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> release(String tag,
        {bool draft = false, bool pre = false, bool withSha = true}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': pre,
      'assets': [
        {'name': kZipAsset, 'browser_download_url': 'https://example.test/$tag/$kZipAsset'},
        if (withSha)
          {'name': kShaAsset, 'browser_download_url': 'https://example.test/$tag/$kShaAsset'},
        {'name': 'chup-widget-setup.exe', 'browser_download_url': 'https://example.test/setup.exe'},
      ],
    };

void main() {
  group('compareVersions', () {
    test('compares numerically, not as text', () {
      expect(compareVersions('1.10.0', '1.9.2'), 1);
      expect(compareVersions('1.2.0', '1.2.0'), 0);
      expect(compareVersions('1.2.0', '1.2.1'), -1);
    });

    test('ignores a leading v and build or pre-release suffixes', () {
      expect(compareVersions('v1.3.0', '1.3.0'), 0);
      expect(compareVersions('1.3.0+7', '1.3.0'), 0);
      expect(compareVersions('2', '1.9.9'), 1);
    });
  });

  group('parseRelease', () {
    test('reads the version and both asset URLs', () {
      final r = parseRelease(release('v1.4.0'))!;
      expect(r.version, '1.4.0');
      expect(r.zip.toString(), endsWith('/$kZipAsset'));
      expect(r.sha256.toString(), endsWith('/$kShaAsset'));
    });

    test('skips drafts, pre-releases and releases without a checksum', () {
      expect(parseRelease(release('v1.4.0', draft: true)), isNull);
      expect(parseRelease(release('v1.4.0', pre: true)), isNull);
      expect(parseRelease(release('v1.4.0', withSha: false)), isNull,
          reason: 'an update that cannot be verified is not offered');
    });
  });

  group('Updater.check', () {
    test('offers a newer release from GitHub', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/repos/$kReleasesRepo/releases/latest');
        expect(req.headers['User-Agent'], startsWith('chup-widget/'));
        return http.Response(jsonEncode(release('v9.0.0')), 200);
      });
      expect((await Updater.check(client: client))?.version, '9.0.0');
    });

    test('offers nothing when GitHub answers with an error', () async {
      final client = MockClient((_) async => http.Response('rate limited', 403));
      expect(await Updater.check(client: client), isNull);
    });
  });

  group('updateScript', () {
    test('waits for the widget, swaps the files, and always restarts it', () {
      final s = updateScript(
        pid: 4242,
        zip: r'C:\Temp\u\chup-widget-windows.zip',
        installDir: r'C:\Users\dr\AppData\Local\Programs\Chup Widget',
        exe: r'C:\Users\dr\AppData\Local\Programs\Chup Widget\chup_widget.exe',
        log: r'C:\Temp\u\update.log',
      );
      expect(s, contains('Wait-Process -Id 4242'));
      expect(s, contains('Expand-Archive'));
      expect(s, contains(r"-Destination 'C:\Users\dr\AppData\Local\Programs\Chup Widget'"));
      final restart = s.indexOf('Start-Process');
      expect(restart, greaterThan(s.indexOf('finally')),
          reason: 'a failed copy must still bring the widget back');
    });

    test('quotes paths so an apostrophe cannot break out of the string', () {
      final s = updateScript(
        pid: 1,
        zip: r"C:\Users\O'Neil\u.zip",
        installDir: r"C:\Users\O'Neil\Chup",
        exe: r"C:\Users\O'Neil\Chup\chup_widget.exe",
        log: r"C:\Users\O'Neil\u.log",
      );
      expect(s, contains(r"'C:\Users\O''Neil\Chup'"));
      expect(s, isNot(contains(r"O'Neil")));
    });
  });

  test('the swap script parses as PowerShell', () async {
    final dir = await Directory.systemTemp.createTemp('chup-ps-');
    final f = File('${dir.path}${Platform.pathSeparator}update.ps1')
      ..writeAsStringSync(updateScript(
        pid: 1,
        zip: r"C:\Temp\O'Neil\u.zip",
        installDir: r'C:\Temp\Chup Widget',
        exe: r'C:\Temp\Chup Widget\chup_widget.exe',
        log: r'C:\Temp\u.log',
      ));
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "\$e = \$null; [System.Management.Automation.Language.Parser]::ParseFile('${f.path}', [ref]\$null, [ref]\$e) | Out-Null; if (\$e) { \$e | ForEach-Object { \$_.Message }; exit 1 }",
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, skip: !Platform.isWindows);

  test('a failure names its cause in a few words', () {
    expect(Updater.describeFailure(const SocketException('blocked')),
        contains("can't download"));
    expect(Updater.describeFailure(http.ClientException('reset')),
        contains("can't download"));
    expect(Updater.describeFailure(TimeoutException('slow')), contains('timed out'));
    expect(
        Updater.describeFailure(
            const FileSystemException('The download did not match its checksum')),
        contains('damaged'));
    expect(Updater.describeFailure(const ProcessException('cmd.exe', [])),
        contains("couldn't start"));
    expect(Updater.describeFailure(StateError('x')), 'Update failed. Try again later.');
  });
}
