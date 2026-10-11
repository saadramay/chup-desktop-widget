import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../core/api.dart';
import '../core/limits.dart';
import '../core/queue_controller.dart';
import '../core/visit.dart';
import '../core/window_anchor.dart';
import 'action_button.dart';
import 'sign_in.dart';
import 'tokens.dart';

/// The widget at rest plus its hover reveal.
///
/// Geometry that is load-bearing: the bottom 38px is identical at every size and
/// always sits the same distance from the screen corner. Growing the panel adds
/// rows upward and opens the reveal upward, so the action target never moves
/// under the cursor.
class SliverPanel extends StatelessWidget {
  const SliverPanel({super.key});

  QueueController get c => Get.find<QueueController>();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => c.setRevealed(true),
      onExit: (_) => c.setRevealed(false),
      child: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (c.revealed.value) const Expanded(child: _Reveal()),
            _QueueRows(),
            const _RestingBand(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- resting band

class _RestingBand extends StatelessWidget {
  const _RestingBand();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final state = c.state.value;
      return SizedBox(
        // 40 is the window; the shell's 1px border takes a pixel off each edge,
        // so the band's own box is the 38 the design calls "the bottom 38px"
        // (design/README.md). At 40 it claimed 2px more than the column had,
        // even once the window itself was the right size.
        height: 38,
        child: Column(
          children: [
            Expanded(
              child: switch (state) {
                PanelState.serving => const _ServingLine(),
                PanelState.empty => const _StatusLine(
                    text: 'NO ONE IN THE QUEUE', color: cInk500),
                PanelState.loading =>
                  const _StatusLine(text: 'READING THE QUEUE', color: cInk500),
                PanelState.offline => _StatusLine(
                    text: 'CANNOT REACH CHUP',
                    color: cRed,
                    trailing: c.lastGoodPoll.value == null
                        ? null
                        : 'LAST READ ${c.minutesSinceLastPoll}M AGO',
                  ),
              },
            ),
            const _LeadMeter(),
          ],
        ),
      );
    });
  }
}

/// The resting line names the NEXT patient, not the one in the room.
class _ServingLine extends StatelessWidget {
  const _ServingLine();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final n = c.next;
      if (n == null) {
        return const _StatusLine(text: 'NO ONE IN THE QUEUE', color: cInk500);
      }
      final called = n.isCalled;
      final over = c.leadOverLimit;
      final mins = c.leadMinutes;

      return Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 9),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t(11.5, FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${n.sortIndex}/${c.sessionTotal}',
                        style: t(9.5, FontWeight.w800,
                            color: cInk500, tabular: true),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(_clock(n.appointmentAt),
                          style: t(10, FontWeight.w700, tabular: true)),
                      const Spacer(),
                      Text(
                        called ? 'CALLED ${mins}M' : '${mins}M WAITING',
                        style: t(9, FontWeight.w800,
                            color: over ? cRed : cInk500,
                            spacing: 0.4,
                            tabular: true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.all(2),
            child: ActionButton(
              action: c.action,
              onFire: () => c.act(c.action),
            ),
          ),
        ],
      );
    });
  }
}

String _clock(DateTime? d) {
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h.$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, required this.color, this.trailing});
  final String text;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        // Two strings have to share one line and the line's width is not theirs
        // to choose: 216 minus the shell's 1px border and this 9px on each side
        // is 196, and the offline pair needs 214 of it. Both used to be laid out
        // at the Row's full width with a Spacer between them, so once the two
        // together outgrew the band the Spacer collapsed to nothing and neither
        // gave way — the Row just reported an overflow.
        //
        // Now the headline, which is the part that names the state, takes what
        // it needs up to the whole line, and the trailing clock is an Expanded
        // that gets the remainder and ellipsises into it. Sum of the two can
        // never exceed the Row, so there is no width at which this overflows.
        child: Row(
          children: [
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t(9.5, FontWeight.w800, color: color, spacing: 0.5),
            ),
            if (trailing != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: t(9, FontWeight.w800, color: cInk500, spacing: 0.4),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// 3px along the bottom edge. Tracks the same person the line names — the wait,
/// or once called, the grace window.
class _LeadMeter extends StatelessWidget {
  const _LeadMeter();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final loading = c.state.value == PanelState.loading;
      return SizedBox(
        height: 3,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: loading ? 1 : c.leadProgress,
            child: ColoredBox(
              color: loading
                  ? cGreen700.withValues(alpha: .25)
                  : (c.leadOverLimit ? cRed : cGreen700),
            ),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------- queue rows

class _QueueRows extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final rows = c.upcoming;
      if (c.size.value.rows == 0) return const SizedBox.shrink();
      final h = c.size.value.rowHeight;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in rows)
            Container(
              height: h,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: cLine200)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(v.shortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t(10, FontWeight.w600)),
                  ),
                  Text('${minutesSince(v.arrivedAt, c.now.value)}M',
                      style: t(9, FontWeight.w800,
                          color: cInk500, tabular: true)),
                ],
              ),
            ),
          // Mark the true end of the list rather than leaving empty paper.
          if (c.endOfSession && rows.length < c.size.value.rows)
            Container(
              height: h,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: cLine200)),
              ),
              child: Text('END OF SESSION',
                  style: t(8.5, FontWeight.w800,
                      color: cInk500, spacing: 0.8)),
            ),
        ],
      );
    });
  }
}

// ---------------------------------------------------------------- reveal

