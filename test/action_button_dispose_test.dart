import 'package:chup_widget/core/visit.dart';
import 'package:chup_widget/ui/action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A `late final` AnimationController declared at its field is only realised
/// the first time it is *read* — and `dispose()` reads it. A button that is
/// never held therefore builds its controllers *during* dispose, which calls
/// `TickerProviderStateMixin.createTicker` on an already-deactivated element
/// and throws "Looking up a deactivated widget's ancestor is unsafe."
///
/// END VISIT is the button that trips it, and it is the common one: it shows
/// whenever anybody is in the room or has been called, and it is never held.
/// The controllers now live in `initState()`; these tests fail if they ever go
/// back to being lazily built.
void main() {
  Future<void> mount(WidgetTester tester, VisitAction action) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ActionButton(action: action, onFire: () {})),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'mounting $action');
  }

  for (final action in VisitAction.values) {
    testWidgets('a ${action.name} button unmounts without crashing',
        (tester) async {
      await mount(tester, action);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'disposing $action — the controllers were built too late');
    });
  }

  testWidgets('disposing a button that has already been used', (tester) async {
    await mount(tester, VisitAction.noShow);
    final centre = tester.getCenter(find.byType(ActionButton));
    final gesture = await tester.startGesture(centre);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  /// Ticks in steps, the way a real frame budget does. One long `pump` moves
  /// the clock without ticking the animation, so a hold that depends on frames
  /// would never advance.
  Future<void> pumpFor(WidgetTester tester, int milliseconds) async {
    for (var t = 0; t < milliseconds; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('holding NO-SHOW for its full duration fires exactly once',
      (tester) async {
    var fired = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActionButton(action: VisitAction.noShow, onFire: () => fired++),
      ),
    ));
    await tester.pump();

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ActionButton)));
    await pumpFor(tester, 1000);
    await gesture.up();
    await tester.pump();

    expect(fired, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('letting go early cancels the hold instead of firing',
      (tester) async {
    var fired = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActionButton(action: VisitAction.noShow, onFire: () => fired++),
      ),
    ));
    await tester.pump();

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(ActionButton)));
    await pumpFor(tester, 200);
    await gesture.up();
    await pumpFor(tester, 600);

    expect(fired, 0);
    expect(tester.takeException(), isNull);
  });
}
