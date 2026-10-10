import 'package:chup_widget/core/limits.dart';
import 'package:chup_widget/core/visit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Visit.fromJson', () {
    test('coerces the 0/1 integers the API sends for boolean flags', () {
      // The API returns is_* flags as 0/1, not JSON booleans. A client typing
      // them as bool throws on decode.
      expect(Visit.fromJson({'id': 1, 'is_end_visit': 0}).isEndVisit, isFalse);
      expect(Visit.fromJson({'id': 1, 'is_end_visit': 1}).isEndVisit, isTrue);
      expect(Visit.fromJson({'id': 1, 'is_end_visit': true}).isEndVisit, isTrue);
    });

    test('reads state and client from the nested resource shape', () {
      final v = Visit.fromJson({
        'id': 7,
        'token': 'AD 126',
        'sort_index': 3,
        'state': {'id': 2, 'name': 'serving', 'color': '#0c6e3c'},
        'client': {'name': 'Ahmad Abu'},
      });
      expect(v.stateName, 'SERVING');
      expect(v.isServing, isTrue);
      expect(v.clientName, 'Ahmad Abu');
      expect(v.sortIndex, 3);
    });

    test('prefers arrived_at over created_at as the wait clock', () {
      final v = Visit.fromJson({
        'id': 1,
        'arrived_at': '2026-08-01T15:05:00+08:00',
        'created_at': '2026-08-01T09:00:00+08:00',
      });
      expect(v.arrivedAt!.toUtc().hour, 7); // 15:05 +08:00
    });

    test('survives missing fields rather than throwing', () {
      final v = Visit.fromJson({});
      expect(v.id, 0);
      expect(v.clientName, '');
      expect(v.arrivedAt, isNull);
    });
  });

  group('the resting line', () {
    test('shortens the name; the reveal is what shows it in full', () {
      final v = Visit.fromJson({
        'id': 1,
        'client': {'name': 'Kawthar Falah Qandeel'},
      });
      expect(v.shortName, 'Kawthar F.');
      expect(v.clientName, 'Kawthar Falah Qandeel');
    });

    test('leaves a single name alone', () {
      final v = Visit.fromJson({
        'id': 1,
        'client': {'name': 'Yaya'},
      });
      expect(v.shortName, 'Yaya');
    });
  });

  group('called state', () {
    test('a called patient is what flips the action to END VISIT', () {
      final v = Visit.fromJson({
        'id': 1,
        'called_at': '2026-08-01T15:31:00+08:00',
        'state': {'name': 'WAITING'},
      });
      expect(v.isCalled, isTrue);
    });

    test('a patient already in the room is not "called"', () {
      final v = Visit.fromJson({
        'id': 1,
        'called_at': '2026-08-01T15:31:00+08:00',
        'state': {'name': 'SERVING'},
      });
      expect(v.isCalled, isFalse);
    });
  });

  group('minutesSince', () {
    final now = DateTime(2026, 8, 1, 15, 45);

    test('counts whole minutes from a timestamp', () {
      expect(minutesSince(DateTime(2026, 8, 1, 15, 5), now), 40);
    });

    test('never goes negative for a future timestamp', () {
      expect(minutesSince(DateTime(2026, 8, 1, 16, 0), now), 0);
    });

    test('treats a missing timestamp as zero', () {
      expect(minutesSince(null, now), 0);
    });
  });

  group('Limits', () {
    test('defaults to 20 / 15 / 5 when the backend sends nothing', () {
      const l = Limits();
      expect(l.wait.inMinutes, 20);
      expect(l.consult.inMinutes, 15);
      expect(l.grace.inMinutes, 5);
    });

    test('wait and consult differ deliberately', () {
      // Twenty minutes waiting is a failure; twenty minutes in consultation is
      // often the job.
      const l = Limits();
      expect(l.wait, isNot(equals(l.consult)));
    });

    test('takes the backend values when present', () {
      final l = Limits.fromJson(
          {'wait_minutes': 30, 'consult_minutes': 10, 'grace_minutes': 3});
      expect(l.wait.inMinutes, 30);
      expect(l.consult.inMinutes, 10);
      expect(l.grace.inMinutes, 3);
    });
  });
}
