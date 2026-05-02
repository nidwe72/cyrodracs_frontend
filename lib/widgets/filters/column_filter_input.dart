import 'package:flutter/material.dart';
import '../../models/column_filter_meta.dart';
import 'boolean_filter_input.dart';
import 'date_range_filter_input.dart';
import 'datetime_range_filter_input.dart';
import 'debouncer.dart';
import 'entity_ref_filter_input.dart';
import 'enum_filter_input.dart';
import 'number_range_filter_input.dart';
import 'string_filter_input.dart';
import 'year_month_range_filter_input.dart';

/// Dispatches to the right per-type input widget for a column. Returns null
/// for UNSUPPORTED.
///
/// [acquireController] returns a stable [TextEditingController] for a given
/// sub-key under the column. Sub-keys used:
///   - `''`       — STRING input
///   - `'from'`   — NUMBER lower bound
///   - `'to'`     — NUMBER upper bound
///
/// Scope params ([viewNodeCode] / [dataFormCode] / [elementCode]) are
/// required by the ENTITY_REF picker so it can fetch candidates from the
/// correct table surface. Other types ignore them.
///
/// CF3.4.3 picker-restriction params (ENTITY_REF only):
/// - [userFilter] — the host's full active CF1 user-filter tree, for the
///   backend to strip the picker's own column and run the inner DISTINCT.
/// - [editorEntityId] — the parent editor entity's id when the surface is a
///   GRID inside an editor (drives the Janino injectable's editor-entity).
/// - [dismissTrigger] — a [Listenable] that fires whenever any column filter
///   changes; the picker overlay closes on each tick to avoid showing stale
///   candidates relative to the now-changed `otherUserFilters`.
///
/// CF3.4.4 picker-augmentation param (ENTITY_REF only):
/// - [pendingRowDirectValues] — list of `{ fieldName, ids }` tuples carrying
///   pending rows' direct field values for picker candidate augmentation in
///   create-new mode. Null/empty → no augmentation (CF3.4.3 behaviour).
Widget? buildColumnFilterInput({
  required ColumnFilterMeta meta,
  required dynamic currentValue,
  required TextEditingController Function(String subkey) acquireController,
  required Debouncer debouncer,
  required void Function(String columnKey, dynamic value) onChanged,
  String? viewNodeCode,
  String? dataFormCode,
  String? elementCode,
  Map<String, dynamic>? userFilter,
  int? editorEntityId,
  Listenable? dismissTrigger,
  List<Map<String, dynamic>>? pendingRowDirectValues,
}) {
  switch (meta.filterType) {
    case ColumnFilterType.string:
      return StringFilterInput(
        controller: acquireController(''),
        debouncer: debouncer,
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.number:
      return NumberRangeFilterInput(
        fromController: acquireController('from'),
        toController: acquireController('to'),
        debouncer: debouncer,
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.boolean:
      return BooleanFilterInput(
        value: currentValue is bool ? currentValue : null,
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.entityEnum:
      final values = meta.enumValues ?? const <String>[];
      return EnumFilterInput(
        values: values,
        value: currentValue is String ? currentValue : null,
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.date:
      return DateRangeFilterInput(
        value: currentValue is Map<String, String>
            ? currentValue
            : (currentValue is Map ? Map<String, String>.from(currentValue) : null),
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.yearMonth:
      return YearMonthRangeFilterInput(
        value: currentValue is Map<String, String>
            ? currentValue
            : (currentValue is Map ? Map<String, String>.from(currentValue) : null),
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.datetime:
      return DateTimeRangeFilterInput(
        value: currentValue is Map<String, String>
            ? currentValue
            : (currentValue is Map ? Map<String, String>.from(currentValue) : null),
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.entityRef:
      return EntityRefFilterInput(
        columnKey: meta.columnKey,
        value: currentValue is Map<String, dynamic>
            ? currentValue
            : (currentValue is Map ? Map<String, dynamic>.from(currentValue) : null),
        viewNodeCode: viewNodeCode,
        dataFormCode: dataFormCode,
        elementCode: elementCode,
        userFilter: userFilter,
        editorEntityId: editorEntityId,
        dismissTrigger: dismissTrigger,
        pendingRowDirectValues: pendingRowDirectValues,
        onChanged: (v) => onChanged(meta.columnKey, v),
      );
    case ColumnFilterType.unsupported:
      return null;
  }
}
