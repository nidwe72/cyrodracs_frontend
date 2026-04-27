import 'package:flutter/material.dart';
import 'filter_field_style.dart';

/// Tri-state boolean filter: `true` / `false` / `any`.
/// Emits true, false, or null (any). No debounce — each click is a deliberate
/// commit per CF1.4.
class BooleanFilterInput extends StatelessWidget {
  const BooleanFilterInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool? value;
  final void Function(bool? value) onChanged;

  Widget _option(String label, bool? optionValue) {
    final selected = value == optionValue;
    return InkWell(
      onTap: () => onChanged(optionValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade100 : Colors.transparent,
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.blue.shade900 : Colors.black87,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kFilterFieldHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option('any', null),
          _option('true', true),
          _option('false', false),
        ],
      ),
    );
  }
}
