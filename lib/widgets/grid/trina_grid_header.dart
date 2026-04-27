import 'package:flutter/material.dart';
import 'column_sort.dart' show SortDirection;

/// Two-row column header used inside a TrinaGrid via
/// [TrinaColumn.titleRenderer]. Row 1 is the column label + sort glyph
/// (clickable area cycles sort). Row 2 is an optional filter input — when
/// non-null it fills the column width via stretch.
///
/// Hosted within a parent that provides a tight `(width, height)`
/// constraint; `buildTrinaColumn` wraps this in a `Container` sized from
/// `TrinaColumnTitleRendererContext.column.width` / `.height`.
class SortableFilterableHeader extends StatelessWidget {
  const SortableFilterableHeader({
    super.key,
    required this.header,
    required this.isSortActive,
    required this.sortDirection,
    required this.onSortToggle,
    this.filterInput,
  });

  final String header;
  final bool isSortActive;
  final SortDirection? sortDirection;
  final VoidCallback onSortToggle;
  final Widget? filterInput;

  IconData get _glyph {
    if (!isSortActive) return Icons.unfold_more;
    if (sortDirection == SortDirection.asc) return Icons.arrow_upward;
    return Icons.arrow_downward;
  }

  Color? get _glyphColor => isSortActive ? null : Colors.grey.shade400;

  @override
  Widget build(BuildContext context) {
    final labelRow = InkWell(
      onTap: onSortToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(
                header,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            Icon(_glyph, size: 14, color: _glyphColor),
          ],
        ),
      ),
    );

    if (filterInput == null) {
      return Center(child: labelRow);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          labelRow,
          const SizedBox(height: 4),
          filterInput!,
        ],
      ),
    );
  }
}
