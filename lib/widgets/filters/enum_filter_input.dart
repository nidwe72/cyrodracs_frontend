import 'package:flutter/material.dart';
import 'filter_field_style.dart';

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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160),
      child: FilterFieldShell(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              isDense: true,
              isExpanded: true,
              style: kFilterFieldTextStyle.copyWith(color: Colors.black87),
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
      ),
    );
  }
}
