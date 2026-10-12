import 'package:chup_widget/core/mock.dart';
import 'package:chup_widget/core/move.dart';
import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/window_anchor.dart';
import 'package:chup_widget/ui/move_card.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:chup_widget/ui/sliver_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
  'data': {'total': rows.length, 'data': rows},
};

Map<String, dynamic> row(int id, int state, int sort, String name, {int? servingMins}) => {
  'id': id,
  'state': state,
  'sort_index': sort,
  'token': 'AD $id',
  'service_id': 2214,
  'client': {'name': name},
  'created_at': DateTime.now().subtract(const Duration(minutes: 30)).toUtc().toIso8601String(),
  if (servingMins != null)
    'started_at': DateTime.now()
        .subtract(Duration(minutes: servingMins))
        .toUtc()
        .toIso8601String(),
};

void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  tearDown(Get.reset);

  group('parseMoveServices', () {
    test('reads services, their staff, and whether any-available applies', () {
      final s = parseMoveServices(Mock.moveServices());
      expect(s.map((x) => x.name), contains('Pharmacy'));
      final pharmacy = s.firstWhere((x) => x.name == 'Pharmacy');
      expect(pharmacy.staff.map((u) => u.name), ['Pharmacy Counter 1', 'Pharmacy Counter 2']);
      expect(pharmacy.anyAvailable, isTrue);
      expect(s.firstWhere((x) => x.name == 'Consultant').anyAvailable, isFalse);
    });

    test('survives odd payloads', () {
      expect(parseMoveServices({'data': null}), isEmpty);
      expect(parseMoveServices({'data': [{'name': 'no id'}]}), isEmpty);
      final s = parseMoveServices({
        'data': [
          {'id': 1, 'name': 'X', 'users': [{'name': 'no id'}, {'id': 2, 'name': 'Y'}]},
        ],
      });
      expect(s.single.staff.single.id, 2);
      expect(s.single.anyAvailable, isFalse);
    });

    test('a visit carries its service id for the move list', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses(page([row(1, 4, 1, 'A', servingMins: 3)]), page([]));
      expect(c.serving.value!.serviceId, 2214);
    });
  });

  group('window', () {
    test('widens for the Move card and returns when it closes', () async {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses(page([row(1, 4, 1, 'A', servingMins: 3)]), page([]));
      expect(c.windowWidth, kWidgetWidth);
      c.moving.value = c.serving.value;
      expect(c.windowWidth, greaterThan(kWidgetWidth + kMoveCardWidth));
      expect(c.windowHeight, greaterThanOrEqualTo(kMoveCardHeight));
      await c.cancelMove();
      expect(c.windowWidth, kWidgetWidth);
      expect(c.moving.value, isNull);
    });

    test('starting the tour closes the Move card', () async {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses(page([row(1, 4, 1, 'A', servingMins: 3)]), page([]));
      c.moving.value = c.serving.value;
      await c.startTour();
      expect(c.moving.value, isNull);
    });
  });

  testWidgets('the Move card lists services, then staff, then confirms',
      (tester) async {
    requireSegoe(segouiLoaded);
    final c = PanelHost();
    Get.put<QueueController>(c);
    c.applyResponses(page([row(1, 4, 1, 'Ahmad Faizal bin Yusof', servingMins: 9)]), page([]));
    c.moving.value = c.serving.value;
    c.moveServices.assignAll(parseMoveServices(Mock.moveServices()));

    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(width: c.windowWidth, height: c.windowHeight, child: const WidgetShell()),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(MoveCard), findsOneWidget);
    expect(find.text('Move Ahmad F.'), findsOneWidget);

    await tester.tap(find.text('Consultant'));
    await tester.pump();
    expect(find.text('Choose staff'), findsOneWidget, reason: 'no choice made yet');
    await tester.tap(find.text('Dr Rajesh Kumar a/l Subramaniam'));
    await tester.pump();
    expect(find.text('Move to Dr Rajesh Kumar a/l Subramaniam'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.tap(find.text('Pharmacy'));
    await tester.pump();
    await tester.tap(find.text('Any available'));
    await tester.pump();
    expect(find.text('Move to Pharmacy'), findsOneWidget);
  }, skip: noSegoe);

  testWidgets('the reveal row keeps 3-digit serving minutes whole beside Move',
      (tester) async {
    requireSegoe(segouiLoaded);
    final c = PanelHost();
    Get.put<QueueController>(c);
    c.size.value = WidgetSize.medium;
    c.applyResponses(
      page([row(1, 4, 1, 'Ahmad Faizal bin Yusof', servingMins: 128)]),
      page([row(2, 2, 2, 'Nur Aisyah binti Rahman'), row(3, 1, 3, 'Tan Mei Ling')]),
    );
    c.revealed.value = true;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(width: kWidgetWidth, height: c.windowHeight, child: const WidgetShell()),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SliverPanel), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(c.servingMinutes, greaterThanOrEqualTo(100));
    final minutes = tester.renderObject<RenderParagraph>(
      find.text('${c.servingMinutes}m'),
    );
    expect(minutes.didExceedMaxLines, isFalse);
    expect(minutes.size.width, greaterThanOrEqualTo(minutes.getMaxIntrinsicWidth(20) - 0.5),
        reason: 'the minutes must never be cut ("12." for 128)');
  }, skip: noSegoe);
}
