import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:chup_widget/ui/sliver_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

/// A controller whose window requests resize a fake window, so the shell is
/// laid out the way the OS would lay it out after each request.
class FakeWindowHost extends PanelHost {
  final window = ValueNotifier<Size>(const Size(kWidgetWidth, 40));
  final requests = <Size>[];
  @override
  Future<void> applyWindowGeometry() async {
    requests.add(Size(windowWidth, windowHeight));
    window.value = Size(windowWidth, windowHeight);
  }
}

Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
  'data': {'total': rows.length, 'data': rows},
};

Map<String, dynamic> row(int id, int state) => {
  'id': id,
  'state': state,
  'sort_index': id,
  'token': 'AD $id',
  'client': {'name': 'Patient $id'},
  'created_at': '2026-08-01T07:00:00.000000Z',
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
  });
  tearDown(Get.reset);

  for (final queueLen in [0, 1, 3, 12]) {
    for (final target in ['Medium', 'Large', 'Small']) {
      testWidgets('menu -> $target with $queueLen in the queue keeps the panel',
          (tester) async {
        final original = FlutterError.onError;
        final errors = <String>[];
        FlutterError.onError = (d) {
          if (!d.toString().contains('overflowed')) errors.add(d.toString());
        };
        addTearDown(() => FlutterError.onError = original);

        final c = FakeWindowHost();
        Get.put<QueueController>(c);
        c.applyResponses(page([]), page([for (var i = 1; i <= queueLen; i++) row(i, 1)]));
        await c.applyWindowGeometry();

        await tester.binding.setSurfaceSize(const Size(900, 900));
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ValueListenableBuilder<Size>(
                valueListenable: c.window,
                builder: (_, s, _) => SizedBox(width: s.width, height: s.height, child: const WidgetShell()),
              ),
            ),
          ),
        ));
        await tester.pump();

        await c.setRevealed(true);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(target).last);
        await tester.pumpAndSettle();
        // Pointer leaves the panel afterwards.
        await c.setRevealed(false);
        await tester.pumpAndSettle();

        final size = c.size.value;
        expect(size.label, target);
        expect(find.byType(SliverPanel), findsOneWidget,
            reason: 'window ${c.window.value}, resting ${c.restingHeight}, requests ${c.requests}');
        expect(c.window.value.height, greaterThanOrEqualTo(c.restingHeight));
        expect(errors, isEmpty);
      });
    }
  }
}
