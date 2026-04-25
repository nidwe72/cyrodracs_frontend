import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'debouncer.dart';

/// Side-by-side `from` / `to` numeric inputs. Either may be empty.
/// Emits a `Map<String, String>` with non-empty `from` / `to` keys, or null
/// when both are empty.
class NumberRangeFilterInput extends StatelessWidget {
  const NumberRangeFilterInput({
    super.key,
    required this.fromController,
    required this.toController,
    required this.debouncer,
    required this.onChanged,
  });

  final TextEditingController fromController;
  final TextEditingController toController;
  final Debouncer debouncer;
  final void Function(Map<String, String>? value) onChanged;

  void _emit() {
    final from = fromController.text.trim();
    final to = toController.text.trim();
    final out = <String, String>{};
    if (from.isNotEmpty) out['from'] = from;
    if (to.isNotEmpty) out['to'] = to;
    onChanged(out.isEmpty ? null : out);
  }

  Widget _field(TextEditingController controller, String hint) {
    return SizedBox(
      width: 76,
      height: 28,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]'))],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (_) => debouncer.run(_emit),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(fromController, 'from'),
        const SizedBox(width: 4),
        _field(toController, 'to'),
      ],
    );
  }
}
