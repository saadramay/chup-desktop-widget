// Runs the real app in a real Windows window (CI: windows-latest), with
// fixtures so nothing touches a server:
//
//   flutter test integration_test -d windows --dart-define=MOCK=true
//
// Covers the two checks a widget test cannot: the OS window's actual size
// after boot, and the size menu inside it.

import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/window_anchor.dart';
import 'package:chup_widget/main.dart' as app;
import 'package:chup_widget/ui/sliver_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:integration_test/integration_test.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots at a stored Large size, then the menu fits at Small',
      (tester) async {
    await GetStorage.init();
    final box = GetStorage();
    await box.write('size', 'large');
    await box.write('first_run_completed', true);

    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 1. Restart at Large: the window fits the Large panel's rows (the panel
    //    sizes to its content, capped at 208) and the panel draws.
    final c = Get.find<QueueController>();
    expect(c.size.value, WidgetSize.large);
    final boot = await windowManager.getBounds();
    expect(boot.width, kWidgetWidth);
    expect(boot.height, c.restingHeight);
    expect(c.restingHeight, greaterThan(WidgetSize.small.height),
        reason: 'the fixtures put people in the Large list');
    expect(c.restingHeight, lessThanOrEqualTo(WidgetSize.large.height));
    expect(find.byType(SliverPanel), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 2. Menu at Small: every item is visible inside the window.
    await c.setSize(WidgetSize.small);
    await c.setRevealed(true);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final menu = await windowManager.getBounds();
    expect(menu.height, kSizeMenuWindowHeight);
    for (final item in ['Small', 'Medium', 'Large', 'Help', 'Sign out', 'Quit']) {
      final f = find.text(item);
      expect(f, findsOneWidget, reason: item);
      final r = tester.getRect(f);
      expect(r.bottom, lessThanOrEqualTo(kSizeMenuWindowHeight),
          reason: '$item is drawn below the window');
    }
    expect(c.revealed.value, isTrue,
        reason: 'the reveal must stay open under the menu');
    expect(tester.takeException(), isNull);

    // 3. Picking Large, then Medium, from the menu: the widget must stay on
    //    screen, visible and drawn (reported: "when I changed to large, it
    //    disappeared").
    for (final target in [WidgetSize.large, WidgetSize.medium]) {
      if (find.text(target.label).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
      }
      await tester.tap(find.text(target.label).last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await c.setRevealed(false);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final b = await windowManager.getBounds();
      final display = await screenRetriever.getPrimaryDisplay();
      final area = Offset.zero & (display.visibleSize ?? display.size);
      expect(c.size.value, target);
      expect(await windowManager.isVisible(), isTrue, reason: '${target.label}: window hidden');
      expect(await windowManager.isMinimized(), isFalse, reason: '${target.label}: minimised');
      expect(area.contains(b.topLeft) && area.contains(b.bottomRight - const Offset(1, 1)), isTrue,
          reason: '${target.label}: window $b is off the work area $area');
      expect(b.height, c.restingHeight, reason: '${target.label}: window $b vs panel ${c.restingHeight}');
      expect(find.byType(SliverPanel), findsOneWidget, reason: '${target.label}: panel not drawn');
      expect(tester.takeException(), isNull);

      // Reopen the reveal for the next menu.
      await c.setRevealed(true);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
    }

    await box.erase();
  });
}
