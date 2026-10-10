import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/visit.dart';
import 'package:chup_widget/core/window_anchor.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

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

void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  tearDown(Get.reset);

  /// Pumps the real shell at the exact window size `applyWindowGeometry`
  /// would ask for: `size.height + kRevealHeight`.
  Future<void> pumpTallestReveal(
    WidgetTester tester,
    WidgetSize size, {
    String servingName = 'Ahmad Abu Ibrahim',
  }) async {
    final c = PanelHost();
    Get.put<QueueController>(c);
    c.size.value = size;
    c.state.value = PanelState.serving;
    c.revealed.value = true;
    // Frozen: the real controller ticks this every second, and an unset clock
    // makes the SERVING counter read tens of thousands of minutes — which
    // changes how wide the reveal's figure row is.
    c.now.value = DateTime(2026, 8, 1, 15, 45);

    // Somebody in the room …
    c.serving.value = visit(
      name: servingName,
      state: 'SERVING',
      startedAt: DateTime(2026, 8, 1, 15, 30),
    );

    // … and somebody called, which is what puts NO-SHOW on the reveal.
    final called = visit(
      name: 'Kawthar Falah Qandeel',
      calledAt: DateTime(2026, 8, 1, 15, 31),
    );
    c.called.value = called;

    // Enough waiting patients to fill every row: a full list is the tallest
    // the queue block can get, so it is the worst case for the reveal.
    c.queue.value = <Visit>[
      called,
      for (var i = 0; i < size.rows + 1; i++)
        visit(name: 'Patient Number $i'),
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
      requireSegoe(segouiLoaded);

      await pumpTallestReveal(tester, size);

      expect(tester.takeException(), isNull,
          reason: 'kRevealHeight is too short for the reveal — the NO-SHOW '
              'button is being clipped. The window is sized at '
              '${size.height} + $kRevealHeight.');
    });
  }

  testWidgets('a name too long for one line does not push NO-SHOW off',
      (tester) async {
    requireSegoe(segouiLoaded);

    // Three lines if it were allowed to wrap — 42px past the bottom of the
    // panel before the name was given maxLines.
    await pumpTallestReveal(tester, WidgetSize.small,
        servingName: 'Nurul Binti Abdul Rahman Al-Hafiz ibn Yusof Kamaruddin');

    expect(tester.takeException(), isNull,
        reason: 'the reveal name must stay on one line: the reveal height is '
            'fixed by the window, so every extra line pushes the NO-SHOW '
            'button off the bottom of the panel.');
  });
}
