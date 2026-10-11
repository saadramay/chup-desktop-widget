import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/window_anchor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

// The size menu must not collapse the reveal it is anchored to.
//
// `PopupMenuButton` pushes a route, and that route lands a full-screen barrier
// over the panel. The pointer has not moved, but the render tree has — so
// `MouseTracker` re-hit-tests and the panel's `MouseRegion` reports an exit
// while the menu is still open. Take that exit at face value and the window
// goes 158 → 40 with the menu open, which is where the live app ended up: 167px
// of menu items drawn into a 40px window, roughly one row of it, and hover dead
// until the menu is dismissed.
//
// The pin is one line of `setRevealed`, so it is the controller contract that
// is tested here rather than the route — a widget test has no MouseTracker
// exit to fire unless a pointer actually moves, and the pointer does not move
// when you click the button.

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
  });

  tearDown(Get.reset);

  test('the reveal stays open while the size menu is up', () async {
    final c = PanelHost();
    Get.put<QueueController>(c);

    // The reveal is up because the pointer is on the panel.
    await c.setRevealed(true);
    expect(c.revealed.value, isTrue);

    // The menu's barrier makes the MouseRegion report an exit.
    c.menuOpen.value = true;
    await c.setRevealed(false);

    expect(c.revealed.value, isTrue,
        reason: 'collapsing here takes 118px of window, and the button the '
            'menu is anchored to, out from under a menu whose items are '
            '167px tall — the menu then draws into the 40px band instead.');

    // Once the menu is down, ordinary hover behaviour has to resume or the
    // reveal would stay open forever after the first use of the menu.
    c.menuOpen.value = false;
    await c.setRevealed(false);

    expect(c.revealed.value, isFalse,
        reason: 'the pin has to be temporary: the reveal closes when the '
            'pointer leaves, menu or no menu.');

    // Opening the reveal again still works — the pin never latched it shut.
    await c.setRevealed(true);
    expect(c.revealed.value, isTrue);
  });

  test('the window grows for the size menu and shrinks back', () async {
    final c = PanelHost();
    Get.put<QueueController>(c);

    c.size.value = WidgetSize.small;
    await c.setRevealed(true);
    expect(c.windowHeight, 40 + kRevealHeight);

    c.menuOpen.value = true;
    expect(c.windowHeight, kSizeMenuWindowHeight,
        reason: 'the small reveal is only 158px and the menu needs ~188 from '
            'the top of the window; without this its last row — Sign out — '
            'draws off the bottom as an unreadable sliver.');

    c.menuOpen.value = false;
    expect(c.windowHeight, 40 + kRevealHeight,
        reason: 'the extra room belongs to the menu alone.');

    // Medium and large already outgrow the floor, so it must not force them
    // any taller than the reveal they are already showing.
    c.size.value = WidgetSize.large;
    c.menuOpen.value = true;
    expect(c.windowHeight, 208 + kRevealHeight);
  });
}
