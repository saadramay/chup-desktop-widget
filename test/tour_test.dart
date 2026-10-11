import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/tour.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:chup_widget/ui/sliver_panel.dart';
import 'package:chup_widget/ui/tour_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

// Every tour step must build beside the panel, in the window the controller
// asks for, and its body must fit the card rather than fade out unread.

void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  tearDown(Get.reset);

  for (var step = 1; step <= tourSteps.length; step++) {
    testWidgets('tour step $step fits beside the panel', (tester) async {
      requireSegoe(segouiLoaded);

      final c = PanelHost();
      Get.put<QueueController>(c);
      // The fullest panel: someone in the room, someone called, a long queue,
      // so every ringed region is on screen.
      Map<String, dynamic> row(int id, int state, int sort) => {
            'id': id,
            'token': 'AD $id',
            'sort_index': sort,
            'state': state,
            'client': {'name': 'Kawthar Falah Qandeel $id'},
            'created_at': '2026-08-01T07:00:00.000000Z',
          };
      Map<String, dynamic> page(List<Map<String, dynamic>> rows) =>
          {'data': {'total': rows.length, 'data': rows}};
      c.applyResponses(page([row(1, 4, 1)]),
          page([row(2, 2, 2), for (var i = 3; i < 13; i++) row(i, 1, i)]));
      c.presentation.value = Presentation.panel;
      await c.goToTourStep(step);

      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: c.windowWidth,
              height: c.windowHeight,
              child: const WidgetShell(),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(TourCard), findsOneWidget);
      expect(find.byType(SliverPanel), findsOneWidget);

      final body = tester.renderObject<RenderParagraph>(
          find.text(tourSteps[step - 1].body));
      expect(body.getMaxIntrinsicHeight(body.size.width),
          lessThanOrEqualTo(body.size.height + 0.5),
          reason: 'the body is cut off; raise kTourCardHeight');
    }, skip: noSegoe);
  }
}
