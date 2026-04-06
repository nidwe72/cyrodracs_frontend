import 'dart:convert';
import 'package:date_picker_plus/date_picker_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bootstrap5/flutter_bootstrap5.dart';
import 'package:http/http.dart' as http;
import '../app_config_editor/app_config_service.dart';
import '../models/data_form.dart';
import '../models/data_form_element.dart';
import '../theme/app_theme.dart';

class FormRendererView extends StatefulWidget {
  final DataForm form;
  final int? entityId;
  final Map<String, dynamic>? initialValues;
  final VoidCallback? onSaved;

  const FormRendererView({
    super.key,
    required this.form,
    this.entityId,
    this.initialValues,
    this.onSaved,
  });

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
    final initial = widget.initialValues;
    for (final e in widget.form.elements) {
      if (initial != null && initial.containsKey(e.key)) {
        _values[e.key] = initial[e.key];
      } else {
        _values[e.key] = switch (e.type) {
          DataFormElementType.checkbox || DataFormElementType.toggle => false,
          DataFormElementType.slider => e.min ?? 0.0,
          DataFormElementType.rating => 0,
          DataFormElementType.checkboxGroup ||
          DataFormElementType.multiSelect =>
            <String>[],
          _ => null,
        };
      }
    }
  }

  void _onSubmit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      if (widget.form.hasEntity) {
        _persistEntity();
      } else {
        _showValues();
      }
    }
  }

  void _showValues() {
    setState(() {
      _submitResult = _values.entries.map((e) {
        final v = e.value;
        if (v == null) return '${e.key}: -';
        if (v is List) return '${e.key}: ${v.isEmpty ? '-' : v.join(', ')}';
        if (v is double) return '${e.key}: ${v.toStringAsFixed(1)}';
        return '${e.key}: $v';
      }).join('\n');
    });
  }

  Future<void> _persistEntity() async {
    // Only send values for elements that belong to this form
    final formKeys = widget.form.elements.map((e) => e.key).toSet();
    final filteredValues = Map<String, dynamic>.fromEntries(
      _values.entries.where((e) => formKeys.contains(e.key)),
    );

    final body = <String, dynamic>{
      'dataFormCode': widget.form.code,
      'values': filteredValues,
      if (widget.entityId != null) 'entityId': widget.entityId,
    };
    try {
      final response = await http.post(
        Uri.parse('http://localhost:8080/api/data-form-data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _submitResult = 'Saved entity (id=${result['entityId']})\n'
              '${filteredValues.entries.map((e) => '${e.key}: ${e.value ?? '-'}').join('\n')}';
        });
        widget.onSaved?.call();
      } else {
        setState(() => _submitResult = 'Error: HTTP ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      setState(() => _submitResult = 'Error: $e');
    }
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    var group = <DataFormElement>[];
    for (final e in widget.form.elements) {
      if (e.breakBefore && group.isNotEmpty) {
        rows.add(_buildRow(group));
        group = [];
      }
      group.add(e);
    }
    if (group.isNotEmpty) rows.add(_buildRow(group));
    return rows;
  }

  Widget _buildRow(List<DataFormElement> elements) {
    return FB5Row(
      classNames: 'g-3',
      children: elements
          .map((e) => FB5Col(classNames: 'col-12 col-md-${e.cols}', child: _buildField(e)))
          .toList(),
    );
  }

  Widget _buildField(DataFormElement e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: switch (e.type) {
        DataFormElementType.inputString => TextFormField(
            initialValue: _values[e.key]?.toString(),
            decoration: InputDecoration(labelText: e.label),
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.inputNumber => TextFormField(
            decoration: InputDecoration(labelText: e.label),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSaved: (v) => _values[e.key] = v == null || v.isEmpty ? null : double.tryParse(v),
          ),
        DataFormElementType.inputEmail => TextFormField(
            decoration: InputDecoration(labelText: e.label),
            keyboardType: TextInputType.emailAddress,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.inputPassword => _PasswordField(
            label: e.label,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.textarea => TextFormField(
            decoration: InputDecoration(
              labelText: e.label,
      
              alignLabelWithHint: true,
            ),
            maxLines: e.rows ?? 3,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.select => DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: e.label),
            items: e.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => _values[e.key] = v,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.multiSelect => _MultiSelectField(
            label: e.label,
            options: e.options,
            onChanged: (v) => _values[e.key] = v,
          ),
        DataFormElementType.checkboxGroup => _CheckboxGroupField(
            label: e.label,
            options: e.options,
            onChanged: (v) => _values[e.key] = v,
          ),
        DataFormElementType.radioGroup => _RadioGroupField(
            label: e.label,
            options: e.options,
            onChanged: (v) => _values[e.key] = v,
          ),
        DataFormElementType.checkbox => _CheckboxField(
            label: e.label,
            onChanged: (v) => _values[e.key] = v,
          ),
        DataFormElementType.toggle => _ToggleField(
            label: e.label,
            onChanged: (v) => _values[e.key] = v,
          ),
        DataFormElementType.datePicker => _DateField(
            label: e.label,
            initialValue: _values[e.key]?.toString(),
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.timePicker => _TimeField(
            label: e.label,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.dateTimePicker => _DateTimeField(
            label: e.label,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.dateRangePicker => _DateRangeField(
            label: e.label,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.slider => _SliderField(
            label: e.label,
            min: e.min ?? 0.0,
            max: e.max ?? 100.0,
            onChanged: (v) => _values[e.key] = v,
          ),
        DataFormElementType.rating => _RatingField(
            label: e.label,
            max: e.max?.toInt() ?? 5,
            onChanged: (v) => _values[e.key] = v,
          ),
        DataFormElementType.datePickerYearMonth => _YearMonthField(
            label: e.label,
            initialValue: _values[e.key]?.toString(),
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.entitySelect => _EntitySelectField(
            label: e.label,
            providerCode: e.entityProviderRef ?? '',
            rendererCode: e.entityRendererRef ?? '',
            initialValue: _values[e.key] != null
                ? int.tryParse(_values[e.key].toString())
                : null,
            onChanged: (v) => _values[e.key] = v,
            onSaved: (v) => _values[e.key] = v,
          ),
        DataFormElementType.grid => _GridField(
            label: e.label,
            dataFormCode: widget.form.code ?? '',
            elementCode: e.key,
            entityId: widget.entityId,
            formState: _values,
            tableColumns: e.tableColumns,
          ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildRows(),
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
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text-based fields
// ---------------------------------------------------------------------------

class _PasswordField extends StatefulWidget {
  final String label;
  final void Function(String?) onSaved;

  const _PasswordField({required this.label, required this.onSaved});

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: widget.label,

        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, size: 18),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onSaved: widget.onSaved,
    );
  }
}

class _DateField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final void Function(String?) onSaved;

  const _DateField({required this.label, this.initialValue, required this.onSaved});

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showDatePickerDialog(
      context: context,
      initialDate: DateTime.now(),
      minDate: DateTime(1800),
      maxDate: DateTime(2200),
    );
    if (picked != null) {
      setState(() {
        _controller.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _clear() {
    setState(() => _controller.clear());
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      onTap: _pick,
      decoration: InputDecoration(
        labelText: widget.label,

        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: _clear,
              ),
            const Icon(Icons.calendar_today, size: 18),
            const SizedBox(width: 8),
          ],
        ),
      ),
      onSaved: (_) => widget.onSaved(_controller.text.isEmpty ? null : _controller.text),
    );
  }
}

class _YearMonthField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final void Function(String?) onSaved;

  const _YearMonthField({required this.label, this.initialValue, required this.onSaved});

  @override
  State<_YearMonthField> createState() => _YearMonthFieldState();
}

class _YearMonthFieldState extends State<_YearMonthField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
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
              onDateSelected: (value) => Navigator.pop(ctx, value),
            ),
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _controller.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
      });
    }
  }

  void _clear() {
    setState(() => _controller.clear());
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'YYYY-MM',

        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: _clear,
              ),
            IconButton(
              icon: const Icon(Icons.calendar_today, size: 18),
              onPressed: _pick,
            ),
          ],
        ),
      ),
      onSaved: (_) => widget.onSaved(_controller.text.isEmpty ? null : _controller.text),
    );
  }
}

