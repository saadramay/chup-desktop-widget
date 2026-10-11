import 'dart:async';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'api.dart';
import 'limits.dart';
import 'mock.dart';
import 'visit.dart';
import 'window_anchor.dart';

/// The panel is 216px wide at every size. Only height changes, and it grows
/// *upward* — the bottom 38px never moves, so the action target stays put under
/// the cursor.
const double kWidgetWidth = 216;

enum WidgetSize { small, medium, large }

extension WidgetSizeX on WidgetSize {
  double get height => switch (this) {
        WidgetSize.small => 40,
        WidgetSize.medium => 128,
        WidgetSize.large => 208,
      };

  int get rows => switch (this) {
        WidgetSize.small => 0,
        WidgetSize.medium => 4,
        WidgetSize.large => 8,
      };

  double get rowHeight => switch (this) {
        WidgetSize.small => 0,
        WidgetSize.medium => 22,
        WidgetSize.large => 21,
      };

  String get label => switch (this) {
        WidgetSize.small => 'Small',
        WidgetSize.medium => 'Medium',
        WidgetSize.large => 'Large',
      };
}

/// What the panel is showing. Every state keeps the reveal reachable and puts
/// its line in the same bottom 38px the action occupies.
enum PanelState { loading, serving, empty, offline }

/// How the window itself is presented. Neither minimised nor closed removes the
/// widget from the screen — an always-on-top tool has no tray to hide in, and a
/// doctor who dismissed it mid-session would lose the queue.
enum Presentation { panel, minimised, closed }

class QueueController extends GetxController {
  final _box = GetStorage();

  // ---- data
  final serving = Rxn<Visit>(); // the patient in the room
  final called = Rxn<Visit>(); // alerted, inside the grace window
  final queue = <Visit>[].obs; // everyone waiting, in order
  final limits = const Limits().obs;
  final state = PanelState.loading.obs;
  final lastGoodPoll = Rxn<DateTime>();

  // ---- presentation
  final size = WidgetSize.small.obs;
  final presentation = Presentation.panel.obs;
  final revealed = false.obs;

  /// True while the size menu is up.
  ///
  /// `PopupMenuButton` pushes a route, and that route installs a full-screen
  /// barrier over the panel. From the moment the barrier lands the pointer no
  /// longer hits the panel's `MouseRegion`, so `onExit` fires with `false`
  /// while the menu is still open — and collapsing the reveal takes 118px of
  /// window, plus the button the menu is anchored to, out from under a menu
  /// whose items are 167px tall. The menu then draws into a 40px window:
  /// roughly one row of it, unclickable, with hover dead until it is dismissed.
  final menuOpen = false.obs;

  final busyAction = false.obs;

  /// Ticks every second so minute figures keep counting between polls.
  final now = DateTime.now().obs;

  Timer? _poll;
  Timer? _clock;

  /// The size last chosen from the menu, read straight from storage.
  ///
  /// Static because `main()` needs it before the controller exists — and it
  /// needs it badly: starting the window at a fixed 40px regardless of what
  /// was stored left a 208px panel with nowhere to go, so the shell drew
  /// nothing at all and the widget sat on the desktop blank and inert. Small
  /// is the answer whenever nothing is stored, which is every first run.
  static WidgetSize storedSize() {
    final saved = GetStorage().read<String>('size');
    return WidgetSize.values.firstWhere((s) => s.name == saved,
        orElse: () => WidgetSize.small);
  }

