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
const cInk800 = Color(0xFF1D1D1D); // body ink
const cInk500 = Color(0xFF4F4F4F); // secondary text, micro labels
const cLine200 = Color(0xFFEBEBEB); // every hairline
const cLine300 = Color(0xFFCFD1D4); // unchecked control borders
const cWhite = Color(0xFFFFFFFF);

/// The widget is a Windows citizen — it uses the OS UI stack, not the document
/// faces the Chup stationery uses.
const kFont = 'Segoe UI Variable Text';
const kFontFallback = <String>['Segoe UI', 'system-ui'];

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
