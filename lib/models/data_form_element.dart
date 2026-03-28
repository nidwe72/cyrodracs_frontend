enum DataFormElementType {
  inputString,
  select,
  datePicker,
}

class DataFormElement {
  final String key;
  final String label;
  final DataFormElementType type;
  final List<String> options;

  const DataFormElement({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
  });
}
