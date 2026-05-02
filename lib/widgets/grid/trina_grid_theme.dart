import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';
import '../../theme/app_theme.dart';

/// Single source of truth for TrinaGrid row metrics. Exposed so callers
/// (e.g. embedded GRID's vertical-sizing helper per gridElement.md G1.6.8)
/// can compute heights without dipping into Trina internals.
const double kTrinaRowHeight = 44;

/// Header height when the column has the project's two-row header
/// (label row + per-column filter input row, per columnFilters.md CF1.1).
const double kTrinaColumnHeightWithFilter = 88;

/// Header height when columns have only the label row (no filter inputs).
const double kTrinaColumnHeightNoFilter = 44;

/// Project-wide [TrinaGridConfiguration] mapped onto [AppTheme] tokens.
/// Used by both the ENTITY_LIST surface (`app_view.dart`) and the GRID
/// DataFormElement surface (`form_renderer_view.dart`) so the migrated
/// tables look consistent and (roughly) match the pre-migration
/// Material `DataTable` baseline.
///
/// `columnHeight` varies by surface: 88 when filter inputs are present
/// (two-row header), 44 otherwise. Caller passes the right value.
TrinaGridConfiguration trinaGridConfigForApp({
  required double columnHeight,
  double rowHeight = kTrinaRowHeight,
}) {
  return TrinaGridConfiguration(
    // Columns scale to fill the table's horizontal extent (using each
    // TrinaColumn.width as the proportion seed). User column resize
    // pushes/pulls neighbours, preserving the total — so individual
    // resizes don't leave or create empty space at the right.
    columnSize: const TrinaGridColumnSizeConfig(
      autoSizeMode: TrinaAutoSizeMode.scale,
      resizeMode: TrinaResizeMode.pushAndPull,
    ),
    // `columnShowScrollWidth: true` (Trina default) reserves the
    // scrollbar's thickness in the column-header layout — visible as a
    // permanent ~8 px gap on the right. Disable it so columns fill the
    // full table width; the vertical scrollbar overlays the rightmost
    // column when scrolling instead of pre-claiming a gutter.
    scrollbar: const TrinaGridScrollbarConfig(
      columnShowScrollWidth: false,
    ),
    style: TrinaGridStyleConfig(
      // Heights
      columnHeight: columnHeight,
      rowHeight: rowHeight,
      // Drop Trina's default 2-px inner padding around the entire grid
      // content; the Card already provides outer spacing.
      gridPadding: 0,
      // Drop Trina's redundant 1-px inner border; the Card already has
      // its own 1-px shade200 border on the same edge.
      gridBorderWidth: 0,
      // Striping — first data row white, next row tinted. Trina's
      // `evenRowColor` is applied to row indices that are even by *its*
      // counting (1-based), which presents row 1 as "odd" visually;
      // mapping `oddRowColor: white` puts the first row white.
      rowColor: Colors.white,
      evenRowColor: AppTheme.tableStripeColor,
      oddRowColor: Colors.white,
      // Borders — lighter than the panel border for a subtler grid feel.
      gridBorderColor: Colors.grey.shade200,
      borderColor: Colors.grey.shade200,
      enableGridBorderShadow: false,
      // Header — reuse the same text style we used on DataTable.
      columnTextStyle: AppTheme.tableHeaderStyle,
      // Cell — slightly tighter than Trina's 14pt default to match
      // the prior 13pt density.
      cellTextStyle: const TextStyle(
        fontSize: 13,
        color: Colors.black87,
      ),
      // Sort glyph icons aren't shown — we render our own glyph in the
      // titleRenderer (CF2.1). Keeping defaults here is harmless.
    ),
  );
}
