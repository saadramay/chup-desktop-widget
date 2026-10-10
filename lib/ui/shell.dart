import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/queue_controller.dart';
import '../core/window_anchor.dart';
import 'sliver_panel.dart';
import 'tokens.dart';

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

      return switch (p) {
        Presentation.panel => Container(
            decoration: BoxDecoration(
              color: cWhite,
              border: Border.all(color: cLine200),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: const SliverPanel(),
          ),
        Presentation.minimised => const _MinimisedChip(),
        Presentation.closed => const _ClosedTab(),
      };
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
          onTap: () => c.presentation.value = Presentation.panel,
          child: Container(
            decoration: BoxDecoration(
              color: cWhite,
              border: Border.all(color: cLine200),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      '${c.leadMinutes}',
                      style: t(17, FontWeight.w800,
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
        onTap: () => c.presentation.value = Presentation.panel,
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
