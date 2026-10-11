import 'dart:io';

import 'package:flutter/foundation.dart';

/// Registers the widget to open when Windows starts, as the sign-in card
/// promises. Per-user Run key, so no admin rights are needed. Skipped in debug
/// so a development build never registers the Flutter runner.
Future<void> registerStartup() async {
  if (!Platform.isWindows || !kReleaseMode) return;
  try {
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
      '/v',
      'ChupWidget',
      '/t',
      'REG_SZ',
      '/d',
      '"${Platform.resolvedExecutable}"',
      '/f',
    ]);
  } catch (_) {
    // Startup is a convenience; never block sign-in on it.
  }
}
