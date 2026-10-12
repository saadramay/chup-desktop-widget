import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/queue_controller.dart';
import '../core/window_anchor.dart';
import 'sliver_panel.dart';
import 'tokens.dart';
import 'move_card.dart';
import 'tour_card.dart';

/// Switches between the three presentations and keeps the OS window sized to
/// whichever is showing.
///
/// Neither minimise nor close removes the widget from the screen. An
/// always-on-top tool has no tray to hide in, and a doctor who dismissed it
/// mid-session would lose the queue.
class WidgetShell extends StatelessWidget {
  const WidgetShell({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();

    return Obx(() {
      final p = c.presentation.value;
      // Read here, not inside LayoutBuilder: Obx only tracks reads made
      // during its own build.
      final panelMin = c.restingHeight;
      final touring = c.tourStep.value != 0;
      final moving = c.moving.value != null;
      // A side card (tour or Move) sets the window's height; the panel keeps
      // its own.
      final sideCard = touring || moving;
      final blinking = c.blinking.value;
      final panelHeight = c.panelHeight;

      // Geometry follows presentation. Done after the frame so the window is
      // never resized mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        switch (p) {
          case Presentation.panel:
            await c.applyWindowGeometry();
          case Presentation.minimised:
            await WindowAnchor.instance.setSizeKeepingBottom(44, 44);
          case Presentation.closed:
            await WindowAnchor.instance.setEdgeTab(5, 34);
        }
      });

      // The panel may only be built into a window that can hold it.
      //
      // Windows will not make a window as small as the two other
      // presentations ask for: a 5x34 closed tab clamps to a 136x39 minimum.
      // Both of them therefore leave the *view* at 136x39 when the panel comes
      // back, and SetWindowPos has already returned success by then — so
      // awaiting the resize before flipping `presentation` (showPanel) is not
      // enough, the view reports the old size for a frame or two afterwards.
      //
      // Built into that, the band is 116px wide against a 117px headline,
      // `_ServingLine`'s row is squeezed to 33px, and 39px of window is 1px
      // short of the 38px band plus the shell's border: three overflow errors
      // for one frame's wait. Draw nothing instead; the callback above has
      // already asked for 216 and the next frame draws the panel.
      //
      // Read from the constraints rather than MediaQuery, because MediaQuery
      // answers for the *view* — which in a widget test is the test surface,
      // not the SizedBox the shell was pumped into.
      return LayoutBuilder(builder: (context, box) {
        if (p == Presentation.panel &&
            (box.maxWidth < kWidgetWidth ||
                box.maxHeight < panelMin)) {
          // Drawing nothing is only half of the fix — the other half is asking
          // for the height the panel is missing, because nothing else would.
          // main() starts the window at the *stored* size, but that handshake
          // is the only place the two agree, and a window left at 40px for a
          // 208px panel stays that way for good: transparent, ignoring the
          // cursor, looking hung. Asked here it resolves on the next frame.
          c.reclaimGeometry();
          return const SizedBox.shrink();
        }

        if (p == Presentation.panel) {
          WidgetsBinding.instance.addPostFrameCallback((_) => c.landed());
        }

        // Pinned to the window's right edge at its own width, so a wider
        // window (the tour card) never stretches or moves it. It fills the
        // window's height except while touring, when the card sets that.
        final panel = Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: kWidgetWidth,
            height: sideCard
                ? panelHeight.clamp(0.0, box.maxHeight)
                : box.maxHeight,
            child: Stack(fit: StackFit.expand, children: [
              Container(
                decoration: BoxDecoration(
                  color: cWhite,
                  border: Border.all(color: cLine200),
                  borderRadius: BorderRadius.circular(kPanelRadius),
                ),
                clipBehavior: Clip.antiAlias,
                child: const SliverPanel(),
              ),
              if (blinking) const LandingBlink(),
            ]),
          ),
        );

        return switch (p) {
          Presentation.panel => sideCard
              ? Stack(children: [
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: moving ? const MoveCard() : const TourCard(),
                  ),
                  panel,
                ])
              : panel,
          Presentation.minimised => const _MinimisedChip(),
          Presentation.closed => const _ClosedTab(),
        };
      });
    });
  }
}

/// 44 x 44. Shows the one number the resting line leads with, in the same
/// colour, with the same meter across its bottom edge.
class _MinimisedChip extends StatelessWidget {
  const _MinimisedChip();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final over = c.leadOverLimit;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => c.showPanel(),
          child: Container(
            decoration: BoxDecoration(
              color: cWhite,
              border: Border.all(color: cLine200),
              borderRadius: BorderRadius.circular(kPanelRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      '${c.leadMinutes}',
                      style: t(16, FontWeight.w600,
                          color: over ? cRed : cGreen700, tabular: true),
                    ),
                  ),
                ),
                SizedBox(
                  height: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: c.leadProgress,
                      child: ColoredBox(color: over ? cRed : cGreen700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// 5 x 34 flush to the right screen edge — the system-tray equivalent for a
/// tool that has no tray. Hover widens it; click reopens.
class _ClosedTab extends StatefulWidget {
  const _ClosedTab();

  @override
  State<_ClosedTab> createState() => _ClosedTabState();
}

class _ClosedTabState extends State<_ClosedTab> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) async {
        setState(() => _h = true);
        await WindowAnchor.instance.setEdgeTab(9, 34);
      },
      onExit: (_) async {
        setState(() => _h = false);
        await WindowAnchor.instance.setEdgeTab(5, 34);
      },
      child: GestureDetector(
        onTap: () => c.showPanel(),
        child: Container(
          decoration: BoxDecoration(
            color: _h ? cGreen600 : cGreen700,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
          ),
        ),
      ),
    );
  }
}
