import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:window_manager/window_manager.dart';

import '../core/api.dart';
import '../core/queue_controller.dart';
import '../core/startup.dart';
import '../core/window_anchor.dart';
import 'shell.dart';
import 'tokens.dart';

/// kSignInWidth x kSignInHeight, centred. Shown once per install.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.notice});

  /// Why the card is showing, e.g. an expired session. Shown until submit.
  final String? notice;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _box = GetStorage();

  bool _busy = false;

  /// Sign-in content opacity during the morph to the corner.
  double _content = 1;
  bool _obscure = true;
  bool _stay = true; // default ON
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.notice;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // "Stay signed in" decides whether the token survives the session. It has
      // to be set before login(), which is what stores the token.
      Api.instance.persistToken = _stay;
      await Api.instance.login(_email.text.trim(), _password.text);
      await _box.write('stay_signed_in', _stay);
      unawaited(registerStartup());
      if (!mounted) return;
      await _morphToCorner();
      if (!mounted) return;
      Get.put(QueueController());
      Get.offAll(() => const WidgetShell());
    } on ApiException catch (e) {
      // The server's own message when it sent one; the API reports a bad
      // password as HTTP 200 with error:true.
      final generic = e.message.isEmpty || e.message == 'Request failed';
      setState(() => _error = generic &&
              (e.statusCode == 401 || e.statusCode == 200)
          ? 'Wrong email or password'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach Chup');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The card becomes the widget: 1150ms on the spec's curve, travelling to
  /// the corner at the panel's stored size, content gone by 28%.
  Future<void> _morphToCorner() async {
    try {
      final from = await windowManager.getBounds();
      final to = await WindowAnchor.instance
          .boundsFor(kWidgetWidth, QueueController.storedSize().height);
      const curve = Cubic(0.45, 0.05, 0.2, 1);
      const total = Duration(milliseconds: 1150);
      final clock = Stopwatch()..start();
      while (clock.elapsed < total && mounted) {
        final lin = clock.elapsedMilliseconds / total.inMilliseconds;
        final e = curve.transform(lin.clamp(0.0, 1.0));
        setState(() => _content = (1 - lin / 0.28).clamp(0.0, 1.0));
        await windowManager.setBounds(Rect.lerp(from, to, e)!);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      await windowManager.setBounds(to);
    } on MissingPluginException {
      // No OS window under `flutter test`.
    }
  }

  @override
  Widget build(BuildContext context) {
    // While the window shrinks the card keeps its own size and is clipped,
    // so the morph never reports an overflow.
    // The white box is the window and shrinks with it; only the content is
    // fixed-size, faded and clipped.
    return Container(
      decoration: BoxDecoration(
        color: cWhite,
        border: Border.all(color: cLine200),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 0,
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: SizedBox(
          width: kSignInWidth - 2,
          height: kSignInHeight - 2,
          child: Opacity(opacity: _content, child: _card()),
        ),
      ),
    );
  }

  Widget _card() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => windowManager.startDragging(),
                  child: const SizedBox(height: 19),
                ),
              ),
              _WinCtl(
                  icon: Icons.remove, onTap: () => windowManager.minimize()),
              const SizedBox(width: 1),
              _WinCtl(
                  icon: Icons.close,
                  danger: true,
                  onTap: () => windowManager.destroy()),
            ],
          ),
          SvgPicture.asset('assets/chup-logo.svg', width: 74),
          const SizedBox(height: 9),
          Text('Chup Desktop Widget', style: t(13, FontWeight.w800)),
          Text('Sign in to follow your queue',
              style: t(10.5, FontWeight.w500, color: cInk500)),
          const SizedBox(height: 9),
          const _Label('EMAIL'),
          _Input(controller: _email, autofocus: true),
          const SizedBox(height: 9),
          Row(
            children: [
              const _Label('PASSWORD'),
              const Spacer(),
              _ShowHide(
                shown: !_obscure,
                onTap: () => setState(() => _obscure = !_obscure),
              ),
            ],
          ),
          _Input(
            controller: _password,
            obscure: _obscure,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 9),
          _StayTicked(
            value: _stay,
            onChanged: (v) => setState(() => _stay = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: t(10, FontWeight.w700, color: cRed)),
          ],
          const SizedBox(height: 9),
          _Primary(busy: _busy, onTap: _submit),
          const SizedBox(height: 6),
          // States the consequence of the tick, not of the button.
          Text(
            _stay
                ? 'Opens straight to your queue when this computer starts'
                : 'Opens when this computer starts, and asks for your password',
            textAlign: TextAlign.center,
            style: t(8.5, FontWeight.w500, color: cInk500, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(text,
            style: t(8.5, FontWeight.w800, color: cInk500, spacing: 0.68)),
      );
}

class _Input extends StatelessWidget {
  const _Input({
    required this.controller,
    this.obscure = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 30,
        child: TextField(
          controller: controller,
          obscureText: obscure,
          autofocus: autofocus,
          onSubmitted: onSubmitted,
          style: t(11.5, FontWeight.w500),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 9),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: cLine200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: cGreen700),
            ),
          ),
        ),
      );
}

class _ShowHide extends StatefulWidget {
  const _ShowHide({required this.shown, required this.onTap});
  final bool shown;
  final VoidCallback onTap;

  @override
  State<_ShowHide> createState() => _ShowHideState();
}

class _ShowHideState extends State<_ShowHide> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(widget.shown ? 'HIDE' : 'SHOW',
                style: t(8.5, FontWeight.w800,
                    color: _h ? cOrange : cGreen700, spacing: 0.68)),
          ),
        ),
      );
}

class _StayTicked extends StatelessWidget {
  const _StayTicked({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!value),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: value ? cGreen700 : null,
                  border: Border.all(color: value ? cGreen700 : cLine300),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: value
                    ? const Icon(Icons.check, size: 10, color: cWhite)
                    : null,
              ),
              const SizedBox(width: 6),
              Text('Stay signed in on this computer',
                  style: t(10, FontWeight.w500)),
            ],
          ),
        ),
      );
}

class _Primary extends StatefulWidget {
  const _Primary({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_Primary> createState() => _PrimaryState();
}

class _PrimaryState extends State<_Primary> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.busy ? null : widget.onTap,
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _h ? cGreen700Hover : cGreen700,
              borderRadius: BorderRadius.circular(6),
            ),
            child: widget.busy
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cWhite),
                  )
                : Text('SIGN IN',
                    style:
                        t(12, FontWeight.w800, color: cWhite, spacing: 0.6)),
          ),
        ),
      );
}

class _WinCtl extends StatefulWidget {
  const _WinCtl({required this.icon, required this.onTap, this.danger = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WinCtl> createState() => _WinCtlState();
}

class _WinCtlState extends State<_WinCtl> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: _h ? (widget.danger ? cRedWash : cGreen50) : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(widget.icon,
                size: 12,
                color: _h ? (widget.danger ? cRed : cGreen700) : cInk500),
          ),
        ),
      );
}