class _TimeField extends StatefulWidget {
  final String label;
  final void Function(String?) onSaved;

  const _TimeField({required this.label, required this.onSaved});

  @override
  State<_TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<_TimeField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null && mounted) {
      setState(() => _controller.text = picked.format(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      onTap: _pick,
      decoration: InputDecoration(
        labelText: widget.label,

        suffixIcon: const Icon(Icons.access_time, size: 18),
      ),
      onSaved: (_) => widget.onSaved(_controller.text.isEmpty ? null : _controller.text),
    );
  }
}

class _DateTimeField extends StatefulWidget {
  final String label;
  final void Function(String?) onSaved;

  const _DateTimeField({required this.label, required this.onSaved});

  @override
  State<_DateTimeField> createState() => _DateTimeFieldState();
}

class _DateTimeFieldState extends State<_DateTimeField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    setState(() {
      final d =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      _controller.text = '$d ${time.format(context)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      onTap: _pick,
      decoration: InputDecoration(
        labelText: widget.label,

        suffixIcon: const Icon(Icons.calendar_today, size: 18),
      ),
      onSaved: (_) => widget.onSaved(_controller.text.isEmpty ? null : _controller.text),
    );
  }
}

class _DateRangeField extends StatefulWidget {
  final String label;
  final void Function(String?) onSaved;

