import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:window_manager/window_manager.dart';

import '../core/api.dart';
import '../core/queue_controller.dart';
import 'shell.dart';
import 'tokens.dart';

/// 260 x 271, centred. Shown once per install.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _box = GetStorage();

  bool _busy = false;
  bool _obscure = true;
  bool _stay = true; // default ON
  String? _error;

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
      await Api.instance.login(_email.text.trim(), _password.text);
      // "Stay signed in" is what decides whether the token survives the session,
      // which is a different promise from remembering an email.
      if (!_stay) Api.instance.persistToken = false;
      await _box.write('stay_signed_in', _stay);
      if (!mounted) return;
      Get.put(QueueController());
      Get.offAll(() => const WidgetShell());
    } on ApiException catch (e) {
      setState(() => _error = e.statusCode == 401 || e.statusCode == 200
          ? 'Wrong email or password'
          : e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach Chup');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cWhite,
        border: Border.all(color: cLine200),
        borderRadius: BorderRadius.circular(8),
      ),
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
