import 'package:flutter/widgets.dart';

/// Chup design system tokens, as used by the widget.
const cGreen700 = Color(0xFF115934); // labels, END VISIT, meter green, rules
const cGreen600 = Color(0xFF0C6E3C); // token numerals
const cGreen50 = Color(0xFFEDF7F3); // control hover
const cOrange = Color(0xFFF26522); // ALERT only
const cOrangeHover = Color(0xFFDD5717);
const cGreen700Hover = Color(0xFF0D4728);
const cRed = Color(0xFFE03127); // NO-SHOW, overrun red
const cRedWash = Color(0xFFF9E9E8); // close-button hover
const cInk800 = Color(0xFF1F2328); // body ink
const cInk500 = Color(0xFF6B7280); // secondary text
const cInk400 = Color(0xFF9AA0A8); // tertiary text, end-of-list
const cLine200 = Color(0xFFECEEF0); // every hairline
const cLine300 = Color(0xFFCFD1D4); // unchecked control borders
const cWhite = Color(0xFFFFFFFF);
const cSurface2 = Color(0xFFF4F6F5); // pills, tracks, control hover
const cRedTint = Color(0xFFFDECEB); // no-show face

/// Corner radii: the panel, and controls inside it.
const kPanelRadius = 12.0;
const kControlRadius = 8.0;

/// The widget is a Windows citizen — it uses the OS UI stack, not the document
/// faces the Chup stationery uses.
const kFont = 'Segoe UI Variable Text';
const kFontFallback = <String>['Segoe UI', 'system-ui'];

/// The sign-in card's window. Shown once, centred, so it is the one size with
/// no geometry of its own to protect — it only has to be big enough for the
/// card.
///
/// The design sheet says 260 x 271. The 260 holds; the 271 was measured from
/// the HTML mock rather than from Segoe UI at these sizes, and it predates the
/// logo actually rendering (assets/chup-logo.svg was missing from pubspec, so
/// SvgPicture drew nothing instead of its 28px). Measured against the real
/// faces the card needs kSignInHeight, guarded by test/sign_in_fit_test.dart.
const kSignInWidth = 260.0;
const kSignInHeight = 336.0;

/// Every figure ticks, so numerals must not jitter as they change width.
const kTabular = <FontFeature>[FontFeature.tabularFigures()];

TextStyle t(
  double size,
  FontWeight weight, {
  Color color = cInk800,
  double? spacing,
  double? height,
  bool tabular = false,
}) =>
    TextStyle(
      fontFamily: kFont,
      fontFamilyFallback: kFontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
      fontFeatures: tabular ? kTabular : null,
    );
