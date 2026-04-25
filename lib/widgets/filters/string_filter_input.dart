import 'package:flutter/material.dart';
import 'debouncer.dart';

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
    return SizedBox(
      width: 160,
      height: 28,
      child: TextField(
        controller: controller,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (value) {
          debouncer.run(() => onChanged(value));
        },
      ),
    );
  }
}