  const _DateRangeField({required this.label, required this.onSaved});

  @override
  State<_DateRangeField> createState() => _DateRangeFieldState();
}

class _DateRangeFieldState extends State<_DateRangeField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: DateTime.now(),
        end: DateTime.now().add(const Duration(days: 7)),
      ),
    );
    if (range != null) {
      setState(() => _controller.text = '${_fmt(range.start)} – ${_fmt(range.end)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      readOnly: true,
      onTap: _pick,
      decoration: InputDecoration(
        labelText: widget.label,

        suffixIcon: const Icon(Icons.date_range, size: 18),
      ),
      onSaved: (_) => widget.onSaved(_controller.text.isEmpty ? null : _controller.text),
    );
  }
}

// ---------------------------------------------------------------------------
// Selection fields
// ---------------------------------------------------------------------------

class _MultiSelectField extends StatefulWidget {
  final String label;
  final List<String> options;
  final void Function(List<String>) onChanged;

  const _MultiSelectField({required this.label, required this.options, required this.onChanged});

  @override
  State<_MultiSelectField> createState() => _MultiSelectFieldState();
}

class _MultiSelectFieldState extends State<_MultiSelectField> {
  final _selected = <String>{};

  Future<void> _open() async {
    final temp = Set<String>.from(_selected);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(widget.label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.options
                .map((o) => CheckboxListTile(
                      title: Text(o),
                      value: temp.contains(o),
                      dense: true,
                      onChanged: (v) => setDialogState(() {
                        if (v == true) {
                          temp.add(o);
                        } else {
                          temp.remove(o);
                        }
                      }),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      setState(() {
        _selected.clear();
        _selected.addAll(temp);
      });
      widget.onChanged(_selected.toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
  
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 2,
          children: _selected.isEmpty
              ? [const SizedBox(height: 20)]
              : _selected
                  .map((s) => Chip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ))
                  .toList(),
        ),
      ),
    );
  }
}

class _CheckboxGroupField extends StatefulWidget {
  final String label;
  final List<String> options;
  final void Function(List<String>) onChanged;

  const _CheckboxGroupField({required this.label, required this.options, required this.onChanged});

  @override
  State<_CheckboxGroupField> createState() => _CheckboxGroupFieldState();
}

