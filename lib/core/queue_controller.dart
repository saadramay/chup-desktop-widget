import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../ui/sign_in.dart';
import '../ui/tokens.dart';
import 'api.dart';
import 'limits.dart';
import 'mock.dart';
import 'tour.dart';
import 'updater.dart';
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

  /// Short reason the last action failed, shown on the resting line for a few
  /// seconds so a failed call never looks like a successful one.
  final actionError = RxnString();

  /// Paginator `total` of the waiting list, which can exceed the rows fetched.
  final visitsTotal = 0.obs;

  /// When this app first saw a visit called (`c:<id>`) or serving (`s:<id>`).
  /// Stands in for `called_at` / `started_at` while the API does not send them.
  final Map<String, DateTime> _observed = {};

  /// A newer published version, when there is one.
  final updateVersion = RxnString();
  Release? _release;
  Timer? _updateTimer;
  final updating = false.obs;

  /// 1-based tour step, 0 when the tour is not showing.
  final tourStep = 0.obs;

  /// True for the landing blink, first run only.
  final blinking = false.obs;

  TourStep? get tour =>
      tourStep.value == 0 ? null : tourSteps[tourStep.value - 1];

  int _failures = 0;
  bool _refreshing = false;
  bool _reclaimPending = false;
  Timer? _errorTimer;

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
    return WidgetSize.values.firstWhere(
      (s) => s.name == saved,
      orElse: () => WidgetSize.small,
    );
  }

  @override
  void onInit() {
    super.onInit();
    size.value = storedSize();
    _loadObserved();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });
    refreshNow().whenComplete(_schedulePoll);
    if (Updater.enabled) {
      unawaited(checkForUpdates());
      _updateTimer = Timer.periodic(
        const Duration(hours: 6),
        (_) => checkForUpdates(),
      );
    }
  }

  @override
  void onClose() {
    _poll?.cancel();
    _clock?.cancel();
    _errorTimer?.cancel();
    _updateTimer?.cancel();
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
    // Pinned open while the menu is up — see `menuOpen` — and while a tour
    // step is showing the reveal.
    if (!v && menuOpen.value) return;
    if (!v && (tour?.open ?? false)) return;
    revealed.value = v;
    await applyWindowGeometry();
  }

  /// Resizes the OS window to fit the current size plus, when open, the reveal —
  /// keeping the bottom edge pinned so the action band never moves.
  Future<void> applyWindowGeometry() async {
    await WindowAnchor.instance.setSizeKeepingBottom(windowWidth, windowHeight);
  }

  /// The panel's width, plus room for the tour card to its left while the tour
  /// runs. The right edge is anchored, so the panel itself never moves.
  double get windowWidth =>
      tour == null ? kWidgetWidth : kWidgetWidth + kTourGap + kTourCardWidth;

  /// Rows the list shows: the people behind the next patient, plus the END OF
  /// SESSION row when the session is shorter than the size allows. Never more
  /// than the size's maximum.
  int get listRowCount {
    if (size.value.rows == 0 || next == null) return 0;
    final n = upcoming.length;
    return n < size.value.rows ? n + 1 : n;
  }

  /// The panel at rest, sized to its content rather than to the size's
  /// maximum, so a short session never leaves empty paper above the list.
  double get restingHeight =>
      WidgetSize.small.height + listRowCount * size.value.rowHeight;

  /// The panel's own height, which the window can exceed (menu, tour card).
  double get panelHeight =>
      restingHeight + (revealed.value ? kRevealHeight : 0.0);

  // ---------------------------------------------------------------- tour

  bool get firstRunCompleted => _box.read<bool>('first_run_completed') ?? false;

  /// First run only: blink once, then open the tour 800ms after landing.
  Future<void> landed() async {
    if (firstRunCompleted || blinking.value || tourStep.value != 0) return;
    blinking.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!isClosed) await startTour();
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    blinking.value = false;
  }

  Future<void> startTour() async {
    presentation.value = Presentation.panel;
    await goToTourStep(1);
  }

  Future<void> goToTourStep(int step) async {
    if (step < 1 || step > tourSteps.length) return endTour();
    tourStep.value = step;
    final s = tourSteps[step - 1];
    // Driven, not chosen: the stored size is restored when the tour ends.
    size.value = s.size;
    revealed.value = s.open;
    await applyWindowGeometry();
  }

  Future<void> endTour() async {
    tourStep.value = 0;
    await _box.write('first_run_completed', true);
    size.value = storedSize();
    revealed.value = false;
    await applyWindowGeometry();
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
  ///
  /// Called from the shell's build, so it is deferred to after the frame and
  /// coalesced: one request per frame, never a resize mid-build.
  void reclaimGeometry() {
    if (_reclaimPending) return;
    _reclaimPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _reclaimPending = false;
      await applyWindowGeometry();
    });
  }

  /// The height this presentation needs from the window, at the width above.
  ///
  /// Derived rather than commanded, so every caller agrees: `kRevealHeight`
  /// when the reveal is up, plus `kSizeMenuWindowHeight` as a floor while the
  /// size menu is showing — that menu needs more room than the small reveal
  /// has and otherwise draws its last row off the bottom of the window.
  double get windowHeight {
    var h = panelHeight;
    if (menuOpen.value && h < kSizeMenuWindowHeight) h = kSizeMenuWindowHeight;
    if (tour != null && h < kTourCardHeight) h = kTourCardHeight;
    return h;
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
    final wasClosed = presentation.value == Presentation.closed;
    try {
      await applyWindowGeometry();
    } finally {
      presentation.value = Presentation.panel;
    }
    // Polling slows right down while closed; catch up the moment it reopens.
    if (wasClosed) unawaited(refreshNow());
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

  /// Everyone in the session: the patient in the room plus the whole waiting
  /// list, not just the rows fetched.
  int get sessionTotal =>
      math.max(visitsTotal.value, queue.length) +
      (serving.value == null ? 0 : 1);

  /// 1-based place in the session, counted the same way as [sessionTotal] so
  /// the pair always reads sensibly (never "7/3").
  int positionOf(Visit v) {
    final offset = serving.value == null ? 0 : 1;
    if (serving.value?.id == v.id) return 1;
    final i = queue.indexWhere((q) => q.id == v.id);
    return i < 0 ? offset + 1 : i + 1 + offset;
  }

  /// Minutes the next patient has waited, or — once called — minutes since the
  /// call, because that is now the thing being waited on.
  /// Nobody waiting, someone in the room: the resting line names them, so
  /// END VISIT stays reachable, and the lead figures track the consultation.
  bool get onlyServing => next == null && serving.value != null;

  int get leadMinutes {
    final n = next;
    if (n == null) return onlyServing ? servingMinutes : 0;
    return n.isCalled
        ? minutesSince(n.calledAt, now.value)
        : minutesSince(n.arrivedAt, now.value);
  }

  /// The meter tracks whatever the lead figure is measuring, against whichever
  /// threshold applies to it.
  double get leadProgress {
    final n = next;
    if (n == null) {
      final consult = limits.value.consult.inMinutes;
      return onlyServing && consult > 0
          ? (servingMinutes / consult).clamp(0.0, 1.0)
          : 0;
    }
    final limit = n.isCalled ? limits.value.grace : limits.value.wait;
    final m = limit.inMinutes;
    if (m <= 0) return 0;
    return (leadMinutes / m).clamp(0.0, 1.0);
  }

  bool get leadOverLimit {
    final n = next;
    if (n == null) return onlyServing && servingOverLimit;
    final limit = n.isCalled ? limits.value.grace : limits.value.wait;
    return leadMinutes >= limit.inMinutes;
  }

  int get servingMinutes => minutesSince(serving.value?.startedAt, now.value);
  bool get servingOverLimit =>
      serving.value != null && servingMinutes >= limits.value.consult.inMinutes;

  int get minutesSinceLastPoll => minutesSince(lastGoodPoll.value, now.value);

  /// The action the button offers right now. Exactly one, ever.
  /// The backend only ends a visit that is SERVING, so a called patient is
  /// started first: ALERT, then START, then END VISIT.
  VisitAction get action {
    if (serving.value != null) return VisitAction.endVisit;
    if (called.value != null) return VisitAction.start;
    return VisitAction.alert;
  }

  // ---------------------------------------------------------------- polling

  List<Visit> _rows(Map<String, dynamic> res) {
    final data = res['data'];
    // Both endpoints return a Laravel paginator: {data: {data: [...]}}.
    final list = data is Map<String, dynamic> ? data['data'] : data;
    if (list is! List) return const <Visit>[];
    return list.whereType<Map<String, dynamic>>().map(Visit.fromJson).toList();
  }

  static int _total(Map<String, dynamic> res) {
    final data = res['data'];
    return data is Map && data['total'] is num
        ? (data['total'] as num).toInt()
        : 0;
  }

  /// `limits` sits beside the paginator keys, or at the top level.
  static Map<String, dynamic>? _limits(Map<String, dynamic> res) {
    final data = res['data'];
    final l = (data is Map ? data['limits'] : null) ?? res['limits'];
    return l is Map<String, dynamic> ? l : null;
  }

  // ---------------------------------------------------------------- observed

  void _loadObserved() {
    final raw = _box.read('observed');
    if (raw is! Map) return;
    raw.forEach((k, v) {
      final t = DateTime.tryParse('$v');
      if (t != null) _observed['$k'] = t;
    });
  }

  /// Records [key] the first time it is seen, and returns when that was.
  DateTime _seen(String key, DateTime now) =>
      _observed.putIfAbsent(key, () => now);

  /// Fills `called_at` / `started_at` from local observation when the API sent
  /// none, and forgets visits that have left the queue.
  ({Visit? serving, List<Visit> rows}) _withObserved(
    Visit? serving,
    List<Visit> rows,
  ) {
    final now = DateTime.now();
    final keep = <String>{};
    Visit? s;
    if (serving != null) {
      keep.add('s:${serving.id}');
      s = serving.withObserved(startedAt: _seen('s:${serving.id}', now));
    }
    final out = [
      for (final v in rows)
        if (v.isCalled)
          (() {
            keep.add('c:${v.id}');
            return v.withObserved(calledAt: _seen('c:${v.id}', now));
          })()
        else
          v,
    ];
    _observed.removeWhere((k, _) => !keep.contains(k));
    _box.write(
      'observed',
      _observed.map((k, v) => MapEntry(k, v.toIso8601String())),
    );
    return (serving: s, rows: out);
  }

  // ---------------------------------------------------------------- polling

  /// 10s normally; 60s while closed to the edge tab; doubling from 10s up to
  /// 60s while the server cannot be reached.
  Duration get pollInterval {
    if (state.value == PanelState.offline && _failures > 0) {
      final s = 10 * math.pow(2, math.min(_failures - 1, 3));
      return Duration(seconds: math.min(s.toInt(), 60));
    }
    if (presentation.value == Presentation.closed) {
      return const Duration(seconds: 60);
    }
    return const Duration(seconds: 10);
  }

  void _schedulePoll() {
    _poll?.cancel();
    if (isClosed) return;
    _poll = Timer(pollInterval, () async {
      await refreshNow();
      _schedulePoll();
    });
  }

  /// Folds one poll's two responses into the panel's state.
  @visibleForTesting
  void applyResponses(
    Map<String, dynamic> servingRes,
    Map<String, dynamic> visitsRes,
  ) {
    final heightBefore = panelHeight;
    final servingRows = _rows(servingRes);
    final observed = _withObserved(
      servingRows.isEmpty ? null : servingRows.first,
      _rows(visitsRes),
    );

    serving.value = observed.serving;
    called.value = observed.rows.where((v) => v.isCalled).firstOrNull;
    queue.value =
        observed.rows.where((v) => !v.isNoShow && !v.isServing).toList()
          ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
    visitsTotal.value = _total(visitsRes);
    // The serving endpoint resolves the doctor's own consult length, so it wins.
    limits.value = Limits.fromJson(_limits(servingRes) ?? _limits(visitsRes));

    _failures = 0;
    lastGoodPoll.value = DateTime.now();
    state.value = (serving.value == null && queue.isEmpty)
        ? PanelState.empty
        : PanelState.serving;

    // The list grew or shrank: follow it, bottom edge pinned.
    if (panelHeight != heightBefore &&
        presentation.value == Presentation.panel) {
      unawaited(applyWindowGeometry());
    }
  }

  /// Counts a failed poll, for [pollInterval]'s backoff.
  @visibleForTesting
  void recordFailure() {
    _failures++;
    state.value = PanelState.offline;
  }

  Future<void> refreshNow() async {
    if (_refreshing || isClosed) return;
    _refreshing = true;
    try {
      // `serving` looks like it should be a single object but is a paginated
      // list too — parsing it as an object yields a junk visit with id 0.
      final servingRes = kMock
          ? Mock.serving()
          : await Api.instance.get(Urls.serving, Urls.widgetQuery);
      final visitsRes = kMock
          ? Mock.visits()
          : await Api.instance.get(Urls.visits, Urls.listQuery);
      if (isClosed) return;
      applyResponses(servingRes, visitsRes);
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _refreshing = false;
        await endSession(expired: true);
        return;
      }
      // Everything else is treated as unreachable so the panel degrades
      // honestly rather than lying about the queue.
      recordFailure();
    } catch (_) {
      recordFailure();
    } finally {
      _refreshing = false;
    }
  }

  // ---------------------------------------------------------------- actions

  void _showActionError(String message) {
    actionError.value = message;
    _errorTimer?.cancel();
    _errorTimer = Timer(
      const Duration(seconds: 8),
      () => actionError.value = null,
    );
  }

  /// The face the button shows: the tour's while a tour step sets one.
  VisitAction get displayAction => tour?.face ?? action;

  Future<void> act(VisitAction a) async {
    if (busyAction.value) return;
    // The tour drives the panel for show; it must never write to a queue.
    if (tourStep.value != 0) return;
    final target = switch (a) {
      VisitAction.alert => next,
      VisitAction.start => called.value,
      VisitAction.endVisit => serving.value,
      VisitAction.noShow => called.value,
    };
    if (target == null) return;

    busyAction.value = true;
    actionError.value = null;
    try {
      if (kMock) {
        // Never write to a real queue from fixtures.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return;
      }
      switch (a) {
        case VisitAction.alert:
          await Api.instance.put(Urls.alert(target.id));
          _observed['c:${target.id}'] = DateTime.now();
        case VisitAction.start:
          // No force: if someone is already in the room the server says so,
          // and that message is shown rather than overridden.
          await Api.instance.put(Urls.serving_(target.id));
          _observed['s:${target.id}'] = DateTime.now();
        case VisitAction.endVisit:
          await Api.instance.put(Urls.served(target.id));
        case VisitAction.noShow:
          await Api.instance.put(Urls.noShow(target.id));
      }
      await refreshNow();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await endSession(expired: true);
        return;
      }
      _showActionError(e.message);
      await refreshNow();
    } on SocketException {
      _showActionError('Cannot reach Chup');
      await refreshNow();
    } on http.ClientException {
      _showActionError('Cannot reach Chup');
      await refreshNow();
    } on TimeoutException {
      _showActionError('Chup took too long to answer');
      await refreshNow();
    } catch (_) {
      // Not a network problem; do not blame the connection for it.
      _showActionError('Something went wrong. Try again.');
      await refreshNow();
    } finally {
      busyAction.value = false;
    }
  }

  // ---------------------------------------------------------------- updates

  /// Asks GitHub for a newer release. Quiet on failure: an update check must
  /// never get in the way of the queue.
  Future<void> checkForUpdates() async {
    try {
      _release = await Updater.check();
      updateVersion.value = _release?.version;
    } catch (_) {}
    if (kAutoUpdate && _release != null) await installUpdate();
  }

  /// Downloads and verifies the update, hands over to the swap script, and
  /// exits so the files can be replaced. The script restarts the widget.
  Future<void> installUpdate() async {
    final r = _release;
    if (r == null || updating.value) return;
    updating.value = true;
    try {
      await Updater.install(r);
      await windowManager.destroy();
    } catch (e) {
      _showActionError('Update failed. Try again later.');
    } finally {
      updating.value = false;
    }
  }

  // ---------------------------------------------------------------- session

  /// Back to the sign-in card, for sign-out and for an expired token alike.
  ///
  /// Stops this controller (timers and all) so signing in again starts a
  /// fresh one instead of running two.
  Future<void> endSession({bool expired = false}) async {
    _poll?.cancel();
    _clock?.cancel();
    if (expired) {
      Api.instance.token = null;
    } else {
      await Api.instance.signOut();
    }
    // Not awaited: Get.offAll's future only completes when the route is popped.
    unawaited(
      Get.offAll(
        () => SignInScreen(
          notice: expired
              ? 'Your session expired. Please sign in again.'
              : null,
        ),
      ),
    );
    await showSignInWindow();
    await Get.delete<QueueController>(force: true);
  }

  /// Sizes and centres the window for the sign-in card.
  Future<void> showSignInWindow() async {
    await windowManager.setSize(const Size(kSignInWidth, kSignInHeight));
    await windowManager.center();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
