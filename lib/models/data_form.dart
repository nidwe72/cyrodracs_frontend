import 'data_form_element.dart';

class DataForm {
  final String? code;
  final String? entityValue;
  final List<DataFormElement> elements;

  const DataForm({this.code, this.entityValue, required this.elements});

  bool get hasEntity => entityValue != null && entityValue!.isNotEmpty;

  factory DataForm.fromJson(Map<String, dynamic> json) {
    return DataForm(
      code: json['code'] as String?,
      entityValue: json['entityValue'] as String?,
      elements: (json['elements'] as List<dynamic>)
          .map((e) => DataFormElement.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
