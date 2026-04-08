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

  // Width of the action icons area (icon size + padding per icon + gap)
  static const double _actionIconWidth = iconSize + 8; // 4px padding each side

  /// Builds a DataCell that prepends action icons before the cell text.
  /// Used as the first data column cell in every DataRow (for edit icon).
  static DataCell cellWithActions(String text, List<Widget> actions) {
    return DataCell(Row(
      children: [
        ...actions,
        if (actions.isNotEmpty) const SizedBox(width: 8),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ],
    ));
  }

  /// Builds a DataCell that appends action icons after the cell text.
  /// Used as the last data column cell in every DataRow (for delete icon).
  static DataCell cellWithTrailingActions(String text, List<Widget> actions) {
    return DataCell(Row(
      children: [
        Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
        if (actions.isNotEmpty) const SizedBox(width: 8),
        ...actions,
      ],
    ));
  }

  /// Builds a DataColumn header with left padding to align with cellWithActions content.
  /// [actionCount] is the number of action icons at the start (typically 1 for edit).
  static DataColumn headerWithActionsOffset(String label, {int actionCount = 1}) {
    final offset = actionCount * _actionIconWidth + (actionCount > 0 ? 8 : 0);
    return DataColumn(
      label: Padding(
        padding: EdgeInsets.only(left: offset),
        child: Text(label),
      ),
    );
  }

  /// Returns a DataRow.color that applies striping based on row index.
  /// Even rows are white, odd rows are light grey.
  static WidgetStateProperty<Color?> stripeColor(int index) {
    return WidgetStateProperty.all(
      index.isOdd ? tableStripeColor : Colors.white,
    );
  }
}
