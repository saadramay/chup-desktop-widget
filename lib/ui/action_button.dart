import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/visit.dart';
import 'tokens.dart';

/// The 80x30 action button. One face shown at a time.
///
/// ALERT and END VISIT are a single click. NO-SHOW is hold-to-confirm — it
/// writes to production, marks a real person absent, and has no undo.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.action,
    required this.onFire,
    this.width = 80,
    this.height = 30,
    this.holdLabel,
  });

  final VisitAction action;
  final VoidCallback onFire;
  final double width;
  final double height;

  /// When set, the label carries the patient's name so there is no doubt who is
  /// being marked absent.
  final String? holdLabel;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 550);

  /// Built in [initState], never lazily.
  ///
  /// A `late final` field initialised at its declaration is only realised the
  /// first time it is read — and `dispose()` reads them. So a button that was
  /// never held (END VISIT: no one has been alerted) would construct its
  /// AnimationController *during* dispose, which calls
  /// `TickerProviderStateMixin.createTicker` on an already-deactivated element
  /// and throws "Looking up a deactivated widget's ancestor is unsafe."
  late final AnimationController _hold;
  late final AnimationController _bell;

  @override
  void initState() {
    super.initState();
    _hold = AnimationController(
      vsync: this,
      duration: _holdDuration,
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          widget.onFire();
          _hold.reset();
        }
      });

    // The bell rings in place of a toast: nothing to read, nothing to dismiss.
    _bell = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  bool _hovered = false;
  bool _pressed = false;

  @override
  void dispose() {
    _hold.dispose();
    _bell.dispose();
    super.dispose();
  }

  bool get _isHold => widget.action == VisitAction.noShow;

  ({String label, IconData icon, Color base, Color hover, Color ink})
      get _face => switch (widget.action) {
            VisitAction.alert => (
                label: 'Alert',
                icon: Icons.notifications_rounded,
                base: cOrange,
                hover: cOrangeHover,
                ink: cWhite,
              ),
            VisitAction.start => (
                label: 'Start',
                icon: Icons.play_arrow_rounded,
                base: cGreen600,
                hover: cGreen700Hover,
                ink: cWhite,
              ),
            VisitAction.endVisit => (
                label: 'End visit',
                icon: Icons.check_rounded,
                base: cGreen700,
                hover: cGreen700Hover,
                ink: cWhite,
              ),
            // Quiet until held: the outcome you dread should not shout.
            VisitAction.noShow => (
                label: 'No-show',
                icon: Icons.person_off_rounded,
                base: cRedTint,
                hover: const Color(0xFFFADAD8),
                ink: cRed,
              ),
          };

  void _fireImmediate() {
    if (widget.action == VisitAction.alert) _bell.forward(from: 0);
    widget.onFire();
  }

  @override
  Widget build(BuildContext context) {
    final f = _face;
    final label = widget.holdLabel ?? f.label;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() => _hovered = false);
        if (_isHold) _hold.reset();
      },
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _pressed = true);
          if (_isHold) _hold.forward(from: 0);
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
          // Releasing early cancels — the fill sweep is the only feedback.
          if (_isHold) {
            _hold.reset();
          } else {
            _fireImmediate();
          }
        },
        onTapCancel: () {
          setState(() => _pressed = false);
          if (_isHold) _hold.reset();
        },
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Transform.translate(
            offset: Offset(0, _pressed ? 0.5 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kControlRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: _hovered ? f.hover : f.base),
                  if (_isHold)
                    AnimatedBuilder(
                      animation: _hold,
                      builder: (_, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _hold.value,
                        child: ColoredBox(color: cRed.withValues(alpha: .22)),
                      ),
                    ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The bell rings in place of the static icon after Alert.
                        if (widget.action == VisitAction.alert)
                          _Bell(anim: _bell, fallback: f.icon)
                        else
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(f.icon, size: 15, color: f.ink),
                          ),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t(12.5, FontWeight.w600, color: f.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scales in, then rings with a decaying rotation and two expanding waves.
class _Bell extends StatelessWidget {
  const _Bell({required this.anim, required this.fallback});
  final Animation<double> anim;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, _) {
        if (anim.isDismissed) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(fallback, size: 15, color: cWhite),
          );
        }
        final v = anim.value;
        final scale = v < .2 ? (0.45 + (v / .2) * 0.55) : 1.0;
        // ±15deg, decaying to nothing.
        final swing = math.sin(v * math.pi * 6) * (1 - v) * 0.26;
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Transform.scale(
            scale: scale,
            child: Transform.rotate(
              angle: swing,
              child: Icon(fallback, size: 15, color: cWhite),
            ),
          ),
        );
      },
    );
  }
}
