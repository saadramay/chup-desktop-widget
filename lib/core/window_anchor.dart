import 'dart:ui';

import 'package:get_storage/get_storage.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Height the hover reveal needs above the action band.
const double kRevealHeight = 112;

/// Resting distance from the right and bottom screen edges.
const double kEdgeInset = 12;

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

  Future<void> savePosition(double r, double b) async {
    await _box.write('pos_right', r);
    await _box.write('pos_bottom', b);
  }

  Future<Rect> _workArea() async {
    final d = await screenRetriever.getPrimaryDisplay();
    final size = d.visibleSize ?? d.size;
    final origin = d.visiblePosition ?? Offset.zero;
    return Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
  }

  /// Places a window of [w]x[h] at the stored corner offsets, clamped so the
  /// reveal always has room to open upward without running off the top.
  Future<void> setSizeKeepingBottom(double w, double h) async {
    final area = await _workArea();
    final x = area.right - w - right;
    var y = area.bottom - h - bottom;

    // Reserve the reveal's headroom so the panel can never park somewhere the
    // reveal would open past the top of the screen.
    final minY = area.top + kRevealHeight;
    if (y < minY) y = minY;

    await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
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
  Future<void> rememberCurrentPosition() async {
    final area = await _workArea();
    final b = await windowManager.getBounds();
    await savePosition(
      (area.right - b.right).clamp(0.0, area.width),
      (area.bottom - b.bottom).clamp(0.0, area.height),
    );
  }
}
