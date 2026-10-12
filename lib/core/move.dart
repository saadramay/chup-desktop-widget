/// Where a patient can be moved: a service and the staff who take its queue.
///
/// From `GET user/reception/services?for_move=1&current_service_id=…`, the
/// same list the web app's serving page uses for its Move dialog.
class MoveStaff {
  const MoveStaff({required this.id, required this.name});
  final int id;
  final String name;
}

class MoveService {
  const MoveService({
    required this.id,
    required this.name,
    required this.staff,
    required this.anyAvailable,
  });
  final int id;
  final String name;
  final List<MoveStaff> staff;

  /// The service hands patients to whoever is free when no staff is chosen
  /// (`first_available` on for the live queue), so "Any available" is offered.
  final bool anyAvailable;
}

List<MoveService> parseMoveServices(Map<String, dynamic> res) {
  final data = res['data'];
  final list = data is List ? data : (data is Map ? data['data'] : null);
  if (list is! List) return const [];
  final out = <MoveService>[];
  for (final s in list.whereType<Map>()) {
    final id = (s['id'] as num?)?.toInt();
    if (id == null) continue;
    final fa = (s['settings'] is Map ? s['settings']['first_available'] : null);
    final anyAvailable =
        fa is Map &&
        '${fa['first_available_state']}' == '1' &&
        ['both', 'live_queue'].contains(fa['first_available_for']);
    out.add(
      MoveService(
        id: id,
        name: '${s['name'] ?? ''}'.trim(),
        anyAvailable: anyAvailable,
        staff: [
          for (final u in (s['users'] as List? ?? const []).whereType<Map>())
            if (u['id'] is num)
              MoveStaff(
                id: (u['id'] as num).toInt(),
                name: '${u['name'] ?? ''}'.trim(),
              ),
        ],
      ),
    );
  }
  return out;
}
