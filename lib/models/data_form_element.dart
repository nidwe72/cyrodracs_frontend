enum DataFormElementType {
  inputString,
  inputNumber,
  inputEmail,
  inputPassword,
  textarea,
  select,
  multiSelect,
  checkboxGroup,
  radioGroup,
  checkbox,
  toggle,
  datePicker,
  timePicker,
  dateTimePicker,
  dateRangePicker,
  slider,
  rating,
  datePickerYearMonth,
  entitySelect,
  grid,
}

class GridTableColumn {
  final String key;
  final String header;
  final String? entityRendererRef;

  const GridTableColumn({
    required this.key,
    required this.header,
    this.entityRendererRef,
  });
}

class DataFormElement {
  final String key;
  final String label;
  final DataFormElementType type;
  final String? dataBinding;
  final int? dataBindingNodeId;
  final String? entityProviderRef;
  final int? entityProviderRefNodeId;
  final String? entityRendererRef;
  final int? entityRendererRefNodeId;
  final List<String> options;
  final int cols;
  final bool breakBefore;
  final double? min;
  final double? max;
  final int? rows;
  final List<GridTableColumn> tableColumns;
  final bool reloadOnChange;

  const DataFormElement({
    required this.key,
    required this.label,
    required this.type,
    this.dataBinding,
    this.dataBindingNodeId,
    this.entityProviderRef,
    this.entityProviderRefNodeId,
    this.entityRendererRef,
    this.entityRendererRefNodeId,
    this.options = const [],
    this.cols = 12,
    this.breakBefore = false,
    this.min,
    this.max,
    this.rows,
    this.tableColumns = const [],
    this.reloadOnChange = false,
  });

  factory DataFormElement.fromJson(Map<String, dynamic> json) {
    return DataFormElement(
      key: json['key'] as String,
      label: json['label'] as String,
      type: DataFormElementType.values.byName(json['type'] as String),
      dataBinding: json['dataBinding'] as String?,
      dataBindingNodeId: (json['dataBindingNodeId'] as num?)?.toInt(),
      entityProviderRef: json['entityProviderRef'] as String?,
      entityProviderRefNodeId: (json['entityProviderRefNodeId'] as num?)?.toInt(),
      entityRendererRef: json['entityRendererRef'] as String?,
      entityRendererRefNodeId: (json['entityRendererRefNodeId'] as num?)?.toInt(),
      options: (json['options'] as List<dynamic>?)?.cast<String>() ?? [],
      cols: json['cols'] as int? ?? 12,
      breakBefore: json['breakBefore'] as bool? ?? false,
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
      rows: json['rows'] as int?,
      tableColumns: ((json['tableColumns'] as List<dynamic>?) ?? [])
          .map((c) {
            final m = c as Map<String, dynamic>;
            return GridTableColumn(
              key: m['key'] as String,
              header: m['header'] as String,
              entityRendererRef: m['entityRendererRef'] as String?,
            );
          })
          .toList(),
      reloadOnChange: json['reloadOnChange'] as bool? ?? false,
    );
  }
}
