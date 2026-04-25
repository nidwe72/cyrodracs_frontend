import 'package:flutter/material.dart';

/// Single-select enum dropdown. Emits the chosen value, or null when cleared.
class EnumFilterInput extends StatelessWidget {
  const EnumFilterInput({
    super.key,
    required this.values,
    required this.value,
    required this.onChanged,
  });

  final List<String> values;
  final String? value;
  final void Function(String? value) onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 28,
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          border: OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: value,
            isDense: true,
            isExpanded: true,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('any')),
              ...values.map((v) => DropdownMenuItem<String?>(
                    value: v,
                    child: Text(v),
                  )),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
