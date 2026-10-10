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
  final String stateName; // WAITING / SERVING / NO_SHOW / SERVED …

  /// When the patient physically arrived — the clock the wait is measured from.
  /// The design is explicit that this must be a timestamp, not a duration:
  /// durations freeze between polls, timestamps keep counting.
  final DateTime? arrivedAt;

  /// Their appointment slot, when they have one. Walk-ins do not.
  final DateTime? appointmentAt;

  /// When Alert was fired. Drives the GRACE countdown and switches the action
  /// button to END VISIT.
  /// TODO(backend): not yet exposed — see design/BACKEND-WIRING.md.
  final DateTime? calledAt;

  /// When the consultation started. Drives the serving meter.
  /// TODO(backend): not yet exposed — see design/BACKEND-WIRING.md.
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

  factory Visit.fromJson(Map<String, dynamic> j) {
    // `state` is an object {id, color, name}; older payloads used a flat string.
    final state = j['state'];
    final stateName = state is Map
        ? _str(state['name'])
        : _str(j['state_name'] ?? j['stateName']);

    // `client` is a relation; it is absent unless eager-loaded.
    final client = j['client'];
    final name = client is Map
        ? _str(client['name'])
        : _str(j['client_name'] ?? j['clientName']);

    // Appointment time comes off the booking relation when there is one.
    final booking = j['booking'];
    final appt = booking is Map
        ? _time(booking['started_at'] ?? booking['date'])
        : _time(j['should_be_served_at'] ?? j['shouldBeServedAt']);

    return Visit(
      id: (j['id'] as num?)?.toInt() ?? 0,
      token: _str(j['token']),
      clientName: name,
      sortIndex: (j['sort_index'] as num?)?.toInt() ?? 0,
      stateName: stateName.toUpperCase(),
      arrivedAt: _time(j['arrived_at']) ?? _time(j['created_at']),
      appointmentAt: appt,
      calledAt: _time(j['called_at'] ?? j['alerted_at']),
      startedAt: _time(j['started_at'] ?? j['serving_started_at']),
      isEndVisit: _flag(j['is_end_visit'] ?? j['isEndVisit']),
    );
  }

  // ---------------------------------------------------------------- state
  //
  // Match on the enum name, never the display label — labels arrive in Malay
  // too ("Tidak Hadir" is NO_SHOW).

  bool get isServing => stateName == 'SERVING';
  bool get isNoShow => stateName == 'NO_SHOW';

  /// Whether this patient has been called and is inside the grace window.
  bool get isCalled => calledAt != null && !isServing;

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

/// The one action offered at any moment. Never two at once — the button at rest
/// is always the outcome you expect; the outcome you dread costs a hover and a
/// hold.
enum VisitAction { alert, endVisit, noShow }
