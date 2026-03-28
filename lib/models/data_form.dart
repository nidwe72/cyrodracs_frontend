import 'data_form_element.dart';

class DataForm {
  final List<DataFormElement> elements;

  const DataForm({required this.elements});

  factory DataForm.fromJson(Map<String, dynamic> json) {
    return DataForm(
      elements: (json['elements'] as List<dynamic>)
          .map((e) => DataFormElement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
