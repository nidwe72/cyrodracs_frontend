import 'package:date_picker_plus/date_picker_plus.dart';
import 'package:flutter/material.dart';
import 'picker_button.dart';

/// Side-by-side `from` / `to` year-month pickers (yyyy-MM).
class YearMonthRangeFilterInput extends StatelessWidget {
  const YearMonthRangeFilterInput({
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
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 328,
          height: 400,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MonthPicker(
              minDate: DateTime(1800),
              maxDate: DateTime(2200),
              onDateSelected: (v) => Navigator.pop(ctx, v),
            ),
          ),
        ),
      ),
    );
    if (picked == null) return;
    final yearMonth = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
    final from = slot == 'from' ? yearMonth : value?['from'];
    final to = slot == 'to' ? yearMonth : value?['to'];
    _emit(from, to);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PickerButton(
            text: value?['from'],
            placeholder: 'from',
            onTap: () => _pick(context, 'from'),
            onClear: value?['from'] != null ? () => _emit(null, value?['to']) : null,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: PickerButton(
            text: value?['to'],
            placeholder: 'to',
            onTap: () => _pick(context, 'to'),
            onClear: value?['to'] != null ? () => _emit(value?['from'], null) : null,
          ),
        ),
      ],
    );
  }
}
