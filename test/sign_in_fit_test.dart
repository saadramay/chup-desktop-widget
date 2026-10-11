import 'package:chup_widget/ui/sign_in.dart';
import 'package:chup_widget/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_harness.dart';

// The sign-in card's window is fixed at kSignInWidth x kSignInHeight, so the
// card has to fit that box exactly: too small and Flutter paints the yellow and
// black overflow stripes across the bottom of the card, too big and the card
// floats inside a window with dead space around it.
//
// The height is not a number anyone picked — the design sheet says 271, but
// that was measured from the mock, not from Segoe UI at these sizes, and the
// logo was not rendering when the sheet was written (it was missing from
// pubspec, so SvgPicture drew nothing rather than its 28px). Measured here
// against the real faces instead.
void main() {
  var segouiLoaded = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initPanelStorage();
    segouiLoaded = await loadSegoe();
  });

  testWidgets('the sign-in card fits the window it is given', (tester) async {
    requireSegoe(segouiLoaded);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SizedBox(
            width: kSignInWidth,
            height: kSignInHeight,
            child: const SignInScreen(),
          ),
        ),
      ),
    ));

    // The logo is an async asset load; without this the first pump measures a
    // card with no logo in it at all.
    await tester.pumpAndSettle();

    final e = tester.takeException();
    expect(e, isNull,
        reason: 'the sign-in card overflows its $kSignInWidth x '
            '$kSignInHeight window. Raise kSignInHeight to the height the '
            'card actually needs: $e');
  }, skip: noSegoe);
}
