import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:chup_widget/ui/sliver_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

// The panel may only be built into a window that can hold it.
//
// Windows will not make a window as small as the closed tab (5x34) or the
// minimised chip (44x44) ask for — a 5x34 request clamps to a 136x39
// minimum. So every restore leaves the *view* at 136x39 for a frame or two
// after SetWindowPos has already returned, which is why awaiting the resize
// before flipping `presentation` was not enough on its own.
//
// At 136x39 the panel reports three errors in one frame, all of which were
// seen in the live log:
//
//   - the band is 116px wide against a 117px "NO ONE IN THE QUEUE"
//   - `_ServingLine`'s row is squeezed to 33px and overflows by 62
//   - 39px of window is 1px short of the 38px band plus the 1px shell border,
//     which is the `overflowed by 1.00 pixels on the bottom` line
//
// This pumps the real shell at exactly that size. Without the guard in
// WidgetShell, `takeException()` is not null; with it the shell draws nothing
// and lets the geometry callback ask for 216.

void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  tearDown(Get.reset);

  Future<void> pumpShell(
    WidgetTester tester, {
    required double width,
    required double height,
    PanelState state = PanelState.empty,
    WidgetSize size = WidgetSize.small,
  }) async {
    final c = PanelHost();
    Get.put<QueueController>(c);
    c.size.value = size;
    c.state.value = state;
    c.revealed.value = false;
    c.presentation.value = Presentation.panel;
    c.now.value = DateTime(2026, 8, 1, 15, 45);
    if (state == PanelState.serving) {
      c.serving.value = visit(
        name: 'Ahmad Abu Ibrahim',
        state: 'SERVING',
        startedAt: DateTime(2026, 8, 1, 15, 30),
      );
    }

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: const WidgetShell(),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final state in [PanelState.empty, PanelState.serving]) {
    testWidgets(
        'the panel is not built into the clamped 136x39 window (${state.name})',
        (tester) async {
      requireSegoe(segouiLoaded);

      await pumpShell(tester, width: 136, height: 39, state: state);

      expect(tester.takeException(), isNull,
          reason: '136x39 is what Windows clamps a 5x34 closed tab to, and it '
              'is the size the view still reports for a frame or two after a '
              'restore. The band needs 38px inside a 1px border — 39 leaves '
              '37 — and at 116px wide it cannot hold its own headline.');
      expect(find.byType(SliverPanel), findsNothing,
          reason: 'the shell must draw nothing at this size and let its '
              'geometry callback ask for kWidgetWidth first.');
    }, skip: noSegoe);
  }

  testWidgets('the panel builds normally once the window is 216 wide',
      (tester) async {
    requireSegoe(segouiLoaded);

    // The positive control: the guard must not swallow the real panel.
    await pumpShell(tester,
        width: kWidgetWidth, height: WidgetSize.small.height,
        state: PanelState.serving);

    expect(find.byType(SliverPanel), findsOneWidget,
        reason: 'the guard is about being too small, not about hiding.');
    expect(tester.takeException(), isNull);
  }, skip: noSegoe);

  testWidgets(
      'a too-small window asks to be resized, so it cannot stay that way',
      (tester) async {
    requireSegoe(segouiLoaded);

    // 216x40 is exactly what main() used to start the window at, whatever
    // size the menu had stored. With large stored that is a 208px panel in a
    // 40px window — the state that shipped a blank, inert widget.
    await pumpShell(tester,
        width: kWidgetWidth,
        height: WidgetSize.small.height,
        state: PanelState.empty,
        size: WidgetSize.large);

    final c = Get.find<QueueController>() as PanelHost;

    expect(find.byType(SliverPanel), findsNothing,
        reason: '40px cannot hold a 208px panel, so it still must not draw.');
    expect(tester.takeException(), isNull);
    expect(c.geometryRequests, greaterThan(0),
        reason: 'drawing nothing is only half of it. Nothing else in the app '
            'sizes the window, so without this ask the window stays 40px for '
            'good: transparent, ignoring the cursor, looking hung.');
  }, skip: noSegoe);
}
