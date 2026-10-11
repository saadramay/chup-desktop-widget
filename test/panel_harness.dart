import 'dart:io';

import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/visit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';

// Scaffolding shared by every test that pumps the real WidgetShell: the
// controller stand-in, the Segoe UI faces the panel actually asks for, and
// GetStorage's missing platform channel.
//
// It lives here rather than in either test because the two guards need it
// identically, and because the font table is not guessable — it is the exact
// set of faces `t()` asks for, and a test running against the placeholder face
// measures nothing useful.

/// The panel controller with everything that outlives a frame switched off.
class PanelHost extends QueueController {
  /// Deliberately empty: the real `onInit` starts two periodic timers and
  /// kicks off a poll at a backend. Neither belongs in a layout test — the
  /// timers outlive the frame and the poll has nothing to reach.
  @override
  // ignore: must_call_super
  void onInit() {}

  /// The real one reaches for `screen_retriever` and `window_manager`, neither
  /// of which exists on a test host. The window size is exercised instead by
  /// pumping at the exact height it would ask for.
  ///
  /// Counted, so a test can tell whether the shell ever asked to be resized.
  @override
  Future<void> applyWindowGeometry() async {
    geometryRequests++;
  }

  /// How many times the shell (or anything else) asked for the window.
  int geometryRequests = 0;

  /// No OS window on a test host.
  @override
  Future<void> showSignInWindow() async {}

  /// The first-run blink and tour run on timers; layout tests do not want them.
  @override
  Future<void> landed() async {}
}

const segouiFontDir = 'C:\\Windows\\Fonts';

/// Layout tests measure with real Segoe UI, so they skip on hosts without it
/// (macOS, Linux) instead of failing. CI runs on Windows and still enforces them.
final bool noSegoe = !File('$segouiFontDir\\segoeui.ttf').existsSync();

/// The faces the panel's `t()` helper actually asks for. `segoeuib` is reused
/// for w800 because Segoe UI ships no heavier weight.
final segouiFaces = <String, Map<FontWeight, String>>{
  'Segoe UI': {
    FontWeight.w400: 'segoeui.ttf',
    FontWeight.w500: 'segoeuisl.ttf',
    FontWeight.w600: 'segoeuiz.ttf',
    FontWeight.w700: 'segoeuib.ttf',
    FontWeight.w800: 'segoeuib.ttf',
  },
  'Segoe UI Variable Text': {
    FontWeight.w400: 'segoeui.ttf',
    FontWeight.w500: 'segoeuisl.ttf',
    FontWeight.w600: 'segoeuiz.ttf',
    FontWeight.w700: 'segoeuib.ttf',
    FontWeight.w800: 'segoeuib.ttf',
  },
};

/// False when Segoe UI is absent — a Windows-only widget measured on a host
/// that has no Windows fonts.
Future<bool> loadSegoe() async {
  if (!Directory(segouiFontDir).existsSync()) return false;
  for (final family in segouiFaces.entries) {
    final loader = FontLoader(family.key);
    for (final face in family.value.entries) {
      final file = File('$segouiFontDir\\${face.value}');
      if (!file.existsSync()) return false;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  return true;
}

/// flutter_test's square placeholder face has different metrics from Segoe UI,
/// so anything measured here would pass on a broken constant.
void requireSegoe(bool loaded) => expect(loaded, isTrue,
    reason: 'Segoe UI is needed to measure the panel. This is a Windows-only '
        'widget; install Segoe UI or run it on Windows.');

/// GetStorage resolves its file through path_provider, which has no
/// implementation on a test host, and `QueueController` builds a `GetStorage()`
/// the moment it is constructed — so the mock has to be in place first.
Future<void> initPanelStorage() async {
  // One folder per test process: test files run in parallel, and a shared
  // GetStorage file lets one file's writes land in another's assertions.
  final dir = Directory.systemTemp.createTempSync('chup_widget_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null);

  await GetStorage.init();
}

/// A visit for whatever state is under test. `name` is the only field any of
/// the layout here reads as a variable — the rest are fixed so a fixture can
/// never be the thing that changes width between runs.
Visit visit({
  required String name,
  String state = 'WAITING',
  DateTime? calledAt,
  DateTime? startedAt,
}) =>
    Visit(
      id: name.hashCode,
      token: 'AD 126',
      clientName: name,
      sortIndex: 3,
      stateName: state,
      arrivedAt: DateTime(2026, 8, 1, 15, 5),
      appointmentAt: null,
      calledAt: calledAt,
      startedAt: startedAt,
      isEndVisit: false,
    );
