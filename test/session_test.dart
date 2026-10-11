import 'package:chup_widget/core/api.dart';
import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:chup_widget/ui/sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'panel_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
  });

  tearDown(() {
    Api.instance.persistToken = true;
    Api.instance.token = null;
    Get.reset();
  });

  test('an unticked "stay signed in" never writes the token to disk', () {
    Api.instance.persistToken = true;
    Api.instance.token = 'old';
    expect(GetStorage().read<String>('token'), 'old');

    Api.instance.persistToken = false;
    Api.instance.token = 'new';
    expect(Api.instance.token, 'new');
    expect(GetStorage().read<String>('token'), isNull,
        reason: 'also clears the token a previous session left behind');
  });

  testWidgets('an expired session returns to sign-in and stops the controller',
      (tester) async {
    // This test is about navigation, not layout. flutter_test's placeholder
    // font is far wider than Segoe UI, so overflow reports are ignored here;
    // the Segoe-measured layout tests cover them on Windows.
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    final c = PanelHost();
    Get.put<QueueController>(c);
    c.state.value = PanelState.empty;
    await tester.binding.setSurfaceSize(const Size(800, 600));

    await tester.pumpWidget(GetMaterialApp(
      builder: (context, child) =>
          Material(type: MaterialType.transparency, child: child),
      home: const WidgetShell(),
    ));
    await tester.pump();

    await c.endSession(expired: true);
    // pumpAndSettle would never settle: the email field's cursor blinks.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text('Your session expired. Please sign in again.'),
        findsOneWidget);
    expect(Get.isRegistered<QueueController>(), isFalse,
        reason: 'a second sign-in must not run two controllers');
    expect(c.isClosed, isTrue);
  });

  testWidgets('a serving patient with nobody waiting still shows End visit',
      (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    final c = PanelHost();
    Get.put<QueueController>(c);
    c.applyResponses({
      'data': {
        'data': [
          {'id': 4, 'state': 4, 'sort_index': 1, 'token': 'HL-01', 'client': {'name': 'Saad'}},
        ],
      },
    }, {'data': {'data': []}});

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(width: 216, height: 40, child: WidgetShell()),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('End visit'), findsOneWidget);
    expect(find.text('No one in the queue'), findsNothing);
    expect(find.textContaining('Serving'), findsOneWidget);
  });
}
