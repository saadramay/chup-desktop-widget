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
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setResizable(false);
    await windowManager.setHasShadow(false);
    if (loggedIn) {
      Get.put(QueueController());
      await WindowAnchor.instance.setSizeKeepingBottom(kWidgetWidth, 40);
    }
    await windowManager.show();
  });

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
