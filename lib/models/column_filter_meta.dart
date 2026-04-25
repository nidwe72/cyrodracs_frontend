/// Filter-input widget kinds supported by the inline column filter, returned
/// by the backend's `columnFilterMetadata` query. Mirrors the backend
/// `ColumnFilterType` enum.
enum ColumnFilterType {
  string,
  number,
  date,
  yearMonth,
  datetime,
  boolean,
  entityEnum,    // Dart name avoids clash with the language `enum` keyword
  entityRef,
  unsupported;

  static ColumnFilterType fromWire(String value) {
    return switch (value) {
      'STRING' => ColumnFilterType.string,
      'NUMBER' => ColumnFilterType.number,
      'DATE' => ColumnFilterType.date,
      'YEAR_MONTH' => ColumnFilterType.yearMonth,
      'DATETIME' => ColumnFilterType.datetime,
      'BOOLEAN' => ColumnFilterType.boolean,
      'ENUM' => ColumnFilterType.entityEnum,
      'ENTITY_REF' => ColumnFilterType.entityRef,
      _ => ColumnFilterType.unsupported,
    };
  }
}

/// Per-column filter descriptor returned by `columnFilterMetadata`.
class ColumnFilterMeta {
  final String columnKey;
  final ColumnFilterType filterType;
  final String? entityProviderRef;
  final String? entityRendererRef;
  final List<String>? enumValues;

  ColumnFilterMeta({
    required this.columnKey,
    required this.filterType,
    this.entityProviderRef,
    this.entityRendererRef,
    this.enumValues,
  });

  factory ColumnFilterMeta.fromJson(Map<String, dynamic> json) {
    return ColumnFilterMeta(
      columnKey: json['columnKey'] as String,
      filterType: ColumnFilterType.fromWire(json['filterType'] as String),
      entityProviderRef: json['entityProviderRef'] as String?,
      entityRendererRef: json['entityRendererRef'] as String?,
      enumValues: (json['enumValues'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
