import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';
import '../../theme/app_theme.dart';
import 'column_sort.dart' show SortDirection;
import 'trina_grid_header.dart';
import 'trina_grid_theme.dart' show kTrinaRowHeight;

/// Computes the bounded pixel height for an embedded GRID's TrinaGrid host
/// per gridElement.md G1.6.8 — sum of header height plus
/// `rowCount × rowHeight`. When `rowCount == 0` we reserve one row's worth
/// of height for the empty-state widget (TrinaGrid renders its
/// `noRowsWidget` inside the bounded area).
///
/// `rowCount` MUST be the count of effective rows on screen
/// (committed plus pending — see `_effectiveRows()` in
/// `form_renderer_view.dart`). The "+1 for empty state" convention keeps
/// the no-rows message visible without hardcoding a separate empty
/// height.
double computeGridBodyHeight({
  required int rowCount,
  required double headerHeight,
  double rowHeight = kTrinaRowHeight,
}) {
  final dataRows = rowCount == 0 ? 1 : rowCount;
  return headerHeight + dataRows * rowHeight;
}

/// Builds a [TrinaColumn] for the project's table surfaces.
///
/// Project carve-outs (per `components.md` C1.10): in-cell editing,
/// built-in filter UI, context menu, default sort cycle, and column drag
/// are all disabled. Resize is enabled.
///
/// `TrinaGrid.didUpdateWidget` does not react to changes in the `columns`
/// prop — columns are consumed once at init and managed by `stateManager`
/// thereafter. This API therefore takes a [Listenable] (`rebuildOn`) plus
/// getter callbacks for the bits of host state that drive the header
/// (sort glyph, filter input). Whenever the host signals `rebuildOn`,
/// the column's title widget rebuilds with fresh state via
/// [AnimatedBuilder]. The `TrinaColumn` itself stays stable, preserving
/// stateManager-held UI state (e.g. user resize).
TrinaColumn buildTrinaColumn({
  required String columnKey,
  required String header,
  required Listenable rebuildOn,
  required bool Function() getIsSortActive,
  required SortDirection? Function() getSortDirection,
  required void Function(String columnKey) onSortToggle,
  Widget? Function()? buildFilterInput,
  double initialWidth = 200,
  double minWidth = 80,
  bool enableResize = true,
  TrinaColumnRenderer? cellRenderer,
}) {
  return TrinaColumn(
    title: header,
    field: columnKey,
    type: TrinaColumnType.text(),
    width: initialWidth,
    minWidth: minWidth,
    enableEditingMode: false,
    enableFilterMenuItem: false,
    enableContextMenu: false,
    enableSorting: false,
    enableColumnDrag: false,
    enableDropToResize: enableResize,
    titleRenderer: (ctx) => Container(
      width: ctx.column.width,
      height: ctx.height,
      decoration: BoxDecoration(
        color: AppTheme.panelHeaderBackground,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200, width: 1.0),
        ),
      ),
      // Header content fills the cell. A thin invisible resize handle
      // sits on top of the right edge: it changes the mouse cursor to
      // `resizeLeftRight` on hover and forwards drag deltas to
      // `stateManager.resizeColumn`, which (with `pushAndPull` mode,
      // see `trina_grid_theme.dart`) redistributes width with the
      // neighbouring column. No visible icon overlays the filter input.
      // We don't use `ctx.contextMenuIcon` because its IconButton
      // visually overlaps the cell content.
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: rebuildOn,
              builder: (_, __) => SortableFilterableHeader(
                header: header,
                isSortActive: getIsSortActive(),
                sortDirection: getSortDirection(),
                onSortToggle: () => onSortToggle(columnKey),
                filterInput: buildFilterInput?.call(),
              ),
            ),
          ),
          if (enableResize)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _ColumnResizeHandle(
                stateManager: ctx.stateManager,
                column: ctx.column,
              ),
            ),
        ],
      ),
    ),
    renderer: cellRenderer ?? defaultCellRenderer,
  );
}

