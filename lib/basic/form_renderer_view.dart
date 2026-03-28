import 'package:flutter/material.dart';
import 'package:flutter_bootstrap5/flutter_bootstrap5.dart';
import '../models/data_form_element.dart';

class FormRendererView extends StatefulWidget {
  final List<DataFormElement> elements;

  const FormRendererView({super.key, required this.elements});

  @override
  State<FormRendererView> createState() => _FormRendererViewState();
}

class _FormRendererViewState extends State<FormRendererView> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  String? _submitResult;

  @override
  void initState() {
    super.initState();
    for (final e in widget.elements) {
      _values[e.key] = null;
    }
  }

  void _onSubmit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _submitResult = _values.entries
            .map((e) => '${e.key}: ${e.value ?? '-'}')
            .join('\n');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FB5Row(
              classNames: 'g-3',
              children: widget.elements
                  .map((e) => FB5Col(classNames: 'col-12 col-md-6', child: _buildField(e)))
                  .toList(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _onSubmit, child: const Text('Submit')),
            if (_submitResult != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              SelectableText(
                _submitResult!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField(DataFormElement element) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: switch (element.type) {
        DataFormElementType.inputString => TextFormField(
            decoration: InputDecoration(
              labelText: element.label,
              border: const OutlineInputBorder(),
            ),
            onSaved: (v) => _values[element.key] = v,
          ),
        DataFormElementType.select => DropdownButtonFormField<String>(
            decoration: InputDecoration(
              labelText: element.label,
              border: const OutlineInputBorder(),
            ),
            items: element.options
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (v) => _values[element.key] = v,
            onSaved: (v) => _values[element.key] = v,
          ),
        DataFormElementType.datePicker => _DateField(
            label: element.label,
            onSaved: (v) => _values[element.key] = v,
          ),
      },
    );
  }
}

class _DateField extends StatefulWidget {
  final String label;
  final void Function(String?) onSaved;

  const _DateField({required this.label, required this.onSaved});

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _controller.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      onTap: _pickDate,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
      onSaved: (_) => widget.onSaved(_controller.text.isEmpty ? null : _controller.text),
    );
  }
}
