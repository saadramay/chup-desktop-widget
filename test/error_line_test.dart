import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

// A failed action's reason takes the whole resting line and must stay readable
// (it was cut to "Cann..." beside the time).

void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  tearDown(Get.reset);

  for (final message in [
    'Cannot serve for this service.',
    'The staff currently serving patient(s).',
  ]) {
    testWidgets('the error "$message" fits the band', (tester) async {
      requireSegoe(segouiLoaded);
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses({
        'data': {'data': []},
      }, {
        'data': {
          'data': [
            {'id': 6, 'state': 2, 'sort_index': 1, 'token': 'HL-01', 'client': {'name': 'Saad'}},
          ],
        },
      });
      c.actionError.value = message;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: kWidgetWidth,
              height: c.windowHeight,
              child: const WidgetShell(),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(message), findsOneWidget);
      expect(find.text('Start'), findsOneWidget,
          reason: 'the button stays put while the reason shows');
    }, skip: noSegoe);
  }
}
