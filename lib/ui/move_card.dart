import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/move.dart';
import '../core/queue_controller.dart';
import '../core/window_anchor.dart';
import 'tokens.dart';

/// Move the patient to another service and staff, as the web app's serving
/// page does. Opens beside the panel, like the tour card.
class MoveCard extends StatefulWidget {
  const MoveCard({super.key});

  @override
  State<MoveCard> createState() => _MoveCardState();
}

class _MoveCardState extends State<MoveCard> {
  final _search = TextEditingController();
  MoveService? _service;

  /// The chosen staff, or null for "Any available".
  MoveStaff? _staff;
  bool _staffChosen = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pickService(MoveService s) => setState(() {
    _service = s;
    _staff = null;
    // A single person, or a service that assigns whoever is free, needs no
    // second choice; it can still be changed before confirming.
    if (s.staff.length == 1 && !s.anyAvailable) {
      _staff = s.staff.first;
      _staffChosen = true;
    } else {
      _staffChosen = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = Get.find<QueueController>();
    return Obx(() {
      final v = c.moving.value;
      if (v == null) return const SizedBox.shrink();
      return Container(
        width: kMoveCardWidth,
        height: kMoveCardHeight,
        decoration: BoxDecoration(
          color: cWhite,
          border: Border.all(color: cLine200),
          borderRadius: BorderRadius.circular(kPanelRadius),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (_service != null)
                  _IconBtn(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => setState(() {
                      _service = null;
                      _staffChosen = false;
                    }),
                  ),
                Expanded(
                  child: Text(
                    _service == null ? 'Move ${v.shortName}' : _service!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t(13, FontWeight.w600),
                  ),
                ),
                _IconBtn(
                  icon: Icons.close_rounded,
                  tooltip: 'Cancel',
                  onTap: c.cancelMove,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 4),
              child: Text(
                _service == null
                    ? 'Choose the next service'
                    : 'Choose who sees ${v.shortName}',
                style: t(11, FontWeight.w400, color: cInk500),
              ),
            ),
            Expanded(child: _body(c)),
            if (c.moveError.value != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Text(
                  c.moveError.value!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t(11, FontWeight.w600, color: cRed),
                ),
              ),
            if (_service != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _ConfirmButton(
                  label: !_staffChosen
                      ? 'Choose staff'
                      : 'Move to ${_staff?.name ?? _service!.name}',
                  busy: c.moveBusy.value,
                  enabled: _staffChosen && !c.moveBusy.value,
                  onTap: () => c.confirmMove(_service!, _staff),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _body(QueueController c) {
    if (c.moveLoading.value) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: cGreen700),
        ),
      );
    }
    final s = _service;
    if (s == null) {
      final q = _search.text.trim().toLowerCase();
      final list = c.moveServices
          .where((x) => q.isEmpty || x.name.toLowerCase().contains(q))
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.moveServices.length > 6)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 4),
              child: SizedBox(
                height: 30,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: t(12, FontWeight.w400),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: cSurface2,
                    hintText: 'Search services',
                    hintStyle: t(12, FontWeight.w400, color: cInk400),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: cInk500,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 30),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kControlRadius),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(right: 4),
              children: [
                for (final x in list)
                  _Row(
                    title: x.name,
                    trailing: '${x.staff.length}',
                    onTap: () => _pickService(x),
                    chevron: true,
                  ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(right: 4),
      children: [
        if (s.anyAvailable)
          _Row(
            title: 'Any available',
            subtitle: 'Chup assigns whoever is free',
            selected: _staffChosen && _staff == null,
            onTap: () => setState(() {
              _staff = null;
              _staffChosen = true;
            }),
          ),
        for (final u in s.staff)
          _Row(
            title: u.name,
            selected: _staffChosen && _staff?.id == u.id,
            onTap: () => setState(() {
              _staff = u;
              _staffChosen = true;
            }),
          ),
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.chevron = false,
  });
  final String title;
  final String? subtitle;
  final String? trailing;
  final bool selected;
  final bool chevron;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit: (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: widget.selected ? cGreen50 : (_h ? cSurface2 : null),
          borderRadius: BorderRadius.circular(6),
          border: widget.selected ? Border.all(color: cGreen700) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t(
                      12,
                      widget.selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (widget.subtitle != null)
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(10.5, FontWeight.w400, color: cInk500),
                    ),
                ],
              ),
            ),
            if (widget.trailing != null)
              Text(
                widget.trailing!,
                style: t(10.5, FontWeight.w500, color: cInk400),
              ),
            if (widget.chevron)
              const Icon(Icons.chevron_right_rounded, size: 16, color: cInk400),
            if (widget.selected)
              const Icon(Icons.check_rounded, size: 16, color: cGreen700),
          ],
        ),
      ),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: cInk500),
        ),
      ),
    ),
  );
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.onTap,
    required this.enabled,
    required this.busy,
  });
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: enabled || busy ? cGreen700 : cSurface2,
          borderRadius: BorderRadius.circular(kControlRadius),
        ),
        child: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: cWhite),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: enabled ? cWhite : cInk400,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t(
                        12.5,
                        FontWeight.w600,
                        color: enabled ? cWhite : cInk400,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
