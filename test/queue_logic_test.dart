import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/visit.dart';
import 'package:chup_widget/core/window_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

// The queue as the real API sends it: `state` is the enum integer and
// `state_name` a translated label, inside a Laravel paginator.

Map<String, dynamic> row(int id, int state,
        {int sort = 1, String label = 'x', Map<String, dynamic>? booking}) =>
    {
      'id': id,
      'token': 'AD $id',
      'sort_index': sort,
      'state': state,
      'state_name': label,
      'client': {'name': 'Patient $id'},
      'created_at': '2026-08-01T07:00:00.000000Z',
      'booking': booking,
    };

Map<String, dynamic> page(List<Map<String, dynamic>> rows,
        {int? total, Map<String, dynamic>? limits}) =>
    {
      'error': false,
      'data': {
        'current_page': 1,
        'total': total ?? rows.length,
        'data': rows,
        'limits': ?limits,
      },
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
  });

  tearDown(Get.reset);

  group('state parsing', () {
    test('reads the enum integer, never the translated label', () {
      final v = Visit.fromJson(row(1, 8, label: 'Tidak Hadir'));
      expect(v.stateName, 'NO_SHOW');
      expect(v.isNoShow, isTrue);
      expect(Visit.fromJson(row(2, 4, label: 'Sedang Dilayan')).isServing,
          isTrue);
    });

    test('an ALERTED visit counts as called without called_at', () {
      final v = Visit.fromJson(row(1, 2, label: 'Alerted'));
      expect(v.calledAt, isNull);
      expect(v.isCalled, isTrue);
    });

    test('a label-only payload still maps "No Show" to NO_SHOW', () {
      final v = Visit.fromJson({'id': 1, 'state_name': 'No Show'});
      expect(v.isNoShow, isTrue);
    });
  });

  group('appointment time', () {
    test('combines booking date and time instead of showing midnight', () {
      final v = Visit.fromJson(
          row(1, 1, booking: {'date': '2026-08-01', 'time': '14:30:00'}));
      expect(v.appointmentAt, DateTime(2026, 8, 1, 14, 30));
    });

    test('prefers the visit should_be_served_at when present', () {
      final j = row(1, 1, booking: {'date': '2026-08-01', 'time': '14:30'})
        ..['should_be_served_at'] = '2026-08-01T07:45:00.000000Z';
      expect(Visit.fromJson(j).appointmentAt,
          DateTime.utc(2026, 8, 1, 7, 45).toLocal());
    });
  });

  group('the action', () {
    test('goes ALERT, then START once called, then END VISIT', () {
      final c = PanelHost();
      Get.put<QueueController>(c);

      c.applyResponses(page([]), page([row(1, 1), row(2, 1, sort: 2)]));
      expect(c.action, VisitAction.alert);
      expect(c.next?.id, 1);

      c.applyResponses(page([]), page([row(1, 2), row(2, 1, sort: 2)]));
      expect(c.action, VisitAction.start,
          reason: 'the backend only ends a SERVING visit');
      expect(c.called.value?.calledAt, isNotNull,
          reason: 'observed locally when the API sends no called_at');

      c.applyResponses(page([row(1, 4)]), page([row(2, 1, sort: 2)]));
      expect(c.action, VisitAction.endVisit);
      expect(c.serving.value?.startedAt, isNotNull,
          reason: 'observed locally when the API sends no started_at');
    });
  });

  group('position', () {
    test('counts the same way as the total, so it never reads 7/3', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses(page([row(9, 4, sort: 7)]),
          page([row(1, 1, sort: 8), row(2, 1, sort: 9)], total: 12));
      expect(c.sessionTotal, 13);
      expect(c.positionOf(c.serving.value!), 1);
      expect(c.positionOf(c.queue.first), 2);
    });
  });

  group('limits', () {
    test('come from the serving response first', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses(
          page([], limits: {'wait_minutes': 30, 'consult_minutes': 12, 'grace_minutes': 4}),
          page([], limits: {'wait_minutes': 25, 'consult_minutes': 15, 'grace_minutes': 5}));
      expect(c.limits.value.wait.inMinutes, 30);
      expect(c.limits.value.consult.inMinutes, 12);
    });

    test('fall back to 20 / 15 / 5 when absent', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses(page([]), page([]));
      expect(c.limits.value.grace.inMinutes, 5);
    });
  });

  group('polling', () {
    test('backs off while offline and slows down when closed', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      expect(c.pollInterval.inSeconds, 10);
      c.recordFailure();
      expect(c.pollInterval.inSeconds, 10);
      c.recordFailure();
      expect(c.pollInterval.inSeconds, 20);
      for (var i = 0; i < 5; i++) {
        c.recordFailure();
      }
      expect(c.pollInterval.inSeconds, 60);

      c.applyResponses(page([]), page([]));
      c.presentation.value = Presentation.closed;
      expect(c.pollInterval.inSeconds, 60);
      c.presentation.value = Presentation.panel;
      expect(c.pollInterval.inSeconds, 10);
    });
  });

  group('tour', () {
    test('drives the button face without ever firing an action', () async {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.applyResponses(page([]), page([row(1, 1)]));

      await c.goToTourStep(7);
      expect(c.displayAction, VisitAction.start);
      expect(c.action, VisitAction.alert, reason: 'the real state is untouched');

      // Would hit the network if it got past the tour guard.
      await c.act(VisitAction.alert);
      expect(c.busyAction.value, isFalse);
      expect(c.actionError.value, isNull);

      await c.endTour();
      expect(c.displayAction, VisitAction.alert);
    });
  });

  group('panel height', () {
    test('a short session sizes to its rows, not to the size maximum', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.size.value = WidgetSize.large;
      c.applyResponses(page([]), page([row(1, 2), row(2, 1, sort: 2), row(3, 1, sort: 3)]));

      // Next patient in the band, two behind them, then END OF SESSION.
      expect(c.listRowCount, 3);
      expect(c.restingHeight, 40 + 3 * WidgetSize.large.rowHeight);

      c.revealed.value = true;
      expect(c.panelHeight, c.restingHeight + kRevealHeight,
          reason: 'the reveal gets its own height, not the missing rows');
    });

    test('a full session caps at the size maximum', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.size.value = WidgetSize.large;
      c.applyResponses(page([]), page([for (var i = 1; i <= 12; i++) row(i, 1, sort: i)]));
      expect(c.restingHeight, WidgetSize.large.height);
    });

    test('an empty queue is just the band', () {
      final c = PanelHost();
      Get.put<QueueController>(c);
      c.size.value = WidgetSize.medium;
      c.applyResponses(page([]), page([]));
      expect(c.restingHeight, WidgetSize.small.height);
    });
  });
}
