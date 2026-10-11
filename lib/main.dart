import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:window_manager/window_manager.dart';

import 'core/api.dart';
import 'core/mock.dart';
import 'core/queue_controller.dart';
import 'core/window_anchor.dart';
import 'ui/shell.dart';
import 'ui/sign_in.dart';
import 'ui/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  await windowManager.ensureInitialized();

  // Fixtures skip the sign-in card so the panel is reachable with no backend.
  final loggedIn = kMock || Api.instance.isLoggedIn;
  // Sign in is centred; the widget lives in its corner.
  //
  // The panel's height is whatever size the menu left it at — it is stored, and
  // starting the window at a fixed 40 instead was the bug behind a widget that
  // came up blank and dead. A stored size of large is a 208px panel, which
  // nothing can draw into a 40px window.
  final panelHeight =
      loggedIn ? QueueController.storedSize().height : kSignInHeight;
  final start = loggedIn
      ? Size(kWidgetWidth, panelHeight)
      : const Size(kSignInWidth, kSignInHeight);

  final options = WindowOptions(
    size: start,
    minimumSize: const Size(5, 34), // the closed tab is the smallest state
    center: !loggedIn,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    // Frameless, and first — both halves matter.
    //
    // window_manager's TitleBarStyle.hidden branch of WM_NCCALCSIZE shrinks the
    // client area by 8px on the left, right and bottom (commented "required for
    // resizing the window", window_manager issue #483), so setBounds(216, 40)
    // yielded a 200x32 view: the resting band then overflowed by 10px and the
    // widget sat inside an 8px dead zone that still swallowed the cursor. The
    // is_frameless_ branch instead leaves the rect alone, giving client ==
    // window rect — which is the 216x40 the design means by "overlay window".
    //
    // It must also come after waitUntilReadyToShow: SetTitleBarStyle sets
    // is_frameless_ = false, so calling this any earlier would be undone. That
    // ordering is what finally makes setHasShadow(false) below do anything —
    // SetHasShadow is gated on is_frameless_ too.
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    if (loggedIn) {
      await WindowAnchor.instance
          .setSizeKeepingBottom(kWidgetWidth, panelHeight);
    }
    await windowManager.show();
  });

  // Registered here, deliberately NOT inside the callback above.
  //
  // window_manager types that callback as `VoidCallback?` and invokes it as a
  // bare `callback();` — the result is discarded. An async closure therefore
  // runs only as far as its first await (`setAlwaysOnTop`) and then hands back
  // a Future nobody waits on, so `waitUntilReadyToShow` returns and `runApp`
  // builds WidgetShell — which Get.finds this controller — before `Get.put`
  // is ever reached. That threw "QueueController not found" on every launch
  // with a stored token, and nothing marked the shell dirty again once the
  // controller did arrive, so the window stayed on the error widget.
  if (loggedIn) Get.put(QueueController());

  runApp(ChupWidgetApp(loggedIn: loggedIn));
}

class ChupWidgetApp extends StatelessWidget {
  const ChupWidgetApp({super.key, required this.loggedIn});

  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Chup',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: kFont,
        fontFamilyFallback: kFontFallback,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(seedColor: cGreen700),
        tooltipTheme: const TooltipThemeData(preferBelow: false),
      ),
      // A Material for every route, not just the first one.
      //
      // Scaffold builds a Material too, but Scaffold only wraps the route it
      // is built in — `home:` covers the initial screen and nothing else.
      // Signing in does `Get.offAll(() => const WidgetShell())` (sign_in.dart),
      // which pushes a *new* route holding the bare shell with no Scaffold
      // above it; signing out does the same in reverse to SignInScreen, whose
      // TextFields assert the same invariant. The size menu is a
      // PopupMenuButton with a custom child, which Flutter builds as an
      // InkWell, and InkWell asserts `debugCheckHasMaterial` — so on the
      // panel, immediately after every sign-in, the assert threw and the whole
      // widget was replaced by Flutter's red error box.
      //
      // Transparent because the panel and the sign-in card both paint their
      // own white: this is only ever the surface ink lands on.
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: child ?? const SizedBox.shrink(),
      ),
      home: loggedIn ? const WidgetShell() : const SignInScreen(),
    );
  }
}
