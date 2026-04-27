import 'package:flutter/material.dart';

/// Centralised styling tokens + helpers for the inline column-filter
/// widgets (string, number, date, year-month, datetime, boolean, enum,
/// entity-ref). Keeps height, border colour, font, and the various
/// `TextField` overrides that Flutter requires to actually centre text
/// inside a fixed-height box (see `filterFieldInputDecoration`,
/// `kFilterTextAlignVertical`) in one place — change here and every
/// filter widget picks it up.

/// Outer height of every filter input — string box, range pickers,
/// boolean toggle, enum dropdown, date-picker button.
const double kFilterFieldHeight = 28;

/// Body text size used inside every filter field.
const double kFilterFieldFontSize = 13;

/// Body text style used inside every filter field.
const TextStyle kFilterFieldTextStyle = TextStyle(fontSize: kFilterFieldFontSize);

/// Hint / placeholder text style.
final TextStyle kFilterFieldHintStyle = TextStyle(
  fontSize: 12,
  color: Colors.grey.shade500,
);

/// Text alignment baseline offset for `TextField`-based filter widgets.
///
/// `TextAlignVertical.center` (`y = 0`) puts the **baseline** at the box
/// midpoint, which makes glyphs sit above visual centre (ascenders take
/// more vertical room than descenders). A small positive `y` nudges the
/// baseline below the midpoint so the visible text is optically centred.
/// This is Flutter's documented workaround for the typographic asymmetry
/// — see `TextAlignVertical` API docs.
const TextAlignVertical kFilterTextAlignVertical = TextAlignVertical(y: 0.4);

/// Decoration for the outer `Container` that draws the white background
/// + 1-px shade-400 border around every filter input.
final BoxDecoration kFilterFieldDecoration = BoxDecoration(
  color: Colors.white,
  border: Border.all(color: Colors.grey.shade400),
);

/// Wraps a filter widget's inner content in the standard outer
/// `Container` shell (fixed height + white background + shade-400 border).
/// Use this so every filter widget renders an identical visible box.
class FilterFieldShell extends StatelessWidget {
  const FilterFieldShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kFilterFieldHeight,
      decoration: kFilterFieldDecoration,
      child: child,
    );
  }
}

/// `InputDecoration` for `TextField`-based filter widgets. Defeats the
/// global `inputDecorationTheme` (in `main.dart`) which otherwise leaks
/// `floatingLabelBehavior: always`, vertical content padding, and
/// outline borders into our compact filter inputs.
InputDecoration filterFieldInputDecoration({String? hintText}) {
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
    hintText: hintText,
    hintStyle: kFilterFieldHintStyle,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    floatingLabelBehavior: FloatingLabelBehavior.never,
  );
}
