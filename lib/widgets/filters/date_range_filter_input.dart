import 'package:date_picker_plus/date_picker_plus.dart';
import 'package:flutter/material.dart';
import 'picker_button.dart';

/// Side-by-side `from` / `to` date pickers (ISO yyyy-MM-dd).
class DateRangeFilterInput extends StatelessWidget {
  const DateRangeFilterInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Map<String, String>? value;
  final void Function(Map<String, String>? value) onChanged;

  void _emit(String? from, String? to) {
    final out = <String, String>{};
    if (from != null && from.isNotEmpty) out['from'] = from;
    if (to != null && to.isNotEmpty) out['to'] = to;
    onChanged(out.isEmpty ? null : out);
  }

  Future<void> _pick(BuildContext context, String slot) async {
    final picked = await showDatePickerDialog(
      context: context,
      initialDate: DateTime.now(),
      minDate: DateTime(1800),
      maxDate: DateTime(2200),
    );
    if (picked == null) return;
    final iso = '${picked.year}-${picked.month.toString().padLeft(2, '0')}'
        '-${picked.day.toString().padLeft(2, '0')}';
    final from = slot == 'from' ? iso : value?['from'];
    final to = slot == 'to' ? iso : value?['to'];
    _emit(from, to);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PickerButton(
          width: 110,
          text: value?['from'],
          placeholder: 'from',
          onTap: () => _pick(context, 'from'),
          onClear: value?['from'] != null ? () => _emit(null, value?['to']) : null,
        ),
        const SizedBox(width: 4),
        PickerButton(
          width: 110,
          text: value?['to'],
          placeholder: 'to',
          onTap: () => _pick(context, 'to'),
          onClear: value?['to'] != null ? () => _emit(value?['from'], null) : null,
        ),
      ],
    );
  }
}
