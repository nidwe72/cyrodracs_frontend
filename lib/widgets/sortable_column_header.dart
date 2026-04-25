import 'package:flutter/material.dart';

/// User-driven sort direction for a column header.
enum SortDirection {
  asc,
  desc;

  /// Wire value matching the backend `SortDirection` GraphQL enum.
  String get wireValue => this == SortDirection.asc ? 'ASC' : 'DESC';
}

/// Cycles a column's sort state on each header click:
///   null -> ASC -> DESC -> null
///
/// Returns the next direction, or null when the column should clear.
SortDirection? cycleSortDirection(
  SortDirection? current, {
  required bool isActive,
}) {
  if (!isActive) return SortDirection.asc;
  return switch (current) {
    SortDirection.asc => SortDirection.desc,
    SortDirection.desc => null,
    null => SortDirection.asc,
  };
}

/// Builds a [DataColumn] whose label is a clickable header that displays a
/// sort glyph reflecting the current sort state. Clicking the header invokes
/// [onSortToggle] with this column's [columnKey]; the caller is responsible
/// for cycling the state and re-fetching.
///
/// [leftOffset] aligns the label with the row content for columns that sit
/// next to leading action icons (use [AppTheme.actionsOffset]).
/// Height reserved for the filter input row in 2-row headers. Matches the
/// height of [StringFilterInput].
const double kFilterRowHeight = 28;

DataColumn sortableDataColumn({
  required String columnKey,
  required String header,
  required String? activeSortKey,
  required SortDirection? activeSortDirection,
  required void Function(String columnKey) onSortToggle,
  double leftOffset = 0,
  Widget? filterInput,
  bool reserveFilterRow = false,
}) {
  final isActive = activeSortKey == columnKey;
  final IconData glyph;
  if (!isActive) {
    glyph = Icons.unfold_more;
  } else if (activeSortDirection == SortDirection.asc) {
    glyph = Icons.arrow_upward;
  } else {
    glyph = Icons.arrow_downward;
  }
  final glyphColor = isActive ? null : Colors.grey.shade400;

  final labelRow = InkWell(
    onTap: () => onSortToggle(columnKey),
    child: Padding(
      padding: EdgeInsets.only(left: leftOffset),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(header),
          const SizedBox(width: 4),
          Icon(glyph, size: 14, color: glyphColor),
        ],
      ),
    ),
  );

  if (filterInput == null && !reserveFilterRow) {
    return DataColumn(label: labelRow);
  }

  return DataColumn(
    label: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        labelRow,
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(left: leftOffset),
          child: filterInput ?? const SizedBox(height: kFilterRowHeight),
        ),
      ],
    ),
  );
}
