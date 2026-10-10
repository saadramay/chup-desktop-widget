import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/visit.dart';
import 'tokens.dart';

/// The 82x36 action button. Three faces, only ever one shown.
///
/// ALERT and END VISIT are a single click. NO-SHOW is hold-to-confirm — it
/// writes to production, marks a real person absent, and has no undo.
class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.action,
    required this.onFire,
    this.width = 82,
    this.height = 36,
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

  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: _holdDuration,
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onFire();
        _hold.reset();
      }
    });

  // The bell rings in place of a toast: nothing to read, nothing to dismiss.
  late final AnimationController _bell = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool _hovered = false;
  bool _pressed = false;

  @override
  void dispose() {
    _hold.dispose();
    _bell.dispose();
    super.dispose();
  }

  bool get _isHold => widget.action == VisitAction.noShow;

  ({String label, Color base, Color hover}) get _face => switch (widget.action) {
        VisitAction.alert => (label: 'ALERT', base: cOrange, hover: cOrangeHover),
        VisitAction.endVisit =>
          (label: 'END VISIT', base: cGreen700, hover: cGreen700Hover),
        VisitAction.noShow => (label: 'NO-SHOW', base: cRed, hover: cRed),
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
              borderRadius: BorderRadius.circular(6),
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
                        child: ColoredBox(color: Colors.black.withValues(alpha: .28)),
                      ),
                    ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.action == VisitAction.alert)
                          _Bell(anim: _bell),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t(12, FontWeight.w800,
                                color: cWhite, spacing: 0.6),
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
  const _Bell({required this.anim});
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, _) {
        if (anim.isDismissed) return const SizedBox.shrink();
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
              child: const Icon(Icons.notifications,
                  size: 12, color: cWhite),
            ),
          ),
        );
      },
    );
  }
}
