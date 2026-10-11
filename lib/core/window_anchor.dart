import 'dart:ui';

import 'package:get_storage/get_storage.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Height the hover reveal needs above the action band.
///
/// Measured, not guessed: the tallest reveal (someone in the room AND someone
/// called, so the NO-SHOW hold button is showing) needs 116px inside the
/// shell's 1px border, and the shell's border takes 2 more. At 112 the reveal
/// clipped the NO-SHOW button by exactly 6px — 118 is the smallest whole
/// number that fits. Guarded by test/reveal_height_test.dart.
const double kRevealHeight = 118;

/// Resting distance from the right and bottom screen edges.
const double kEdgeInset = 12;

/// Window height the size menu needs, measured the same way as kRevealHeight.
///
/// The menu opens *under* a button that sits about 21px down the reveal, and
/// its items are 30px each: six of them plus the divider and the surface's
/// own padding put the last row's bottom at ~218. The small size's reveal is
/// only 40 + kRevealHeight = 158 tall, which clipped the last rows to an
/// unreadable sliver.
///
/// 242 fits it with the same spare room 212 left for five rows; medium and
/// large are already at least this tall, so the value only ever bites on small.
/// `QueueController.windowHeight` is what applies it, guarded by
/// test/size_menu_pin_test.dart.
/// 272 since the version / update row joined the menu (seven rows).
const double kSizeMenuWindowHeight = 272;

/// Keeps the panel pinned to its corner while its height changes.
///
/// The design is explicit that the bottom 38px must never move: the panel grows
/// upward, so every resize has to move the window's top edge and leave its
/// bottom where it was. Setting size alone would grow it downward, off-screen.
class WindowAnchor {
  WindowAnchor._();
  static final WindowAnchor instance = WindowAnchor._();

  final _box = GetStorage();

  /// Offsets from the bottom-right of the work area. Persisted so the widget
  /// returns to where the doctor put it, across minimise, close and restart.
  double get right => _box.read<double>('pos_right') ?? kEdgeInset;
  double get bottom => _box.read<double>('pos_bottom') ?? kEdgeInset;

  /// The display the widget was last parked on. Offsets are relative to it, so
  /// a widget dragged to a second monitor stays there across resizes.
  String? get displayId => _box.read<String>('pos_display');

  Future<void> savePosition(double r, double b, {String? display}) async {
    await _box.write('pos_right', r);
    await _box.write('pos_bottom', b);
    if (display != null) await _box.write('pos_display', display);
  }

  static Rect _area(Display d) {
    final size = d.visibleSize ?? d.size;
    final origin = d.visiblePosition ?? Offset.zero;
    return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
  }

  /// The stored display when it is still connected, otherwise the primary.
  Future<Display> _display() async {
    final id = displayId;
    if (id != null) {
      final all = await screenRetriever.getAllDisplays();
      for (final d in all) {
        if (d.id == id) return d;
      }
    }
    return screenRetriever.getPrimaryDisplay();
  }

  Future<Rect> _workArea() async => _area(await _display());

  /// Places a window of [w]x[h] at the stored corner offsets, clamped so the
  /// reveal always has room to open upward without running off the top.
  Future<void> setSizeKeepingBottom(double w, double h) async {
    await windowManager.setBounds(await boundsFor(w, h));
  }

  /// Where a [w]x[h] window sits at the stored corner, without moving it.
  Future<Rect> boundsFor(double w, double h) async {
    final area = await _workArea();
    final x = area.right - w - right;
    var y = area.bottom - h - bottom;

    // Reserve the reveal's headroom so the panel can never park somewhere the
    // reveal would open past the top of the screen.
    final minY = area.top + kRevealHeight;
    if (y < minY) y = minY;

    return Rect.fromLTWH(x, y, w, h);
  }

  /// The closed tab sits flush to the right screen edge, at the same height the
  /// panel occupied — not at the stored inset.
  Future<void> setEdgeTab(double w, double h) async {
    final area = await _workArea();
    await windowManager.setBounds(
      Rect.fromLTWH(area.right - w, area.bottom - h - bottom, w, h),
    );
  }

  /// After a drag, convert the window's absolute position back into corner
  /// offsets so later resizes keep the same anchor.
  ///
  /// The display is whichever one now holds the window's centre.
  Future<void> rememberCurrentPosition() async {
    final b = await windowManager.getBounds();
    final all = await screenRetriever.getAllDisplays();
    Display? on;
    for (final d in all) {
      if (_area(d).contains(b.center)) on = d;
    }
    on ??= await screenRetriever.getPrimaryDisplay();
    final area = _area(on);
    await savePosition(
      (area.right - b.right).clamp(0.0, area.width),
      (area.bottom - b.bottom).clamp(0.0, area.height),
      display: on.id,
    );
  }
}
