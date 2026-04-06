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
    );
  }
}
