import 'package:flutter/material.dart';

/// Centralized styling constants for Cyrodracs.
///
/// Material widget styling is handled by ThemeData in main.dart.
/// This class covers custom styling that ThemeData cannot express.
abstract final class AppTheme {
  // -- Spacing scale --
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;

  // -- Icon sizing --
  static const double iconSize = 18;

  // -- Table row striping --
  static const Color tableStripeColor = Color(0xFFF8F9FA);

  // -- Panel header (GRID and reusable for future embedded panels) --
  static const Color panelHeaderBackground = Color(0xFFF1F3F5);
  static const EdgeInsets panelHeaderPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 10);
  static const TextStyle panelHeaderTitle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 14,
    color: Colors.black87,
  );

  // -- Table column headers --
  static const TextStyle tableHeaderStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: Colors.black87,
  );

  // -- Borders --
  static const BorderSide panelBorder = BorderSide(color: Color(0xFFDEE2E6));

  /// Builds an action icon (edit, delete, etc.) as a compact InkWell.
  static Widget actionIcon({
    required IconData icon,
    required VoidCallback? onTap,
    String? tooltip,
  }) {
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: iconSize),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: child);
    }
    return child;
  }

}
