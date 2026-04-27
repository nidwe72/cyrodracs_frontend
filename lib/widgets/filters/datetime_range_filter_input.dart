import 'package:date_picker_plus/date_picker_plus.dart';
import 'package:flutter/material.dart';
import 'picker_button.dart';

/// Side-by-side `from` / `to` datetime pickers. The picker UI selects a date
/// only; `from` is implicitly start-of-day (T00:00:00), `to` is implicitly
/// end-of-day (T23:59:59), giving inclusive day-level range semantics over
/// LocalDateTime columns.
class DateTimeRangeFilterInput extends StatelessWidget {
  const DateTimeRangeFilterInput({
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

  String _format(DateTime d, {required bool endOfDay}) {
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';
    return '${date}T${endOfDay ? "23:59:59" : "00:00:00"}';
  }

  Future<void> _pick(BuildContext context, String slot) async {
    final picked = await showDatePickerDialog(
      context: context,
      initialDate: DateTime.now(),
      minDate: DateTime(1800),
      maxDate: DateTime(2200),
    );
    if (picked == null) return;
    final iso = _format(picked, endOfDay: slot == 'to');
    final from = slot == 'from' ? iso : value?['from'];
    final to = slot == 'to' ? iso : value?['to'];
    _emit(from, to);
  }

  String? _displayText(String? raw) {
    if (raw == null) return null;
    // Show only the date portion of the wire value.
    final tIndex = raw.indexOf('T');
    return tIndex > 0 ? raw.substring(0, tIndex) : raw;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PickerButton(
            text: _displayText(value?['from']),
            placeholder: 'from',
            onTap: () => _pick(context, 'from'),
            onClear: value?['from'] != null ? () => _emit(null, value?['to']) : null,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: PickerButton(
            text: _displayText(value?['to']),
            placeholder: 'to',
            onTap: () => _pick(context, 'to'),
            onClear: value?['to'] != null ? () => _emit(value?['from'], null) : null,
          ),
        ),
      ],
    );
  }
}
