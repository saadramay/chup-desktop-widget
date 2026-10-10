import 'package:chup_widget/core/queue_controller.dart';
import 'package:chup_widget/core/window_anchor.dart';
import 'package:chup_widget/main.dart';
import 'package:chup_widget/ui/shell.dart';
import 'package:chup_widget/ui/sign_in.dart';
import 'package:chup_widget/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'panel_harness.dart';

// Every other test in this suite pumps the panel inside a `Scaffold`, which
// builds a `Material` — so every other test would have passed with the bug
// that shipped. This file performs the navigation the app really performs:
// sign in, then `Get.offAll(() => const WidgetShell())`.
//
// That call pushes a *new route* whose root is the bare shell: no Scaffold, no
// Material. Signing out does the same in reverse. The size menu is a
// `PopupMenuButton` with a custom child, which Flutter builds as
// `Tooltip → InkWell → child`, and `InkWell` asserts `debugCheckHasMaterial` —
// so on the panel, immediately after every sign-in, the assert threw and the
// whole widget was replaced by Flutter's red error box. The unbounded error
// text then overflowed a Row by ~99,000px, which is the second symptom in the
// log, not a second bug.
//
// It only bites with the reveal open, because _SizeMenu lives inside _Reveal
// and the reveal is not in the tree at rest — which is why the panel looked
// fine until the cursor moved over it.
void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  tearDown(Get.reset);

  /// The controller with a patient in the room and one called — the state that
  /// puts the size menu, and so an InkWell, in the tree.
  ///
  /// Registered BEFORE the first pump: WidgetShell Get.finds it in its own
  /// build, so a controller that arrives afterwards is a different bug.
  PanelHost host({WidgetSize size = WidgetSize.small}) {
    final c = PanelHost();
    Get.put<QueueController>(c);
    c.size.value = size;
    c.state.value = PanelState.serving;
    c.now.value = DateTime(2026, 8, 1, 15, 45);
    c.serving.value = visit(
      name: 'Ahmad Abu Ibrahim',
      state: 'SERVING',
      startedAt: DateTime(2026, 8, 1, 15, 30),
    );
    c.called.value = visit(
      name: 'Kawthar Falah Qandeel',
      calledAt: DateTime(2026, 8, 1, 15, 31),
    );
    c.revealed.value = true;
    return c;
  }

  testWidgets('signing in leaves the panel building clean', (tester) async {
    requireSegoe(segouiLoaded);

    // The window the app actually has before sign-in: the centred card.
    tester.view.physicalSize =
        const Size(kSignInWidth, kSignInHeight);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ChupWidgetApp(loggedIn: false));
    await tester.pumpAndSettle();

    // Register the controller, then navigate exactly as sign_in.dart does
    // after a successful login. This is the step that pushes the second route.
    host();

    Get.offAll(() => const WidgetShell());
    await tester.pump();

    // The window deliberately stays the card's size here. The panel only ever
    // gets *more* room than it asks for, and the exact geometry is already
    // measured by reveal_height_test — what is under test is the Material
    // assert, which fires on build regardless of the box it lands in.
    //
    // Resizing the test window down to 216 x 158 instead would lay the
    // sign-in card out in the smaller box for one frame (the route above is
    // still on screen while the new one animates in) and report a 164px
    // overflow that has nothing to do with any of this.

    expect(tester.takeException(), isNull,
        reason: 'signing in pushes the panel as a NEW route via Get.offAll, '
            'so no Scaffold built for home: can cover it. The only Material '
            'ancestor it ever has is the one ChupWidgetApp puts above the '
            'Navigator.');
  });

  testWidgets('signing out leaves the sign-in card building clean',
      (tester) async {
    requireSegoe(segouiLoaded);

    tester.view.physicalSize = Size(
      kWidgetWidth,
      WidgetSize.small.height + kRevealHeight,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Start signed in, which is the only way to reach sign-out.
    host();
    await tester.pumpWidget(const ChupWidgetApp(loggedIn: true));
    await tester.pump();

    // The card needs the bigger window, exactly as sliver_panel.dart resizes
    // to on the way out.
    tester.view.physicalSize =
        const Size(kSignInWidth, kSignInHeight);
    await tester.pump();

    Get.offAll(() => const SignInScreen());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'signing out pushes the sign-in card as a NEW route, and its '
            'TextFields require a Material ancestor.');
  });

  testWidgets('the size menu really is an InkWell, so these tests can fail',
      (tester) async {
    requireSegoe(segouiLoaded);

    tester.view.physicalSize = Size(
      kWidgetWidth,
      WidgetSize.small.height + kRevealHeight,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    host();
    await tester.pumpWidget(const ChupWidgetApp(loggedIn: true));
    await tester.pump();

    // If this ever stops being true the tests above could pass while the panel
    // is still broken, because nothing else in the app needs Material.
    expect(find.byType(InkWell), findsWidgets,
        reason: 'the size menu is the only widget in the app that requires a '
            'Material ancestor. If that changes, this suite needs a new thing '
            'to assert on.');
  });
}