class _Reveal extends StatelessWidget {
  const _Reveal();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final s = c.serving.value;
      final called = c.called.value;
      return Container(
        decoration: const BoxDecoration(
          color: cWhite,
          border: Border(bottom: BorderSide(color: cLine200)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
        ),
        padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(s == null ? 'CHUP' : 'NOW',
                    style: t(10, FontWeight.w800,
                        color: cGreen700, spacing: 0.8)),
                const Spacer(),
                const _ControlCluster(),
              ],
            ),
            const SizedBox(height: 2),
            if (s != null) ...[
              // Full name — only the resting line shortens. One line, though:
              // the reveal's height is fixed, so a name that wrapped to two
              // lines would push the NO-SHOW button off the bottom of the
              // panel (measured: 42px past it for a three-line name).
              Text(s.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      t(19, FontWeight.w700, height: 1.1, spacing: -0.19)),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(s.token,
                      style: t(15, FontWeight.w800,
                          color: cGreen600, tabular: true)),
                  const SizedBox(width: 5),
                  Text('${s.sortIndex}/${c.sessionTotal}',
                      style:
                          t(12, FontWeight.w800, color: cInk500, tabular: true)),
                  const SizedBox(width: 5),
                  Text('· SERVING ${c.servingMinutes}M',
                      style: t(12, FontWeight.w800,
                          color: c.servingOverLimit ? cRed : cInk500,
                          tabular: true)),
                ],
              ),
              const SizedBox(height: 4),
              _ServingMeter(),
            ] else
              Text('No consultation in progress',
                  style: t(11.5, FontWeight.w500, color: cInk500)),
            if (called != null) ...[
              const SizedBox(height: 6),
              ActionButton(
                action: VisitAction.noShow,
                width: double.infinity,
                height: 24,
                holdLabel: 'NO-SHOW · ${called.shortName}',
                onFire: () => c.act(VisitAction.noShow),
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _ServingMeter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final consult = c.limits.value.consult.inMinutes;
      final f = consult == 0 ? 0.0 : (c.servingMinutes / consult).clamp(0.0, 1.0);
      return SizedBox(
        height: 2,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: f,
            child: ColoredBox(color: c.servingOverLimit ? cRed : cGreen700),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------- controls

class _ControlCluster extends StatelessWidget {
  const _ControlCluster();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The grip is the ONLY drag handle. Nothing else on the panel drags.
        _Ctl(
          icon: Icons.drag_indicator,
          tooltip: 'Move',
          cursor: SystemMouseCursors.grab,
          onDragStart: () async {
            await windowManager.startDragging();
            await WindowAnchor.instance.rememberCurrentPosition();
          },
        ),
        _Ctl(
          icon: Icons.open_in_new,
          tooltip: 'Open in Chup',
          onTap: () {}, // TODO(dev): launch the web queue URL
        ),
        _SizeMenu(),
        _Ctl(
          icon: Icons.remove,
          tooltip: 'Minimise',
          onTap: () => c.presentation.value = Presentation.minimised,
        ),
        _Ctl(
          icon: Icons.close,
          tooltip: 'Close',
          danger: true,
          onTap: () => c.presentation.value = Presentation.closed,
        ),
      ],
    );
  }
}

class _Ctl extends StatefulWidget {
  const _Ctl({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.onDragStart,
    this.danger = false,
    this.cursor = SystemMouseCursors.click,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onDragStart;
  final bool danger;
  final MouseCursor cursor;

  @override
  State<_Ctl> createState() => _CtlState();
}

class _CtlState extends State<_Ctl> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final fg = _h ? (widget.danger ? cRed : cGreen700) : cInk500;
    final bg = _h ? (widget.danger ? cRedWash : cGreen50) : null;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onPanStart:
              widget.onDragStart == null ? null : (_) => widget.onDragStart!(),
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(left: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(widget.icon, size: 13, color: fg),
          ),
        ),
      ),
    );
  }
}

class _SizeMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return PopupMenuButton<Object>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      splashRadius: 12,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 132),
      // Hold the reveal open for as long as the menu is up: the route's own
      // barrier is what makes the panel's MouseRegion report an exit, and
      // without this the window collapses under the menu the instant it opens.
      // The geometry follows too — see kSizeMenuWindowHeight.
      onOpened: () {
        c.menuOpen.value = true;
        c.applyWindowGeometry();
      },
      onCanceled: () {
        c.menuOpen.value = false;
        c.applyWindowGeometry();
      },
      onSelected: (v) async {
        c.menuOpen.value = false;
        if (v is WidgetSize) {
          await c.setSize(v);
        } else if (v == 'signout') {
          await Api.instance.signOut();
          Get.offAll(() => const SignInScreen());
          // The card is kSignInWidth x kSignInHeight and centred; the window
          // is still the panel's 216 x 40 tucked into a screen corner. Without
          // this the card renders inside the panel's window and overflows it
          // by hundreds of pixels — the same class of bug as signing in, only
          // on the way out.
          await windowManager.setSize(
              const Size(kSignInWidth, kSignInHeight));
          await windowManager.center();
        }
      },
      itemBuilder: (_) => [
        for (final s in WidgetSize.values)
          PopupMenuItem<Object>(
            value: s,
            height: 30,
            child: Row(children: [
              SizedBox(
                width: 16,
                child: c.size.value == s
                    ? const Icon(Icons.check, size: 12, color: cGreen700)
                    : null,
              ),
              Text(s.label, style: t(11.5, FontWeight.w500)),
            ]),
          ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<Object>(
          value: 'help',
          height: 30,
          // TODO(dev): restarts the ten-step first-run tour.
          child: Text('Help', style: t(11.5, FontWeight.w500)),
        ),
        PopupMenuItem<Object>(
          value: 'signout',
          height: 30,
          child: Text('Sign out', style: t(11.5, FontWeight.w500)),
        ),
      ],
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(left: 1),
        child: const Icon(Icons.more_horiz, size: 13, color: cInk500),
      ),
    );
  }
}
