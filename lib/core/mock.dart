import 'visit.dart';

/// Fixture data, enabled with `--dart-define=MOCK=true`.
///
/// This exists because the real staging queue is usually empty and two of the
/// fields the design depends on (`called_at`, `serving.started_at`) are not
/// exposed by the API yet — so without fixtures most of the UI simply never
/// renders and cannot be worked on. See design/BACKEND-WIRING.md.
///
/// Timestamps are relative to now, so meters fill and figures tick exactly as
/// they would against live data.
const bool kMock = bool.fromEnvironment('MOCK');

class Mock {
  Mock._();

  /// Cycles through the interesting situations so every state can be reached
  /// without a backend. Change with [scenario].
  static MockScenario scenario = MockScenario.calledPatient;

  static DateTime _ago(int minutes) =>
      DateTime.now().subtract(Duration(minutes: minutes));

  static Map<String, dynamic> _visit({
    required int id,
    required String token,
    required String name,
    required int arrivedMinsAgo,
    int? appointmentInMins,
    String state = 'IN_QUEUE',
    int? calledMinsAgo,
    int? startedMinsAgo,
    int sortIndex = 1,
  }) =>
      {
        'id': id,
        'token': token,
        'sort_index': sortIndex,
        // The enum integer, as the real API sends it.
        'state': Visit.stateNames.entries
            .firstWhere((e) => e.value == state,
                orElse: () => const MapEntry(1, 'IN_QUEUE'))
            .key,
        'client': {'name': name},
        'arrived_at': _ago(arrivedMinsAgo).toIso8601String(),
        if (appointmentInMins != null)
          'should_be_served_at':
              DateTime.now().add(Duration(minutes: appointmentInMins)).toIso8601String(),
        if (calledMinsAgo != null)
          'called_at': _ago(calledMinsAgo).toIso8601String(),
        if (startedMinsAgo != null)
          'started_at': _ago(startedMinsAgo).toIso8601String(),
        'is_end_visit': 0,
      };

  /// A Laravel paginator around [rows], matching the real response shape.
  static Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
        'code': 200,
        'success': true,
        'data': {
          'current_page': 1,
          'per_page': 10,
          'total': rows.length,
          'last_page': 1,
          'data': rows,
        },
      };

  static Map<String, dynamic> serving() {
    if (scenario == MockScenario.emptyQueue) return _page([]);
    return _page([
      _visit(
        id: 900,
        token: 'AD 125',
        name: 'Ahmad Abu Bakar',
        arrivedMinsAgo: 40,
        // 18 minutes in the room: under SERVE at first, red once it passes 15.
        startedMinsAgo: scenario == MockScenario.consultOverrun ? 22 : 8,
        state: 'SERVING',
        sortIndex: 2,
      ),
    ]);
  }

  static Map<String, dynamic> visits() {
    switch (scenario) {
      case MockScenario.emptyQueue:
        return _page([]);

      case MockScenario.calledPatient:
        return _page([
          _visit(
            id: 901,
            token: 'AD 126',
            name: 'Kawthar Falah Qandeel',
            arrivedMinsAgo: 26,
            appointmentInMins: -4,
            // Called 3 minutes ago: inside GRACE, so the line reads CALLED 3M.
            calledMinsAgo: 3,
            sortIndex: 3,
          ),
          ..._tail(),
        ]);

      case MockScenario.graceExpired:
        return _page([
          _visit(
            id: 901,
            token: 'AD 126',
            name: 'Kawthar Falah Qandeel',
            arrivedMinsAgo: 31,
            appointmentInMins: -9,
            // Past GRACE (5m): the line and meter go red, No-Show is the point.
            calledMinsAgo: 7,
            sortIndex: 3,
          ),
          ..._tail(),
        ]);

      case MockScenario.longWait:
        return _page([
          _visit(
            id: 901,
            token: 'AD 126',
            name: 'Kawthar Falah Qandeel',
            // Past LIMIT (20m): red wait, full meter, nobody called yet.
            arrivedMinsAgo: 44,
            appointmentInMins: -14,
            sortIndex: 3,
          ),
          ..._tail(),
        ]);

      case MockScenario.consultOverrun:
        return _page([
          _visit(
            id: 901,
            token: 'AD 126',
            name: 'Kawthar Falah Qandeel',
            arrivedMinsAgo: 12,
            appointmentInMins: 3,
            sortIndex: 3,
          ),
          ..._tail(),
        ]);
    }
  }

  /// Enough people behind the next patient to fill Large, plus a short session
  /// so END OF SESSION can be seen at Large.
  static List<Map<String, dynamic>> _tail() => [
        for (final (i, n) in const [
          'Fatima Ameen Hani',
          'Jamaulddin Idris Khalifah',
          'Nurul Adlina',
          'Ridiana Kaidir',
          'Mimi Sulaiman',
          'Salah bin Ismail',
        ].indexed)
          _visit(
            id: 910 + i,
            token: 'HF 0${24 + i}',
            name: n,
            arrivedMinsAgo: 20 - i * 3,
            appointmentInMins: 5 + i * 10,
            sortIndex: 4 + i,
          ),
      ];
}

enum MockScenario {
  /// Somebody has been called and is inside the grace window.
  calledPatient,

  /// The called patient never appeared — grace is spent.
  graceExpired,

  /// Next patient has waited past LIMIT; nobody called.
  longWait,

  /// The consultation in the room has run past SERVE.
  consultOverrun,

  /// Nothing at all.
  emptyQueue,
}

/// Convenience for the mock tail.
extension<T> on List<T> {
  Iterable<(int, T)> get indexed sync* {
    for (var i = 0; i < length; i++) {
      yield (i, this[i]);
    }
  }
}