class _CheckboxGroupFieldState extends State<_CheckboxGroupField> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,

        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      child: Column(
        children: widget.options
            .map((o) => SizedBox(
                  height: 32,
                  child: CheckboxListTile(
                    title: Text(o, style: const TextStyle(fontSize: 14)),
                    value: _selected.contains(o),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selected.add(o);
                        } else {
                          _selected.remove(o);
                        }
                      });
                      widget.onChanged(_selected.toList());
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _RadioGroupField extends StatefulWidget {
  final String label;
  final List<String> options;
  final void Function(String?) onChanged;

  const _RadioGroupField({required this.label, required this.options, required this.onChanged});

  @override
  State<_RadioGroupField> createState() => _RadioGroupFieldState();
}

class _RadioGroupFieldState extends State<_RadioGroupField> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,

        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      child: Column(
        children: widget.options
            .map((o) => SizedBox(
                  height: 32,
                  child: RadioListTile<String>(
                    title: Text(o, style: const TextStyle(fontSize: 14)),
                    value: o,
                    groupValue: _selected,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) {
                      setState(() => _selected = v);
                      widget.onChanged(v);
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Boolean fields
// ---------------------------------------------------------------------------

class _CheckboxField extends StatefulWidget {
  final String label;
  final void Function(bool) onChanged;

  const _CheckboxField({required this.label, required this.onChanged});

  @override
  State<_CheckboxField> createState() => _CheckboxFieldState();
}

class _CheckboxFieldState extends State<_CheckboxField> {
  bool _value = false;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(

        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: CheckboxListTile(
        title: Text(widget.label, style: const TextStyle(fontSize: 14)),
        value: _value,
        activeColor: BootstrapTheme.of(context).colors.secondary,
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) {
          setState(() => _value = v ?? false);
          widget.onChanged(v ?? false);
        },
      ),
    );
  }
}

class _ToggleField extends StatefulWidget {
  final String label;
  final void Function(bool) onChanged;

  const _ToggleField({required this.label, required this.onChanged});

  @override
  State<_ToggleField> createState() => _ToggleFieldState();
}

class _ToggleFieldState extends State<_ToggleField> {
  bool _value = false;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(

        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: Row(
        children: [
          Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 14))),
          Switch(
            value: _value,
            activeTrackColor: BootstrapTheme.of(context).colors.secondary,
            activeColor: Colors.white,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Numeric / range fields
// ---------------------------------------------------------------------------

class _SliderField extends StatefulWidget {
  final String label;
  final double min;
  final double max;
  final void Function(double) onChanged;

  const _SliderField({
    required this.label,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_SliderField> createState() => _SliderFieldState();
}

class _SliderFieldState extends State<_SliderField> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.min;
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '${widget.label}: ${_value.toStringAsFixed(0)}',

        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      ),
      child: Slider(
        value: _value,
        min: widget.min,
        max: widget.max,
        activeColor: BootstrapTheme.of(context).colors.secondary,
        divisions: (widget.max - widget.min).round().clamp(1, 1000),
        onChanged: (v) {
          setState(() => _value = v);
          widget.onChanged(v);
        },
      ),
    );
  }
}

class _RatingField extends StatefulWidget {
  final String label;
  final int max;
  final void Function(int) onChanged;

  const _RatingField({required this.label, required this.max, required this.onChanged});

  @override
  State<_RatingField> createState() => _RatingFieldState();
}

class _RatingFieldState extends State<_RatingField> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,

        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          widget.max,
          (i) => GestureDetector(
            onTap: () {
              setState(() => _rating = i + 1);
              widget.onChanged(i + 1);
            },
            child: Icon(
              i < _rating ? Icons.star : Icons.star_border,
              color: BootstrapTheme.of(context).colors.secondary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entity Select field (ENTITY_SELECT)
// ---------------------------------------------------------------------------

class _EntitySelectField extends StatefulWidget {
  final String label;
  final String providerCode;
  final String rendererCode;
  final int? initialValue;
  final void Function(int?) onChanged;
  final void Function(int?) onSaved;

  const _EntitySelectField({
    required this.label,
    required this.providerCode,
    required this.rendererCode,
    this.initialValue,
    required this.onChanged,
    required this.onSaved,
  });

  @override
  State<_EntitySelectField> createState() => _EntitySelectFieldState();
}

class _EntitySelectFieldState extends State<_EntitySelectField> {
  final _service = AppConfigService();
  List<EntityOption> _options = [];
  int? _selectedId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialValue;
    _fetchOptions();
  }

  Future<void> _fetchOptions() async {
    if (widget.providerCode.isEmpty || widget.rendererCode.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Missing provider or renderer configuration';
      });
      return;
    }
    try {
      final options = await _service.fetchEntityOptions(
          widget.providerCode, widget.rendererCode);
      if (!mounted) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
  
        ),
        child: const SizedBox(
          height: 20,
          child: Center(child: LinearProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
  
          errorText: _error,
        ),
        child: const SizedBox.shrink(),
      );
    }

    final items = [
      const DropdownMenuItem<int>(value: null, child: Text('(none)')),
      ..._options.map((o) => DropdownMenuItem(value: o.id, child: Text(o.label))),
    ];

    return DropdownButtonFormField<int>(
      value: _options.any((o) => o.id == _selectedId) ? _selectedId : null,
      decoration: InputDecoration(
        labelText: widget.label,

      ),
      items: items,
      onChanged: (v) {
        setState(() => _selectedId = v);
        widget.onChanged(v);
      },
      onSaved: (_) => widget.onSaved(_selectedId),
    );
  }
}

// ---------------------------------------------------------------------------
// GRID field (embedded table showing related entities)
// ---------------------------------------------------------------------------

class _GridField extends StatefulWidget {
  final String label;
  final String dataFormCode;
  final String elementCode;
  final int? entityId;
  final Map<String, dynamic> formState;
  final List<GridTableColumn> tableColumns;

  const _GridField({
    required this.label,
    required this.dataFormCode,
    required this.elementCode,
    this.entityId,
    required this.formState,
    required this.tableColumns,
  });

  @override
  State<_GridField> createState() => _GridFieldState();
}

class _GridFieldState extends State<_GridField> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  int _page = 0;
  final int _pageSize = 10;
  int _totalCount = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    if (widget.entityId != null) {
      _fetchData();
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Build formState as Map<String, String> for the backend
    final formStateStrings = <String, String>{};
    for (final entry in widget.formState.entries) {
      if (entry.value != null) {
        formStateStrings[entry.key] = entry.value.toString();
      }
    }

    final body = <String, dynamic>{
      'entityId': widget.entityId,
      'formState': formStateStrings,
    };

    try {
      final uri = Uri.parse(
        'http://localhost:8080/api/view/grid-data/'
        '${widget.dataFormCode}/${widget.elementCode}'
        '?page=$_page&size=$_pageSize',
      );
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _rows = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
          _totalCount = (data['totalCount'] as num).toInt();
          _page = (data['page'] as num).toInt();
          _totalPages = (data['totalPages'] as num).toInt();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'HTTP ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).inputDecorationTheme.border
        is OutlineInputBorder
        ? (Theme.of(context).inputDecorationTheme.border as OutlineInputBorder)
            .borderSide.color
        : Colors.grey;

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel header
            Container(
              width: double.infinity,
              padding: AppTheme.panelHeaderPadding,
              decoration: BoxDecoration(
                color: AppTheme.panelHeaderBackground,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Text(widget.label, style: AppTheme.panelHeaderTitle),
                  if (!_loading && widget.entityId != null) ...[
                    const SizedBox(width: AppTheme.spacingSm),
                    Text(
                      '($_totalCount)',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                  const Spacer(),
                  if (widget.entityId != null)
                    IconButton(
                      icon: const Icon(Icons.refresh, size: AppTheme.iconSize),
                      tooltip: 'Reload',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _fetchData,
                    ),
                ],
              ),
            ),
          // Content
          if (widget.entityId == null)
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: const Text(
                'Save the record first to see related entries.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(AppTheme.spacingLg),
              child: CircularProgressIndicator(),
            ))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: AppTheme.spacingSm),
                  TextButton(onPressed: _fetchData, child: const Text('Retry')),
                ],
              ),
            )
          else if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppTheme.spacingMd),
              child: Text('No entries.', style: TextStyle(color: Colors.grey)),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: widget.tableColumns
                    .map((c) => DataColumn(label: Text(c.header)))
                    .toList(),
                rows: _rows.asMap().entries.map((entry) {
                  final index = entry.key;
                  final row = entry.value;
                  return DataRow(
                    color: AppTheme.stripeColor(index),
                    cells: widget.tableColumns
                        .map((c) => DataCell(Text('${row[c.key] ?? ''}')))
                        .toList(),
                  );
                }).toList(),
              ),
            ),
            // Pagination
            if (_totalPages > 1)
              Padding(
                padding: EdgeInsets.only(
                  top: AppTheme.spacingSm,
                  bottom: AppTheme.spacingSm,
                  right: AppTheme.spacingSm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.first_page, size: AppTheme.iconSize),
                      onPressed: _page > 0 ? () { _page = 0; _fetchData(); } : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: AppTheme.iconSize),
                      onPressed: _page > 0 ? () { _page--; _fetchData(); } : null,
                    ),
                    Text('Page ${_page + 1} of $_totalPages',
                        style: const TextStyle(fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: AppTheme.iconSize),
                      onPressed: _page < _totalPages - 1 ? () { _page++; _fetchData(); } : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.last_page, size: AppTheme.iconSize),
                      onPressed: _page < _totalPages - 1 ? () { _page = _totalPages - 1; _fetchData(); } : null,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
      ),
    );
  }
}
