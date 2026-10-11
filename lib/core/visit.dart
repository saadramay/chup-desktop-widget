/// One visit, as the widget needs it.
///
/// Field names follow the API's snake_case payload — the authority is
/// `app/Http/Resources/Visits/VisitResource.php` in the chup.online repo.
class Visit {
  Visit({
    required this.id,
    required this.token,
    required this.clientName,
    required this.sortIndex,
    required this.stateName,
    required this.arrivedAt,
    required this.appointmentAt,
    required this.calledAt,
    required this.startedAt,
    required this.isEndVisit,
  });

  final int id;
  final String token; // queue number, e.g. "AD 126"
  final String clientName;
  final int sortIndex; // position within the session
  final String stateName; // enum name: IN_QUEUE / ALERTED / SERVING / NO_SHOW …

  /// When the patient physically arrived — the clock the wait is measured from.
  /// The design is explicit that this must be a timestamp, not a duration:
  /// durations freeze between polls, timestamps keep counting.
  final DateTime? arrivedAt;

  /// Their appointment slot, when they have one. Walk-ins do not.
  final DateTime? appointmentAt;

  /// When Alert was fired. Drives the GRACE countdown. From the API when it
  /// sends `called_at`, otherwise from when this app first saw the alert.
  final DateTime? calledAt;

  /// When the consultation started. Drives the serving meter. From the API
  /// when it sends `started_at`, otherwise from when this app first saw it.
  final DateTime? startedAt;

  final bool isEndVisit;

  // ---------------------------------------------------------------- parsing

  /// The API returns `is_*` flags as 0/1 rather than JSON booleans. A client
  /// typing these as `bool` throws on decode.
  static bool _flag(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return false;
  }

  static String _str(dynamic v) => v?.toString() ?? '';

  static DateTime? _time(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  /// `App\Enums\Visit\State` on the backend. The API serialises `state` as
  /// this integer; `state_name` is a translated label ("No Show", "Tidak
  /// Hadir"), so it is never matched on.
  static const stateNames = <int, String>{
    1: 'IN_QUEUE',
    2: 'ALERTED',
    3: 'ARRIVED',
    4: 'SERVING',
    5: 'SERVED',
    6: 'DELAYED',
    7: 'CANCELED',
    8: 'NO_SHOW',
    9: 'EARLY_ARRIVED',
    10: 'MOVED',
    11: 'ON_HOLD',
  };

  static String _stateName(Map<String, dynamic> j) {
    final state = j['state'];
    if (state is num) return stateNames[state.toInt()] ?? '';
    if (state is String && int.tryParse(state) != null) {
      return stateNames[int.parse(state)] ?? '';
    }
    // Older payloads nested {id, name}; a label is the last resort.
    final label = state is Map
        ? _str(state['name'])
        : _str(j['state_name'] ?? j['stateName']);
    return label.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
  }

  /// Booking `date` and `time` are uncast wall-clock strings in clinic time.
  static DateTime? _bookingTime(dynamic booking) {
    if (booking is! Map) return null;
    final date = DateTime.tryParse(_str(booking['date']).split(RegExp('[T ]')).first);
    final time = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(_str(booking['time']));
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, int.parse(time.group(1)!),
        int.parse(time.group(2)!));
  }

  factory Visit.fromJson(Map<String, dynamic> j) {
    // `client` is a relation; it is absent unless eager-loaded.
    final client = j['client'];
    final name = client is Map
        ? _str(client['name'])
        : _str(j['client_name'] ?? j['clientName']);

    return Visit(
      id: (j['id'] as num?)?.toInt() ?? 0,
      token: _str(j['token']),
      clientName: name,
      sortIndex: (j['sort_index'] as num?)?.toInt() ?? 0,
      stateName: _stateName(j),
      arrivedAt: _time(j['arrived_at']) ?? _time(j['created_at']),
      appointmentAt: _time(j['should_be_served_at'] ?? j['shouldBeServedAt']) ??
          _bookingTime(j['booking']),
      calledAt: _time(j['called_at'] ?? j['alerted_at']),
      startedAt: _time(j['started_at'] ?? j['serving_started_at']),
      isEndVisit: _flag(j['is_end_visit'] ?? j['isEndVisit']),
    );
  }

  /// The same visit with locally observed timestamps filled in where the API
  /// sent none.
  Visit withObserved({DateTime? calledAt, DateTime? startedAt}) => Visit(
        id: id,
        token: token,
        clientName: clientName,
        sortIndex: sortIndex,
        stateName: stateName,
        arrivedAt: arrivedAt,
        appointmentAt: appointmentAt,
        calledAt: this.calledAt ?? calledAt,
        startedAt: this.startedAt ?? startedAt,
        isEndVisit: isEndVisit,
      );

  // ---------------------------------------------------------------- state
  //
  // Match on the enum name, never the display label — labels arrive in Malay
  // too ("Tidak Hadir" is NO_SHOW).

  bool get isServing => stateName == 'SERVING';
  bool get isNoShow => stateName == 'NO_SHOW';
  bool get isAlerted => stateName == 'ALERTED';

  /// Called and not yet in the room. The ALERTED state is enough on its own:
  /// the API does not always send `called_at`.
  bool get isCalled => (isAlerted || calledAt != null) && !isServing;

  /// The resting line shortens names; only the reveal shows them in full.
  /// "Kawthar Falah Qandeel" -> "Kawthar F."
  String get shortName {
    final parts = clientName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    return '${parts.first} ${parts[1].characters}.'.replaceAll('..', '.');
  }

  String get initial =>
      clientName.trim().isEmpty ? '?' : clientName.trim()[0].toUpperCase();
}

/// Convenience so `shortName` can take one character without importing
/// `characters` package semantics everywhere.
extension on String {
  String get characters => isEmpty ? '' : substring(0, 1);
}

/// The one action offered at any moment: ALERT, then START once the patient is
/// called (the backend only ends a visit that is serving), then END VISIT.
/// Never two at once — the button at rest
/// is always the outcome you expect; the outcome you dread costs a hover and a
/// hold.
enum VisitAction { alert, start, endVisit, noShow }
