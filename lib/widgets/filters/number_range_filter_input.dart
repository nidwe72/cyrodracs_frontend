import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'debouncer.dart';
import 'filter_field_style.dart';

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
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 80),
      child: FilterFieldShell(
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]'))],
          textAlignVertical: kFilterTextAlignVertical,
          decoration: filterFieldInputDecoration(hintText: hint),
          style: kFilterFieldTextStyle,
          onChanged: (_) => debouncer.run(_emit),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _field(fromController, 'from')),
        const SizedBox(width: 4),
        Expanded(child: _field(toController, 'to')),
      ],
    );
  }
}
