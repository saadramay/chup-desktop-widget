import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/visit.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

// The resting band, and the window it has to fit.
//
// The design gives each size a window, the shell draws a 1px border inside it,
// and what is left is the band: 40 - 2 = the 38 that design/README.md calls
// "the bottom 38px ... identical at all three sizes". The band was built at
// 40 instead, so it claimed 2px more than the column had — an overflow at
// every size, drawn as a red "BOTTOM OVERFLOWED BY 10.0 PIXELS" banner across
// the lead meter.
//
// Read what this test can and cannot see. It pumps at exactly
// `size.height`, which means it assumes the Flutter view *is* the size that
// was asked for. Only a frameless window gives that: window_manager's
// TitleBarStyle.hidden insets 8px on the left, right and bottom of the client
// area instead, which turned 216x40 into 200x32 and took the overflow from
// 2px to 10px. No widget test can see that half — main() calls
// setAsFrameless() for it, and window_anchor's tests cover the sizes.

void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  tearDown(Get.reset);

  /// Pumps the real shell at rest — the state the widget spends almost all of
  /// its life in — at the exact window height `applyWindowGeometry` asks for.
  ///
  /// [fullQueue] fills the list to `size.rows + 1`: one more than the panel
  /// shows, so `upcoming` is capped out and every row slot is drawn. That is
  /// the tallest `_QueueRows` can get, and therefore the tightest fit.
  Future<void> pumpAtRest(
    WidgetTester tester,
    WidgetSize size, {
    required PanelState state,
    Visit? serving,
    bool fullQueue = false,
    DateTime? lastGoodPoll,
  }) async {
    final c = PanelHost();
    Get.put<QueueController>(c);
    c.size.value = size;
    c.state.value = state;
    // Not revealed: the reveal is an Expanded, so it would absorb any slack
    // and hide a band that is too tall. At rest the band is on its own.
    c.revealed.value = false;
    c.now.value = DateTime(2026, 8, 1, 15, 45);
    c.serving.value = serving;
    // Only the offline line reads this, and only to decide whether it has a
    // trailing "LAST READ ...M AGO" to sit beside the headline. Left null the
    // trailing is dropped and the line is short — which is how the horizontal
    // overflow stayed invisible for so long.
    c.lastGoodPoll.value = lastGoodPoll;
    if (fullQueue) {
      c.queue.value = <Visit>[
        for (var i = 0; i < size.rows + 1; i++)
          visit(name: 'Patient Number $i'),
      ];
    }

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: kWidgetWidth,
            height: size.height,
            child: const WidgetShell(),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final size in WidgetSize.values) {
    testWidgets('the band fits at rest with a full queue (${size.name})',
        (tester) async {
      requireSegoe(segouiLoaded);

      await pumpAtRest(tester, size,
          state: PanelState.serving,
          serving: visit(
            name: 'Ahmad Abu Ibrahim',
            state: 'SERVING',
            startedAt: DateTime(2026, 8, 1, 15, 30),
          ),
          fullQueue: true);

      expect(tester.takeException(), isNull,
          reason: 'the resting band does not fit a ${size.height}px window. '
              'The window is ${size.height}, the shell border takes 2, and '
              'the rows take ${size.rows * size.rowHeight} — leaving '
              '${size.height - 2 - size.rows * size.rowHeight}px for the band, '
              'which design/README.md says is 38.');
    }, skip: noSegoe);
  }

  testWidgets('the empty resting line fits the small window', (tester) async {
    requireSegoe(segouiLoaded);

    // This is the state on screen when the overflow was caught: nobody in the
    // queue, no reveal, 216x40.
    await pumpAtRest(tester, WidgetSize.small, state: PanelState.empty);

    expect(tester.takeException(), isNull,
        reason: 'NO ONE IN THE QUEUE does not fit the small window: 40px '
            'minus the shell border leaves 38px, which is exactly what the '
            'band needs — so anything more than 38 overflows.');
  }, skip: noSegoe);

  // The line runs LEFT to RIGHT, and until now nothing pinned it down: the
  // headline sat at its natural width and the trailing clock was pushed out by
  // a Spacer, so the pair overflowed whenever the two together outgrew the
  // band. The tall-size tests above cannot see it — they assert the band's
  // height, and the horizontal case only exists where a trailing is present.
  for (final size in WidgetSize.values) {
    testWidgets('the offline line fits its width (${size.name})',
        (tester) async {
      requireSegoe(segouiLoaded);

      // 100 minutes: the widest the trailing can be is three digits, and the
      // headline "CANNOT REACH CHUP" is the longest one the band prints.
      await pumpAtRest(tester, size,
          state: PanelState.offline, lastGoodPoll: DateTime(2026, 8, 1, 13, 5));

      expect(tester.takeException(), isNull,
          reason: '"CANNOT REACH CHUP" beside "LAST READ 100M AGO" is wider '
              'than the ${kWidgetWidth}px band minus the shell border and the '
              '9px padding on each side. The two have to share one line, so '
              'one of them has to give.');
    }, skip: noSegoe);

    testWidgets('the loading line fits its width (${size.name})',
        (tester) async {
      requireSegoe(segouiLoaded);

      await pumpAtRest(tester, size, state: PanelState.loading);

      expect(tester.takeException(), isNull,
          reason: '"READING THE QUEUE" does not fit the band.');
    }, skip: noSegoe);
  }
}
