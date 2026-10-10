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
  final start = loggedIn ? const Size(kWidgetWidth, 40) : const Size(260, 271);

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
      await WindowAnchor.instance.setSizeKeepingBottom(kWidgetWidth, 40);
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
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: loggedIn ? const WidgetShell() : const SignInScreen(),
      ),
    );
  }
}
