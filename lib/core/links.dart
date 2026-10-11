import 'dart:io';

import 'api.dart';

/// The Chup web app's live queue, on the same host the API is compiled against.
Uri get webQueueUrl {
  final api = Uri.parse(kBaseUrl);
  return api.replace(path: '/live-queues', query: null);
}

/// Opens [url] in the default browser. Windows only; no plugin needed.
Future<void> openInBrowser(Uri url) async {
  if (!Platform.isWindows) return;
  try {
    await Process.run('rundll32', ['url.dll,FileProtocolHandler', url.toString()]);
  } catch (_) {
    // Nothing useful to show in a 40px window; the click simply does nothing.
  }
}
