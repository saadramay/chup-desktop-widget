/// The three durations the whole design reasons about.
///
/// All three are backend-owned (`limits` in the poll payload). Until the API
/// exposes them these defaults stand — see design/BACKEND-WIRING.md.
class Limits {
  const Limits({
    this.wait = const Duration(minutes: 20),
    this.consult = const Duration(minutes: 15),
    this.grace = const Duration(minutes: 5),
  });

  /// Wait threshold. A patient waiting longer than this is red. One flat figure
  /// for the whole queue, not per patient.
  final Duration wait;

  /// Default consultation length — per clinic per doctor. A room past it is red.
  ///
  /// `wait` and `consult` deliberately differ: twenty minutes waiting is a
  /// failure, twenty minutes in consultation is often the job.
  final Duration consult;

  /// How long a called patient has before the widget suggests they aren't coming.
  final Duration grace;

  /// TODO(backend): replace with `limits` from the poll payload once the API
  /// exposes it. Falls back to these defaults if absent.
  factory Limits.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Limits();
    Duration mins(dynamic v, Duration fallback) =>
        v is num ? Duration(minutes: v.round()) : fallback;
    return Limits(
      wait: mins(j['wait_minutes'], const Duration(minutes: 20)),
      consult: mins(j['consult_minutes'], const Duration(minutes: 15)),
      grace: mins(j['grace_minutes'], const Duration(minutes: 5)),
    );
  }
}

/// Whole minutes since [t], never negative. The design counts in minutes
/// everywhere and derives them from the clock so figures keep ticking between
/// polls instead of freezing at whatever the last response said.
int minutesSince(DateTime? t, DateTime now) {
  if (t == null) return 0;
  final m = now.difference(t).inMinutes;
  return m < 0 ? 0 : m;
}