/// Builds a narrow fixed-width action-only column (edit, delete, etc.).
/// Suppressed from auto-size so the surrounding data columns get the
/// remaining width via `TrinaAutoSizeMode.scale`. No header content,
/// no filter row, no resize, no sort.
TrinaColumn buildTrinaActionColumn({
  required String field,
  required double width,
  required TrinaColumnRenderer cellRenderer,
}) {
  return TrinaColumn(
    title: '',
    field: field,
    type: TrinaColumnType.text(),
    width: width,
    minWidth: width,
    enableEditingMode: false,
    enableFilterMenuItem: false,
    enableContextMenu: false,
    enableSorting: false,
    enableColumnDrag: false,
    enableDropToResize: false,
    suppressedAutoSize: true,
    titleRenderer: (ctx) => Container(
      width: ctx.column.width,
      height: ctx.height,
      // Same background and right-border as data column headers so the
      // action column separator is visually identical to the
      // data-column separators.
      decoration: BoxDecoration(
        color: AppTheme.panelHeaderBackground,
        border: Border(
          right: BorderSide(color: Colors.grey.shade200, width: 1.0),
        ),
      ),
    ),
    renderer: cellRenderer,
  );
}

/// Builds a [TrinaRow] from an entity Map. The full entity is attached as
/// `TrinaRow.data` so cell renderers can read companion fields (e.g.
/// `displayValues`) without the cell value carrying them.
///
/// `displayValues` is a map of pre-rendered display strings keyed by field;
/// when non-null and a key is present, the cell value is replaced by the
/// display string (used for ENTITY_REF columns and any other backend-rendered
/// presentation). The raw entity stays accessible via `row.data`.
TrinaRow<Map<String, dynamic>> buildTrinaRow({
  required Map<String, dynamic> entity,
  required List<String> fieldKeys,
  Map<String, String>? displayValues,
  Map<String, dynamic>? metadata,
}) {
  final cells = <String, TrinaCell>{};
  for (final key in fieldKeys) {
    final display = displayValues?[key];
    final value = display ?? entity[key];
    cells[key] = TrinaCell(value: value);
  }
  return TrinaRow<Map<String, dynamic>>(
    cells: cells,
    data: entity,
    metadata: metadata,
  );
}

/// Default text-with-tooltip-ellipsis cell renderer. Use this for plain
/// String / Number / Date display where the cell value is already the
/// display string. Specialised renderers (boolean checkmark, formatted
/// date, multi-line, etc.) can be passed to [buildTrinaColumn] via
/// `cellRenderer`.
Widget defaultCellRenderer(TrinaColumnRendererContext ctx) {
  final raw = ctx.cell.value;
  final text = raw == null ? '' : raw.toString();
  return Tooltip(
    message: text,
    waitDuration: const Duration(milliseconds: 600),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1),
    ),
  );
}

/// Reads the original entity attached to a row by [buildTrinaRow]. Returns
/// null when the row was constructed by other means.
Map<String, dynamic>? entityFromRow(TrinaRow row) {
  final data = row.data;
  return data is Map<String, dynamic> ? data : null;
}

/// `ChangeNotifier` subclass exposing a public `bump()` so a host can
/// trigger `AnimatedBuilder` rebuilds inside `titleRenderer` without
/// violating `ChangeNotifier`'s `@protected notifyListeners`. Pass an
/// instance as `rebuildOn` to [buildTrinaColumn]; call [bump] whenever
/// host state that the column header reads (sort / filter) changes.
class GridRebuildTrigger extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Thin, invisible drag area placed at the right edge of every column
/// header. Mouse cursor flips to `resizeLeftRight` only on hover; drag
/// forwards/backwards calls `stateManager.resizeColumn`. Replaces the
/// default IconButton-based handle that Trina would otherwise render at
/// the column's right edge — visible there, but visually intrusive over
/// our filter inputs.
class _ColumnResizeHandle extends StatefulWidget {
  const _ColumnResizeHandle({
    required this.stateManager,
    required this.column,
  });

  final TrinaGridStateManager stateManager;
  final TrinaColumn column;

  @override
  State<_ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<_ColumnResizeHandle> {
  Offset? _lastPosition;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) => _lastPosition = event.position,
        onPointerMove: (event) {
          final last = _lastPosition;
          if (last == null) return;
          final delta = event.position.dx - last.dx;
          final isLTR = widget.stateManager.isLTR;
          widget.stateManager.resizeColumn(widget.column, isLTR ? delta : -delta);
          _lastPosition = event.position;
        },
        onPointerUp: (_) {
          _lastPosition = null;
          widget.stateManager.updateCorrectScrollOffset();
        },
        child: const SizedBox(width: 6),
      ),
    );
  }
}
