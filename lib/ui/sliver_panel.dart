import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../core/links.dart';
import '../core/updater.dart';
import '../core/limits.dart';
import '../core/queue_controller.dart';
import '../core/visit.dart';
import '../core/window_anchor.dart';
import 'action_button.dart';
import 'tokens.dart';
import 'tour_card.dart';
import '../core/tour.dart';

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
            TourRing(region: TourRegion.list, child: _QueueRows()),
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
                  text: 'No one in the queue',
                  color: cInk500,
                  icon: Icons.check_circle_outline_rounded,
                ),
                PanelState.loading => const _StatusLine(
                  text: 'Reading the queue…',
                  color: cInk500,
                  icon: Icons.sync_rounded,
                ),
                PanelState.offline => _StatusLine(
                  text: "Can't reach Chup",
                  color: cRed,
                  icon: Icons.cloud_off_rounded,
                  trailing: c.lastGoodPoll.value == null
                      ? null
                      : '${c.minutesSinceLastPoll}m ago',
                ),
              },
            ),
            const TourRing(region: TourRegion.meter, child: _LeadMeter()),
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
      // The next patient, or with nobody waiting the patient in the room, so
      // END VISIT never disappears while someone is being served.
      final inRoom = c.onlyServing;
      final n = c.next ?? c.serving.value;
      if (n == null) {
        return const _StatusLine(
          text: 'No one in the queue',
          color: cInk500,
          icon: Icons.check_circle_outline_rounded,
        );
      }
      final called = n.isCalled;
      final over = c.leadOverLimit;
      final mins = c.leadMinutes;

      return Row(
        children: [
          Expanded(
            child: TourRing(
              region: TourRegion.next,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                // A failed action takes the whole line for a few seconds, so
                // the reason is readable and never passes for success.
                child: c.actionError.value != null
                    ? _ActionError(c.actionError.value!)
                    : Column(
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
                                  style: t(13, FontWeight.w600, height: 1.15),
                                ),
                              ),
                              const SizedBox(width: 4),
                              _Pill(
                                '${c.positionOf(n)}/${c.sessionTotal}',
                                color: cInk500,
                                background: cSurface2,
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                _clockShort(n.appointmentAt),
                                style: t(
                                  11,
                                  FontWeight.w500,
                                  color: cInk500,
                                  tabular: true,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Spacer(),
                              Text(
                                inRoom
                                    ? 'Serving ${mins}m'
                                    : called
                                    ? 'Called ${mins}m'
                                    : 'Waiting ${mins}m',
                                style: t(
                                  11,
                                  FontWeight.w600,
                                  color: over ? cRed : cInk500,
                                  tabular: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TourRing(
            region: TourRegion.act,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
              child: ActionButton(
                action: c.displayAction,
                onFire: () => c.act(c.action),
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// "2.30", the row's short form of [_clock].
String _clockShort(DateTime? d) =>
    _clock(d).replaceAll(RegExp(r'\s*(AM|PM)$'), '');

String _clock(DateTime? d) {
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.text,
    required this.color,
    this.trailing,
    this.icon,
  });
  final String text;
  final Color color;
  final String? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
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
        if (icon != null) ...[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t(12, FontWeight.w600, color: color),
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
                style: t(11, FontWeight.w500, color: cInk500),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The reason the last action failed, on up to two lines; full text on hover.
class _ActionError extends StatelessWidget {
  const _ActionError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, size: 15, color: cRed),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t(11, FontWeight.w600, color: cRed, height: 1.2),
          ),
        ),
      ],
    ),
  );
}

/// A small rounded label: positions, tokens.
class _Pill extends StatelessWidget {
  const _Pill(
    this.text, {
    required this.color,
    required this.background,
    this.size = 10,
  });
  final String text;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: t(size, FontWeight.w600, color: color, tabular: true, height: 1.2),
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
      return Container(
        height: 3,
        color: cSurface2,
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Spec order: appointment time, token, full name, minutes waiting
              // (red past the wait limit).
              child: Row(
                children: [
                  if (v.appointmentAt != null) ...[
                    Text(
                      _clockShort(v.appointmentAt),
                      style: t(
                        10.5,
                        FontWeight.w500,
                        color: cInk500,
                        tabular: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _Pill(v.token, color: cGreen700, background: cGreen50),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      v.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(11.5, FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Builder(
                    builder: (_) {
                      final m = minutesSince(v.arrivedAt, c.now.value);
                      return Text(
                        '${m}m',
                        style: t(
                          10.5,
                          FontWeight.w600,
                          color: m >= c.limits.value.wait.inMinutes
                              ? cRed
                              : cInk500,
                          tabular: true,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          // Mark the true end of the list rather than leaving empty paper.
          // Same rule as QueueController.listRowCount, which sizes the window.
          if (rows.length < c.listRowCount)
            Container(
              height: h,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: cLine200)),
              ),
              child: Text(
                'End of list',
                style: t(10.5, FontWeight.w500, color: cInk400),
              ),
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(kPanelRadius - 1),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (s != null) ...[
                  // A live dot: someone is in the room right now.
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: cGreen600,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  s == null ? 'Chup' : 'Now',
                  style: t(11.5, FontWeight.w600, color: cGreen700),
                ),
                const Spacer(),
                const TourRing(
                  region: TourRegion.controls,
                  child: _ControlCluster(),
                ),
              ],
            ),
            const SizedBox(height: 2),
            if (s != null)
              TourRing(
                region: TourRegion.now,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Full name — only the resting line shortens. One line, though:
                    // the reveal's height is fixed, so a name that wrapped to two
                    // lines would push the NO-SHOW button off the bottom of the
                    // panel (measured: 42px past it for a three-line name).
                    Text(
                      s.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(
                        17,
                        FontWeight.w600,
                        height: 1.15,
                        spacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _Pill(
                          s.token,
                          color: cGreen700,
                          background: cGreen50,
                          size: 11.5,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${c.positionOf(s)}/${c.sessionTotal}',
                          style: t(
                            11.5,
                            FontWeight.w500,
                            color: cInk500,
                            tabular: true,
                          ),
                        ),
                        Text(
                          '  ·  Serving ${c.servingMinutes}m',
                          style: t(
                            11.5,
                            FontWeight.w600,
                            color: c.servingOverLimit ? cRed : cInk500,
                            tabular: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _ServingMeter(),
                  ],
                ),
              )
            else
              Text(
                'No consultation in progress',
                style: t(12, FontWeight.w500, color: cInk500),
              ),
            // Shown while someone is called, and on the tour's No-Show step,
            // where act() refuses to fire.
            if (called != null || c.tour?.highlight == TourRegion.noShow) ...[
              const SizedBox(height: 6),
              TourRing(
                region: TourRegion.noShow,
                child: ActionButton(
                  action: VisitAction.noShow,
                  width: double.infinity,
                  height: 26,
                  holdLabel: called == null
                      ? 'Hold for no-show'
                      : 'Hold for no-show · ${called.shortName}',
                  onFire: () => c.act(VisitAction.noShow),
                ),
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
      final f = consult == 0
          ? 0.0
          : (c.servingMinutes / consult).clamp(0.0, 1.0);
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Container(
          height: 4,
          color: cSurface2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: f,
              child: ColoredBox(color: c.servingOverLimit ? cRed : cGreen600),
            ),
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
          icon: Icons.drag_indicator_rounded,
          tooltip: 'Move',
          cursor: SystemMouseCursors.grab,
          onDragStart: () async {
            await windowManager.startDragging();
            await WindowAnchor.instance.rememberCurrentPosition();
          },
        ),
        _Ctl(
          icon: Icons.open_in_new_rounded,
          tooltip: 'Open in Chup',
          onTap: () => openInBrowser(webQueueUrl),
        ),
        _SizeMenu(),
        _Ctl(
          icon: Icons.remove_rounded,
          tooltip: 'Minimise',
          onTap: () => c.presentation.value = Presentation.minimised,
        ),
        _Ctl(
          icon: Icons.close_rounded,
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
    final fg = _h ? (widget.danger ? cRed : cInk800) : cInk500;
    final bg = _h ? (widget.danger ? cRedWash : cSurface2) : null;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onPanStart: widget.onDragStart == null
              ? null
              : (_) => widget.onDragStart!(),
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(left: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 15, color: fg),
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
      constraints: const BoxConstraints(minWidth: 140),
      color: cWhite,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: cLine200),
      ),
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
        } else if (v == 'update') {
          if (c.updateVersion.value != null) {
            await c.installUpdate();
          } else {
            await c.checkForUpdates();
          }
        } else if (v == 'help') {
          await c.startTour();
        } else if (v == 'signout') {
          // Resizes and centres the window for the card, and stops this
          // controller so the next sign-in does not run two.
          await c.endSession();
        } else if (v == 'quit') {
          await windowManager.destroy();
        }
      },
      itemBuilder: (_) => [
        for (final s in WidgetSize.values)
          PopupMenuItem<Object>(
            value: s,
            height: 30,
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  child: c.size.value == s
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: cGreen700,
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Text(s.label, style: t(12, FontWeight.w400)),
              ],
            ),
          ),
        const PopupMenuDivider(height: 1),
        // The version, or the way to the next one.
        PopupMenuItem<Object>(
          value: 'update',
          height: 30,
          child: c.updateVersion.value != null
              ? Row(
                  children: [
                    const Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: cGreen700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Update to ${c.updateVersion.value}',
                      style: t(12, FontWeight.w600, color: cGreen700),
                    ),
                  ],
                )
              : Text(
                  kAppVersion == '0.0.0'
                      ? 'Development build'
                      : 'Version $kAppVersion',
                  style: t(12, FontWeight.w400, color: cInk500),
                ),
        ),
        PopupMenuItem<Object>(
          value: 'help',
          height: 30,
          child: Text('Help', style: t(12, FontWeight.w400)),
        ),
        PopupMenuItem<Object>(
          value: 'signout',
          height: 30,
          child: Text('Sign out', style: t(12, FontWeight.w400)),
        ),
        // Close only tucks the widget into an edge tab; this is the way out.
        PopupMenuItem<Object>(
          value: 'quit',
          height: 30,
          child: Text('Quit', style: t(12, FontWeight.w400, color: cRed)),
        ),
      ],
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.only(left: 1),
        // A green dot on ⋯ says an update is waiting inside.
        child: Obx(
          () => Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.more_horiz_rounded, size: 15, color: cInk500),
              if (c.updateVersion.value != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: cGreen600,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
