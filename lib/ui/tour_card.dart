import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/queue_controller.dart';
import '../core/tour.dart';
import 'tokens.dart';

/// The first-run tour card, beside the panel and never over it.
class TourCard extends StatelessWidget {
  const TourCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final step = c.tourStep.value;
      final s = c.tour;
      if (s == null) return const SizedBox.shrink();
      final numbered = tourSteps.where((t) => !t.done).length;
      return Container(
        width: kTourCardWidth,
        height: kTourCardHeight,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: cWhite,
          border: Border.all(color: cLine200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(s.label.toUpperCase(),
                  style: t(9, FontWeight.w800, color: cGreen700, spacing: 0.7)),
              const Spacer(),
              if (!s.done)
                Text('$step / $numbered',
                    style: t(9, FontWeight.w800, color: cInk500, tabular: true)),
            ]),
            const SizedBox(height: 5),
            Text(s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t(13, FontWeight.w800, height: 1.2)),
            const SizedBox(height: 5),
            Expanded(
              child: Text(s.body,
                  overflow: TextOverflow.fade,
                  style: t(10.5, FontWeight.w500, height: 1.35)),
            ),
            const SizedBox(height: 6),
            Row(children: [
              if (!s.done)
                _TextButton('LANGKAU', onTap: c.endTour),
              const Spacer(),
              if (step > 1)
                _Button('KEMBALI',
                    primary: false, onTap: () => c.goToTourStep(step - 1)),
              const SizedBox(width: 6),
              _Button(s.done ? 'SELESAI' : 'LANJUT',
                  onTap: () => c.goToTourStep(step + 1)),
            ]),
          ],
        ),
      );
    });
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Text(label,
              style: t(9, FontWeight.w800, color: cInk500, spacing: 0.6)),
        ),
      );
}

class _Button extends StatelessWidget {
  const _Button(this.label, {required this.onTap, this.primary = true});
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? cGreen700 : cWhite,
              border: primary ? null : Border.all(color: cLine200),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: t(9.5, FontWeight.w800,
                    color: primary ? cWhite : cInk800, spacing: 0.6)),
          ),
        ),
      );
}

/// Three green ring flashes in the first half, then a halo decaying to
/// nothing. 2600ms, once, first run only.
class LandingBlink extends StatefulWidget {
  const LandingBlink({super.key});

  @override
  State<LandingBlink> createState() => _LandingBlinkState();
}

class _LandingBlinkState extends State<LandingBlink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..forward();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  double _alpha(double v) {
    if (v < 0.5) {
      // Three flashes across the first half.
      final phase = (v / 0.5 * 3) % 1;
      return phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    }
    return (1 - (v - 0.5) / 0.5) * 0.6;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, _) => DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                  color: cGreen700.withValues(alpha: _alpha(_a.value)),
                  width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
}

/// Rings [child] with a 1.5px green hairline while the tour step points at
/// [region]. The ring is always in the tree, only its colour changes, so the
/// child keeps its state as steps change.
class TourRing extends StatelessWidget {
  const TourRing({super.key, required this.region, required this.child});

  final TourRegion region;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final on = c.tourStep.value != 0 && c.tour?.highlight == region;
      return Stack(children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                    color: on ? cGreen700 : const Color(0x00000000),
                    width: 1.5),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}