  @override
  void onInit() {
    super.onInit();
    size.value = storedSize();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });
    refreshNow();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => refreshNow());
  }

  @override
  void onClose() {
    _poll?.cancel();
    _clock?.cancel();
    super.onClose();
  }

  // ---------------------------------------------------------------- geometry

  Future<void> setSize(WidgetSize s) async {
    size.value = s;
    await _box.write('size', s.name);
    await applyWindowGeometry();
  }

  Future<void> setRevealed(bool v) async {
    if (revealed.value == v) return;
    // Pinned open while the menu is up — see `menuOpen`.
    if (!v && menuOpen.value) return;
    revealed.value = v;
    await applyWindowGeometry();
  }

  /// Resizes the OS window to fit the current size plus, when open, the reveal —
  /// keeping the bottom edge pinned so the action band never moves.
  Future<void> applyWindowGeometry() async {
    await WindowAnchor.instance.setSizeKeepingBottom(kWidgetWidth, windowHeight);
  }

  /// The other half of the shell's guard: the shell draws nothing when the
  /// view is smaller than the panel, but nothing else in the app would ever
  /// ask for the missing height.
  ///
  /// That was not a theoretical state. `main()` used to start the window at a
  /// fixed 40px, so a stored size of large meant a 208px panel with a 40px
  /// window to draw it into — for good, since the only code that sizes the
  /// window is here and it was not being called. The widget sat on the
  /// desktop transparent, ignoring the cursor, looking hung. Asked from the
  /// guard it resolves on the very next frame, and stops.
  Future<void> reclaimGeometry() => applyWindowGeometry();

  /// The height this presentation needs from the window, at the width above.
  ///
  /// Derived rather than commanded, so every caller agrees: `kRevealHeight`
  /// when the reveal is up, plus `kSizeMenuWindowHeight` as a floor while the
  /// size menu is showing — that menu needs more room than the small reveal
  /// has and otherwise draws its last row off the bottom of the window.
  double get windowHeight {
    final reveal = revealed.value ? kRevealHeight : 0.0;
    final h = size.value.height + reveal;
    return menuOpen.value && h < kSizeMenuWindowHeight
        ? kSizeMenuWindowHeight
        : h;
  }

  /// Back to the panel, with the window already sized for it.
  ///
  /// The order is the whole point. The alternative — flipping `presentation`
  /// first and letting the shell's post-frame callback resize — leaves a frame
  /// in which the panel is built inside whatever window the previous
  /// presentation left behind, and Windows refuses to make a window as small as
  /// those ask for: a 5x34 closed tab clamps to a 136x39 minimum. Laid out at
  /// 136 the band is 116px wide against a 117px headline, and 39px tall against
  /// the 38px band plus the shell's 1px border — so that single frame reports a
  /// horizontal overflow on the status line, another 62px on the serving row,
  /// and 1px off the bottom. Resizing first means the frame that shows the
  /// panel is the first frame at 216.
  ///
  /// A widget test has no OS window to resize, so this is guarded by measuring
  /// `GetWindowRect` against `GetClientRect` in the running app instead — the
  /// same way main()'s window setup is.
  Future<void> showPanel() async {
    try {
      await applyWindowGeometry();
    } finally {
      presentation.value = Presentation.panel;
    }
  }

  // ---------------------------------------------------------------- derived

  /// The resting line names the NEXT patient — not the one in the room. If
  /// somebody has been called, they are the subject until they are seen.
  Visit? get next => called.value ?? (queue.isEmpty ? null : queue.first);

  /// Everyone behind the next patient, trimmed to the current size.
  List<Visit> get upcoming {
    final n = next;
    final rest = queue.where((v) => v.id != n?.id).toList();
    return rest.take(size.value.rows).toList();
  }

  /// True when the visible list reaches the real end of the session, so the UI
  /// can mark it rather than leaving empty paper.
  bool get endOfSession {
    final n = next;
    final rest = queue.where((v) => v.id != n?.id).length;
    return rest <= size.value.rows;
  }

  int get sessionTotal => queue.length + (serving.value == null ? 0 : 1);

  /// Minutes the next patient has waited, or — once called — minutes since the
  /// call, because that is now the thing being waited on.
  int get leadMinutes {
    final n = next;
    if (n == null) return 0;
    return n.isCalled
        ? minutesSince(n.calledAt, now.value)
        : minutesSince(n.arrivedAt, now.value);
  }

  /// The meter tracks whatever the lead figure is measuring, against whichever
  /// threshold applies to it.
  double get leadProgress {
    final n = next;
    if (n == null) return 0;
    final limit = n.isCalled ? limits.value.grace : limits.value.wait;
    final m = limit.inMinutes;
    if (m <= 0) return 0;
    return (leadMinutes / m).clamp(0.0, 1.0);
  }

  bool get leadOverLimit {
    final n = next;
    if (n == null) return false;
    final limit = n.isCalled ? limits.value.grace : limits.value.wait;
    return leadMinutes >= limit.inMinutes;
  }

  int get servingMinutes => minutesSince(serving.value?.startedAt, now.value);
  bool get servingOverLimit =>
      serving.value != null && servingMinutes >= limits.value.consult.inMinutes;

  int get minutesSinceLastPoll => minutesSince(lastGoodPoll.value, now.value);

  /// The action the button offers right now. Exactly one, ever.
  VisitAction get action =>
      (called.value != null || serving.value != null)
          ? VisitAction.endVisit
          : VisitAction.alert;

  // ---------------------------------------------------------------- polling

  List<Visit> _rows(Map<String, dynamic> res) {
    final data = res['data'];
    // Both endpoints return a Laravel paginator: {data: {data: [...]}}.
    final list = data is Map<String, dynamic> ? data['data'] : data;
    if (list is! List) return const <Visit>[];
    return list.whereType<Map<String, dynamic>>().map(Visit.fromJson).toList();
  }

  Future<void> refreshNow() async {
    try {
      // `serving` looks like it should be a single object but is a paginated
      // list too — parsing it as an object yields a junk visit with id 0.
      final servingRows = _rows(
          kMock ? Mock.serving() : await Api.instance.get(Urls.serving));
      final queueRows =
          _rows(kMock ? Mock.visits() : await Api.instance.get(Urls.visits));

      serving.value = servingRows.isEmpty ? null : servingRows.first;
      called.value = queueRows.where((v) => v.isCalled).firstOrNull;
      queue.value = queueRows
          .where((v) => !v.isNoShow && !v.isServing)
          .toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

      lastGoodPoll.value = DateTime.now();
      state.value = (serving.value == null && queue.isEmpty)
          ? PanelState.empty
          : PanelState.serving;
    } on ApiException catch (e) {
      // A 401 means the token died; everything else is treated as unreachable
      // so the panel degrades honestly rather than lying about the queue.
      state.value = PanelState.offline;
      if (e.statusCode == 401) Api.instance.token = null;
    } catch (_) {
      state.value = PanelState.offline;
    }
  }

  // ---------------------------------------------------------------- actions

  Future<void> act(VisitAction a) async {
    if (busyAction.value) return;
    final target = switch (a) {
      VisitAction.alert => next,
      VisitAction.endVisit => serving.value ?? called.value,
      VisitAction.noShow => called.value,
    };
    if (target == null) return;

    busyAction.value = true;
    try {
      if (kMock) {
        // Never write to a real queue from fixtures.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return;
      }
      switch (a) {
        case VisitAction.alert:
          await Api.instance.put(Urls.alert(target.id));
        case VisitAction.endVisit:
          await Api.instance.put(Urls.served(target.id));
        case VisitAction.noShow:
          await Api.instance.put(Urls.noShow(target.id));
      }
      await refreshNow();
    } on ApiException {
      // Roll back by re-reading rather than guessing at local state.
      await refreshNow();
    } finally {
      busyAction.value = false;
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
