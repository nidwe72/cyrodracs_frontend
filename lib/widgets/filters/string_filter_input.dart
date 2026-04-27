import 'package:flutter/material.dart';
import 'debouncer.dart';
import 'filter_field_style.dart';

/// A single text field that fires [onChanged] after [debounce] of quiet typing.
/// The owning widget is responsible for storing the latest value and composing
/// it into the next data-fetch request.
class StringFilterInput extends StatelessWidget {
  const StringFilterInput({
    super.key,
    required this.controller,
    required this.debouncer,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Debouncer debouncer;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160),
      child: FilterFieldShell(
        child: TextField(
          controller: controller,
          textAlignVertical: kFilterTextAlignVertical,
          decoration: filterFieldInputDecoration(),
          style: kFilterFieldTextStyle,
          onChanged: (value) {
            debouncer.run(() => onChanged(value));
          },
        ),
      ),
    );
  }
}
