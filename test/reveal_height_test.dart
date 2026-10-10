import 'dart:io';

import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/visit.dart';
import 'package:chup_widget/core/window_anchor.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

// The reveal's height is not a round number anyone picked — it is however
// much the tallest reveal needs, plus the shell's 1px border on each edge.
//
// The tallest reveal is the one where somebody is in the room *and* somebody
// else has been called, because that is when the NO-SHOW hold button appears.
// At `kRevealHeight = 112` that state overflowed by exactly 6px and clipped
// the button; 118 is the smallest value that fits (117 overflows by 1px).
//
// This file measures that rather than trusting it, using the real Segoe UI
// metrics — with flutter_test's default square placeholder font the text is a
// different height and the test would pass on a broken constant.

/// The panel controller with everything that outlives a frame switched off.
class _PanelHost extends QueueController {
  /// Deliberately empty: the real `onInit` starts two periodic timers and
  /// kicks off a poll at a backend. Neither belongs in a layout test — the
  /// timers outlive the frame and the poll has nothing to reach.
  @override
  // ignore: must_call_super
  void onInit() {}

  /// The real one reaches for `screen_retriever` and `window_manager`, neither
  /// of which exists on a test host. The window size is exercised by pumping at
  /// `size.height + kRevealHeight`, which is exactly what it asks for.
  @override
  Future<void> applyWindowGeometry() async {}
}

const _fontDir = 'C:\\Windows\\Fonts';

/// The faces the panel's `t()` helper actually asks for. `segoeuib` is reused
/// for w800 because Segoe UI ships no heavier weight.
final _faces = <String, Map<FontWeight, String>>{
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

Future<bool> _loadSegoe() async {
  if (!Directory(_fontDir).existsSync()) return false;
  for (final family in _faces.entries) {
    final loader = FontLoader(family.key);
    for (final face in family.value.entries) {
      final file = File('$_fontDir\\${face.value}');
      if (!file.existsSync()) return false;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  return true;
}

Visit _visit({
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

void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // GetStorage resolves its file through path_provider, which has no
    // implementation on a test host.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async =>
                call.method == 'getApplicationDocumentsDirectory'
                    ? Directory.systemTemp.path
                    : null);

    await GetStorage.init();
    segouiLoaded = await _loadSegoe();
  });

  tearDown(Get.reset);

  /// Pumps the real shell at the exact window size `applyWindowGeometry`
  /// would ask for: `size.height + kRevealHeight`.
  Future<void> pumpTallestReveal(WidgetTester tester, WidgetSize size) async {
    final c = _PanelHost();
    Get.put<QueueController>(c);
    c.size.value = size;
    c.state.value = PanelState.serving;
    c.revealed.value = true;
    // Frozen: the real controller ticks this every second, and an unset clock
    // makes the SERVING counter read tens of thousands of minutes — which
    // changes how wide the reveal's figure row is.
    c.now.value = DateTime(2026, 8, 1, 15, 45);

    // Somebody in the room …
    c.serving.value = _visit(
      name: 'Ahmad Abu Ibrahim',
      state: 'SERVING',
      startedAt: DateTime(2026, 8, 1, 15, 30),
    );

    // … and somebody called, which is what puts NO-SHOW on the reveal.
    final called = _visit(
      name: 'Kawthar Falah Qandeel',
      calledAt: DateTime(2026, 8, 1, 15, 31),
    );
    c.called.value = called;

    // Enough waiting patients to fill every row: a full list is the tallest
    // the queue block can get, so it is the worst case for the reveal.
    c.queue.value = <Visit>[
      called,
      for (var i = 0; i < size.rows + 1; i++)
        _visit(name: 'Patient Number $i'),
    ];

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: kWidgetWidth,
            height: size.height + kRevealHeight,
            child: const WidgetShell(),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final size in WidgetSize.values) {
    testWidgets('the tallest reveal fits at kRevealHeight (${size.name})',
        (tester) async {
      expect(segouiLoaded, isTrue,
          reason: 'Segoe UI is needed to measure the reveal. It is a '
              'Windows-only widget; install Segoe UI or run this on Windows.');
      if (!segouiLoaded) return;

      await pumpTallestReveal(tester, size);

      expect(tester.takeException(), isNull,
          reason: 'kRevealHeight is too short for the reveal — the NO-SHOW '
              'button is being clipped. The window is sized at '
              '${size.height} + $kRevealHeight.');
    });
  }
}
