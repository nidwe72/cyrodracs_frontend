import 'package:date_picker_plus/date_picker_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bootstrap5/flutter_bootstrap5.dart';
import 'package:graphql/client.dart';
import 'package:trina_grid/trina_grid.dart';
import '../app_config_editor/app_config_service.dart';
import '../graphql_client.dart';
import '../models/data_form.dart';
import '../models/data_form_element.dart';
import '../models/column_filter_meta.dart';
import '../models/editor_stack.dart';
import '../theme/app_theme.dart';
import '../widgets/filters/column_filter_input.dart';
import '../widgets/filters/debouncer.dart';
import '../widgets/grid/column_sort.dart';
import '../widgets/grid/trina_grid_adapter.dart';
import '../widgets/grid/trina_grid_theme.dart';

/// Callback for GRID add/edit actions: pushes a child editor.
typedef GridActionCallback = void Function({
  required String targetDataFormRef,
  int? entityId,
  Map<String, dynamic> contextBindings,
  String? childLabel,
  String? sourceElementCode,
});

/// Callback for GRID delete actions.
typedef GridDeleteCallback = Future<bool> Function({
  required String dataFormCode,
  required String elementCode,
  required int entityId,
});

class FormRendererView extends StatefulWidget {
  final DataForm form;
  final int? entityId;
  final Map<String, dynamic>? initialValues;
  final VoidCallback? onSaved;
  /// Called before persistence with the form values and display-friendly values.
  /// Return true to proceed with normal persistence, false to skip (caller handles it).
  final Future<bool> Function(Map<String, dynamic> values, Map<String, dynamic> displayValues)? onBeforeSave;
  /// Context bindings from EditorStack: field code → resolved value.
  /// Fields present here are rendered as read-only.
  final Map<String, dynamic> contextBindings;
  /// Callback to push a child editor from a GRID add/edit action.
  final GridActionCallback? onGridAction;
  /// Callback to delete a GRID row entity.
  final GridDeleteCallback? onGridDelete;
  /// Called whenever a form field value changes. Used to keep EditorFrame.formState up to date.
  final void Function(Map<String, dynamic> values)? onValuesChanged;
  /// Pending children grouped by source element code. Used when parent has no ID.
  final Map<String, List<PendingChild>> pendingChildrenByElement;
  /// Callback to remove a pending child by element code and index.
  final void Function(String elementCode, int index)? onRemovePending;

  const FormRendererView({
    super.key,
    required this.form,
    this.entityId,
    this.initialValues,
    this.onSaved,
    this.onBeforeSave,
    this.contextBindings = const {},
    this.onGridAction,
    this.onGridDelete,
    this.onValuesChanged,
    this.pendingChildrenByElement = const {},
    this.onRemovePending,
  });

  @override
  State<FormRendererView> createState() => _FormRendererViewState();
}

class _FormRendererViewState extends State<FormRendererView> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  final Map<String, String> _displayLabels = {}; // entity select labels for display
  final Map<String, int> _reloadCounters = {}; // per-element reload counter for forcing rebuilds
  final Map<String, ElementState> _elementStates = {}; // central element state from evaluate endpoint
  String? _submitResult;

  void _updateValue(String key, dynamic value) {
    _values[key] = value;
    // Reset dependent elements that declare reloadOnChangeOf this key
    final hasDependents = widget.form.elements.any((e) => e.reloadOnChangeOf.contains(key));
    if (hasDependents) {
      for (final e in widget.form.elements) {
        if (e.reloadOnChangeOf.contains(key)) {
          _values[e.key] = null;
          _displayLabels.remove(e.key);
        }
      }
      _evaluateForm(changedElement: key);
    }
    setState(() {});
    widget.onValuesChanged?.call(Map<String, dynamic>.from(_values));
  }

  Future<void> _evaluateForm({String? changedElement}) async {
    final formCode = widget.form.code;
    if (formCode == null) return;
    try {
      final service = AppConfigService();
      final states = await service.fetchFormEvaluation(
        dataFormCode: formCode,
        entityId: widget.entityId,
        changedElement: changedElement,
        formState: _buildFormState(),
      );
      if (!mounted) return;
      setState(() {
        _elementStates.addAll(states);
        // Bump reload counters for elements whose options changed
        for (final entry in states.entries) {
          if (entry.value.options != null) {
            _reloadCounters[entry.key] = (_reloadCounters[entry.key] ?? 0) + 1;
          }
        }
      });
    } catch (_) {
      // Silently ignore evaluation errors — form remains functional
    }
  }

  /// Converts _values to Map<String, String> for the backend POST endpoint.
  /// Uses dataBinding paths as keys (JPA field names) instead of element keys.
  Map<String, String> _buildFormState() {
    final result = <String, String>{};
    for (final entry in _values.entries) {
      if (entry.value != null) {
        // Resolve the dataBinding path for this element key
        final element = widget.form.elements
            .where((e) => e.key == entry.key)
            .firstOrNull;
        final key = element?.dataBinding ?? entry.key;
        result[key] = entry.value.toString();
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValues;
    for (final e in widget.form.elements) {
      // Context-bound fields get their value from the binding, overriding initial
      if (widget.contextBindings.containsKey(e.key)) {
        _values[e.key] = widget.contextBindings[e.key];
      } else if (initial != null && initial.containsKey(e.key)) {
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
    // Initial evaluation: determine visibility and options for all elements.
    // Deferred to after first frame to avoid setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _evaluateForm();
    });
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

    // Check if caller wants to intercept (e.g., collect as pending instead of persisting)
    if (widget.onBeforeSave != null) {
      final shouldPersist = await widget.onBeforeSave!(filteredValues, Map<String, String>.from(_displayLabels));
      if (!shouldPersist) return; // Caller handled it
    }

    // Collect all pending children from all elements
    final allPending = <Map<String, dynamic>>[];
    for (final entry in widget.pendingChildrenByElement.entries) {
      for (final pending in entry.value) {
        allPending.add(pending.toJson());
      }
    }

    final body = <String, dynamic>{
      'dataFormCode': widget.form.code,
      'values': filteredValues,
      if (widget.entityId != null) 'entityId': widget.entityId,
      if (allPending.isNotEmpty) 'pendingChildren': allPending,
    };
    try {
      final result = await graphqlClient.mutate(MutationOptions(
        document: gql(r'''
          mutation SaveFormData($input: DataFormDataInput!) {
            saveDataFormData(input: $input) {
              success error data { entityId }
            }
          }
        '''),
        variables: {'input': body},
        fetchPolicy: FetchPolicy.noCache,
      ));
      if (result.hasException) throw result.exception!;
      final saveResult = result.data!['saveDataFormData'] as Map<String, dynamic>;
      if (saveResult['success'] == true) {
        final entityId = (saveResult['data'] as Map<String, dynamic>?)?['entityId'];
        setState(() {
          _submitResult = 'Saved entity (id=$entityId)\n'
              '${filteredValues.entries.map((e) => '${e.key}: ${e.value ?? '-'}').join('\n')}';
        });
        widget.onSaved?.call();
      } else {
        setState(() => _submitResult = 'Error: ${saveResult['error'] ?? 'Unknown error'}');
      }
    } catch (e) {
      setState(() => _submitResult = 'Error: $e');
    }
  }

  bool _isElementVisible(DataFormElement e) {
    final state = _elementStates[e.key];
    if (state == null) return true; // no state = visible by default
    return state.visible;
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    var group = <DataFormElement>[];
    for (final e in widget.form.elements) {
      if (!_isElementVisible(e)) continue; // skip hidden elements
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
    // Context-bound fields are rendered as read-only
    final isBound = widget.contextBindings.containsKey(e.key);
    if (isBound) {
      final boundValue = widget.contextBindings[e.key];
      if (boundValue == null) {
        // Parent has no ID yet — show placeholder
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
            initialValue: '(will be assigned on save)',
            decoration: InputDecoration(
              labelText: e.label,
              suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
            ),
            enabled: false,
          ),
        );
      }
      if (e.type == DataFormElementType.entitySelect) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _EntitySelectField(
            label: e.label,
            providerCode: e.entityProviderRef ?? '',
            rendererCode: e.entityRendererRef ?? '',
            initialValue: int.tryParse(boundValue.toString()),
            onChanged: (_) {},
            onSaved: (_) {},
            readOnly: true,
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          initialValue: boundValue.toString(),
          decoration: InputDecoration(
            labelText: e.label,
            suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
          ),
          enabled: false,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: switch (e.type) {
        DataFormElementType.inputString => TextFormField(
            initialValue: _values[e.key]?.toString(),
            decoration: InputDecoration(labelText: e.label),
            onChanged: (v) => _updateValue(e.key, v),
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.inputNumber => TextFormField(
            decoration: InputDecoration(labelText: e.label),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSaved: (v) => _values[e.key] = v == null || v.isEmpty ? null : double.tryParse(v),
          ),
        DataFormElementType.inputEmail => TextFormField(
            decoration: InputDecoration(labelText: e.label),
            keyboardType: TextInputType.emailAddress,
            onChanged: (v) => _updateValue(e.key, v),
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.inputPassword => _PasswordField(
            label: e.label,
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.textarea => TextFormField(
            decoration: InputDecoration(
              labelText: e.label,
      
              alignLabelWithHint: true,
            ),
            maxLines: e.rows ?? 3,
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.select => DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: e.label),
            items: e.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) => _updateValue(e.key, v),
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.multiSelect => _MultiSelectField(
            label: e.label,
            options: e.options,
            onChanged: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.checkboxGroup => _CheckboxGroupField(
            label: e.label,
            options: e.options,
            onChanged: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.radioGroup => _RadioGroupField(
            label: e.label,
            options: e.options,
            onChanged: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.checkbox => _CheckboxField(
            label: e.label,
            onChanged: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.toggle => _ToggleField(
            label: e.label,
            onChanged: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.datePicker => _DateField(
            label: e.label,
            initialValue: _values[e.key]?.toString(),
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.timePicker => _TimeField(
            label: e.label,
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.dateTimePicker => _DateTimeField(
            label: e.label,
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.dateRangePicker => _DateRangeField(
            label: e.label,
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.slider => _SliderField(
            label: e.label,
            min: e.min ?? 0.0,
            max: e.max ?? 100.0,
            onChanged: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.rating => _RatingField(
            label: e.label,
            max: e.max?.toInt() ?? 5,
            onChanged: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.datePickerYearMonth => _YearMonthField(
            label: e.label,
            initialValue: _values[e.key]?.toString(),
            onSaved: (v) => _updateValue(e.key, v),
          ),
        DataFormElementType.entitySelect => _EntitySelectField(
            key: ValueKey('${e.key}_${_reloadCounters[e.key] ?? 0}'),
            label: e.label,
            providerCode: e.entityProviderRef ?? '',
            rendererCode: e.entityRendererRef ?? '',
            initialValue: _values[e.key] != null
                ? int.tryParse(_values[e.key].toString())
                : null,
            onChanged: (v) => _updateValue(e.key, v),
            onSaved: (v) => _updateValue(e.key, v),
            onLabelChanged: (label) => _displayLabels[e.key] = label,
            dataFormCode: widget.form.code,
            entityId: widget.entityId,
            formState: _buildFormState(),
            preloadedOptions: _elementStates[e.key]?.options,
          ),
        DataFormElementType.grid => _GridField(
            label: e.label,
            dataFormCode: widget.form.code ?? '',
            elementCode: e.key,
            entityId: widget.entityId,
            formState: _values,
            tableColumns: e.tableColumns,
            addAction: e.addAction,
            onAddAction: widget.onGridAction != null && e.addAction != null
                ? () {
                    final action = e.addAction!;
                    // Resolve context bindings: ENTITY → parent entity ID
                    final resolved = <String, dynamic>{};
                    for (final b in action.contextBindings) {
                      if (b.source == 'ENTITY') {
                        resolved[b.target] = widget.entityId;
                      }
                      // Future: ENTITY.fieldPath support
                    }
                    widget.onGridAction!(
                      targetDataFormRef: action.targetDataFormRef,
                      contextBindings: resolved,
                      childLabel: action.childLabel != null
                          ? 'New ${action.childLabel}'
                          : null,
                      sourceElementCode: e.key,
                    );
                  }
                : null,
            onEditAction: widget.onGridAction != null && e.addAction != null
                ? (int rowEntityId) {
                    final action = e.addAction!;
                    final resolved = <String, dynamic>{};
                    for (final b in action.contextBindings) {
                      if (b.source == 'ENTITY') {
                        resolved[b.target] = widget.entityId;
                      }
                    }
                    widget.onGridAction!(
                      targetDataFormRef: action.targetDataFormRef,
                      entityId: rowEntityId,
                      contextBindings: resolved,
                      childLabel: action.childLabel,
                      sourceElementCode: e.key,
                    );
                  }
                : null,
            onDeleteAction: widget.onGridDelete != null
                ? (int rowEntityId) async {
                    final success = await widget.onGridDelete!(
                      dataFormCode: widget.form.code ?? '',
                      elementCode: e.key,
                      entityId: rowEntityId,
                    );
                    return success;
                  }
                : null,
            pendingRows: widget.pendingChildrenByElement[e.key] ?? const [],
            onRemovePending: widget.onRemovePending != null
                ? (int index) => widget.onRemovePending!(e.key, index)
                : null,
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
  final bool readOnly;
  final void Function(String label)? onLabelChanged;
  final String? dataFormCode;
  final int? entityId;
  final Map<String, String>? formState;
  final List<EntityOption>? preloadedOptions;

  const _EntitySelectField({
    super.key,
    required this.label,
    required this.providerCode,
    required this.rendererCode,
    this.initialValue,
    required this.onChanged,
    required this.onSaved,
    this.readOnly = false,
    this.onLabelChanged,
    this.dataFormCode,
    this.entityId,
    this.formState,
    this.preloadedOptions,
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
    if (widget.preloadedOptions != null) {
      _options = widget.preloadedOptions!;
      _loading = false;
    } else {
      _fetchOptions();
    }
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

    if (widget.readOnly) {
      final selectedLabel = _options
          .where((o) => o.id == _selectedId)
          .map((o) => o.label)
          .firstOrNull ?? '(none)';
      return TextFormField(
        initialValue: selectedLabel,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
        ),
        enabled: false,
      );
    }

    return DropdownButtonFormField<int>(
      value: _options.any((o) => o.id == _selectedId) ? _selectedId : null,
      decoration: InputDecoration(
        labelText: widget.label,

      ),
      items: items,
      onChanged: (v) {
        setState(() => _selectedId = v);
        widget.onChanged(v);
        if (v != null && widget.onLabelChanged != null) {
          final match = _options.where((o) => o.id == v).firstOrNull;
          if (match != null) widget.onLabelChanged!(match.label);
        }
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
  final AddActionConfig? addAction;
  final VoidCallback? onAddAction;
  final void Function(int entityId)? onEditAction;
  final Future<bool> Function(int entityId)? onDeleteAction;
  final List<PendingChild> pendingRows;
  final void Function(int index)? onRemovePending;

  const _GridField({
    required this.label,
    required this.dataFormCode,
    required this.elementCode,
    this.entityId,
    required this.formState,
    required this.tableColumns,
    this.addAction,
    this.onAddAction,
    this.onEditAction,
    this.onDeleteAction,
    this.pendingRows = const [],
    this.onRemovePending,
  });

  @override
  State<_GridField> createState() => _GridFieldState();
}

class _GridFieldState extends State<_GridField> {
  bool _loading = false;
  String? _error;
  // Backend baseline count: rows matching the effective filter with the
  // userFilter stripped. Drives the (N of M) row-count badge per
  // gridElement.md G1.6.9. The visible-count side of the badge reads
  // _trinaRows.length directly (embedded GRIDs fetch all rows — no
  // pagination per G1.6.8 — so totalCount and items.length agree).
  int _baselineTotal = 0;

  // Per-column sort state (single column, replaces provider sortFields).
  String? _sortColumnKey;
  SortDirection? _sortDirection;

  // Column-filter state. Metadata fetched once on mount; controllers persist
  // across rebuilds so TextField focus is preserved during typing.
  Map<String, ColumnFilterMeta> _columnMeta = const {};
  final Map<String, dynamic> _columnFilters = {};
  final Map<String, TextEditingController> _filterControllers = {};
  final Debouncer _filterDebouncer = Debouncer();
  int _fetchSeq = 0;

  // TrinaGrid integration. Same pattern as `app_view.dart` ENTITY_LIST:
  // rows pushed via `rows` prop, generation key forces remount per fetch
  // (rationale documented in `app_view.dart`). Reactive header (sort glyph,
  // filter input) refreshes via the GridRebuildTrigger.
  List<TrinaRow> _trinaRows = const [];
  int _gridGeneration = 0;
  final GridRebuildTrigger _gridRebuildTrigger = GridRebuildTrigger();

  // G7.8 — Pending-row dot-path resolution cache. Keyed by
  // pendingRowIndex → columnKey → leafId / display string. Populated lazily
  // when new pending rows appear (didUpdateWidget); dropped when pending
  // rows are removed. Filter / sort / display read via _effectiveValue and
  // _effectiveDisplay helpers.
  final Map<int, Map<String, dynamic>> _pendingDotPathValues = {};
  final Map<int, Map<String, String>> _pendingDotPathDisplays = {};
  int _dotPathFetchSeq = 0;

  @override
  void dispose() {
    for (final c in _filterControllers.values) {
      c.dispose();
    }
    _filterDebouncer.dispose();
    _gridRebuildTrigger.dispose();
    super.dispose();
  }

  /// Builds TrinaRows for pending children (un-saved entries), tagging
  /// each with metadata so the cell renderer knows to apply the
  /// pending styling (italic text, amber background, pending badge on
  /// the first cell of the first row, remove icon instead of edit/delete).
  ///
  /// Pending rows are subject to the same column-filter predicates as
  /// committed rows, evaluated client-side per columnFilters.md CF1.5.1,
  /// and reordered by the active sort per CF2.5. Dot-path column values
  /// (e.g. `cameraLensMount.producer`) come from the G7.8 resolution
  /// cache populated lazily on pending-row addition. The original index
  /// is preserved on each surviving row so the "remove pending" action
  /// keeps targeting the right entry — `MapEntry.key` carries it
  /// through both filter and sort steps.
  List<TrinaRow> _buildPendingTrinaRows() {
    final fieldKeys = widget.tableColumns.map((c) => c.key).toList();
    final filtered = widget.pendingRows
        .asMap()
        .entries
        .where((entry) => _pendingMatchesFilters(entry.key, entry.value))
        .toList();
    final cmp = _comparatorForActiveSort();
    if (cmp != null) {
      filtered.sort(cmp);
    }
    return filtered.map((entry) {
      final i = entry.key;
      final pending = entry.value;
      final entityForRow = <String, dynamic>{};
      for (final key in fieldKeys) {
        entityForRow[key] = _effectiveDisplay(i, pending, key);
      }
      return buildTrinaRow(
        entity: entityForRow,
        fieldKeys: fieldKeys,
        metadata: {'pending': true, 'pendingIndex': i},
      );
    }).toList();
  }

  /// G7.8 — effective value for filter / sort: cached dot-path
  /// resolution if `columnKey` is a dot-path, else the direct field
  /// value from `pending.values`. Returns null when the cache hasn't
  /// resolved yet OR the row legitimately has no value at this key.
  dynamic _effectiveValue(int pendingIndex, PendingChild pending, String columnKey) {
    if (columnKey.contains('.')) {
      return _pendingDotPathValues[pendingIndex]?[columnKey];
    }
    return pending.values[columnKey];
  }

  /// G7.8 — effective display string for cell rendering: cached
  /// dot-path display if `columnKey` is a dot-path, else
  /// `pending.displayValues[k] ?? pending.values[k]` (direct columns
  /// already have a display string captured at child-editor save time).
  dynamic _effectiveDisplay(int pendingIndex, PendingChild pending, String columnKey) {
    if (columnKey.contains('.')) {
      return _pendingDotPathDisplays[pendingIndex]?[columnKey];
    }
    return pending.displayValues[columnKey] ?? pending.values[columnKey];
  }

  /// CF2.5 — Comparator for the currently-active sort column / direction,
  /// or null when no sort is active (rows render in insertion order).
  /// Null cell values land last under ASC, first under DESC per CF2.5.2.
  /// Dot-path column values come from the G7.8 resolution cache via
  /// [_effectiveValue]; the comparator therefore takes
  /// `MapEntry<int, PendingChild>` so it has both the index (for cache
  /// lookup) and the row.
  Comparator<MapEntry<int, PendingChild>>? _comparatorForActiveSort() {
    final colKey = _sortColumnKey;
    final dir = _sortDirection;
    if (colKey == null || dir == null) return null;
    final meta = _columnMeta[colKey];
    if (meta == null) return null;
    final ascending = dir == SortDirection.asc;
    return (a, b) {
      final va = _effectiveValue(a.key, a.value, colKey);
      final vb = _effectiveValue(b.key, b.value, colKey);
      if (va == null && vb == null) return 0;
      if (va == null) return ascending ? 1 : -1;
      if (vb == null) return ascending ? -1 : 1;
      final base = _compareNonNull(va, vb, meta.filterType);
      return ascending ? base : -base;
    };
  }

  /// G7.8 — fetches dot-path resolutions for the given pending rows.
  /// One batched POST that covers all (pendingRowIndex × dot-path column)
  /// combinations. Cache is updated on response; out-of-date responses
  /// (sequence-number stale) are silently discarded.
  Future<void> _fetchDotPathResolutionsForPending(List<int> pendingIndices) async {
    if (pendingIndices.isEmpty) return;
    if (widget.dataFormCode.isEmpty || widget.elementCode.isEmpty) return;

    // Identify the dot-path columns we need to resolve. We only resolve
    // columns whose key contains a dot — direct-column display values are
    // already captured at child-editor save time.
    final dotPathColumns = <Map<String, dynamic>>[];
    for (final col in widget.tableColumns) {
      if (!col.key.contains('.')) continue;
      dotPathColumns.add({
        'columnKey': col.key,
        if (col.entityRendererRef != null) 'rendererRef': col.entityRendererRef,
      });
    }
    if (dotPathColumns.isEmpty) return;

    // Build directValues from the requested pending rows. For each row,
    // include all direct-field entries with non-null IDs. The backend uses
    // the column's first-segment to pick the right entry.
    final directValues = <Map<String, dynamic>>[];
    for (final i in pendingIndices) {
      if (i >= widget.pendingRows.length) continue;
      final p = widget.pendingRows[i];
      for (final entry in p.values.entries) {
        if (entry.key.contains('.')) continue;        // skip dot-path keys
        final v = entry.value;
        if (v == null) continue;
        final n = v is num ? v.toInt() : int.tryParse(v.toString());
        if (n == null) continue;
        directValues.add({
          'pendingRowIndex': i,
          'fieldName': entry.key,
          'id': n,
        });
      }
    }
    if (directValues.isEmpty) return;

    final mySeq = ++_dotPathFetchSeq;
    try {
      final result = await graphqlClient.query(QueryOptions(
        document: gql(r'''
          query ResolveDotPathValues($input: ResolveDotPathValuesInput!) {
            resolveDotPathValues(input: $input) {
              pendingRowIndex columnKey leafId displayValue
            }
          }
        '''),
        variables: {
          'input': {
            'dataFormCode': widget.dataFormCode,
            'elementCode': widget.elementCode,
            'directValues': directValues,
            'dotPathColumns': dotPathColumns,
          },
        },
        fetchPolicy: FetchPolicy.noCache,
      ));
      if (mySeq != _dotPathFetchSeq || !mounted) return;
      if (result.hasException) {
        debugPrint('[G7.8] resolveDotPathValues failed: ${result.exception}');
        return;
      }
      final entries = (result.data!['resolveDotPathValues'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      setState(() {
        for (final e in entries) {
          final idx = (e['pendingRowIndex'] as num).toInt();
          final colKey = e['columnKey'] as String;
          final leafId = e['leafId'];
          final display = e['displayValue'] as String?;
          _pendingDotPathValues.putIfAbsent(idx, () => {})[colKey] =
              leafId is num ? leafId.toInt() : leafId;
          if (display != null) {
            _pendingDotPathDisplays.putIfAbsent(idx, () => {})[colKey] = display;
          }
        }
        _gridGeneration++;     // remount TrinaGrid with newly-populated cells
      });
    } catch (e, st) {
      debugPrint('[G7.8] resolveDotPathValues error: $e\n$st');
    }
  }

  /// CF2.5.1 — per-type comparator on non-null cell values, mirroring
  /// the server's ORDER BY semantics for each ColumnFilterType.
  static int _compareNonNull(
      dynamic va, dynamic vb, ColumnFilterType type) {
    switch (type) {
      case ColumnFilterType.string:
        return va
            .toString()
            .toLowerCase()
            .compareTo(vb.toString().toLowerCase());
      case ColumnFilterType.number:
      case ColumnFilterType.entityRef:
        final na = va is num ? va : num.tryParse(va.toString()) ?? 0;
        final nb = vb is num ? vb : num.tryParse(vb.toString()) ?? 0;
        return na.compareTo(nb);
      case ColumnFilterType.date:
      case ColumnFilterType.yearMonth:
      case ColumnFilterType.datetime:
        // ISO date / yearMonth strings sort lexicographically; same trick
        // the backend's ORDER BY relies on for these column types.
        return va.toString().compareTo(vb.toString());
      case ColumnFilterType.boolean:
        final ba = va is bool
            ? va
            : va.toString().toLowerCase() == 'true';
        final bb = vb is bool
            ? vb
            : vb.toString().toLowerCase() == 'true';
        if (ba == bb) return 0;
        return ba ? 1 : -1;          // false < true
      case ColumnFilterType.entityEnum:
        return va.toString().compareTo(vb.toString());
      default:
        return 0;
    }
  }

  /// True iff the pending row passes every active column filter,
  /// matching server-side predicate semantics (columnFilters.md CF1.5.1).
  /// Missing values fail the predicate (mirrors SQL's NULL-LIKE-anything
  /// → UNKNOWN → false). Dot-path column values come from the G7.8
  /// resolution cache via [_effectiveValue].
  bool _pendingMatchesFilters(int pendingIndex, PendingChild pending) {
    for (final entry in _columnFilters.entries) {
      final key = entry.key;
      final filterValue = entry.value;
      final meta = _columnMeta[key];
      if (meta == null) continue;
      final cellValue = _effectiveValue(pendingIndex, pending, key);
      if (!_cellMatchesFilter(cellValue, filterValue, meta.filterType)) {
        return false;
      }
    }
    return true;
  }

  bool _cellMatchesFilter(
      dynamic cellValue, dynamic filterValue, ColumnFilterType type) {
    switch (type) {
      case ColumnFilterType.string:
        if (filterValue is! String || filterValue.isEmpty) return true;
        if (cellValue == null) return false;
        return cellValue
            .toString()
            .toLowerCase()
            .contains(filterValue.toLowerCase());
      case ColumnFilterType.number:
        return _matchesNumberRange(cellValue, filterValue);
      case ColumnFilterType.date:
      case ColumnFilterType.yearMonth:
      case ColumnFilterType.datetime:
        return _matchesStringRange(cellValue, filterValue);
      case ColumnFilterType.boolean:
        if (filterValue is! bool) return true;
        if (cellValue == null) return false;
        if (cellValue is bool) return cellValue == filterValue;
        final s = cellValue.toString().toLowerCase();
        return (filterValue ? s == 'true' : s == 'false');
      case ColumnFilterType.entityEnum:
        if (filterValue is! String || filterValue.isEmpty) return true;
        if (cellValue == null) return false;
        return cellValue.toString() == filterValue;
      case ColumnFilterType.entityRef:
        if (filterValue is! Map || filterValue['id'] == null) return true;
        if (cellValue == null) return false;
        return cellValue.toString() == filterValue['id'].toString();
      default:
        return true;
    }
  }

  bool _matchesNumberRange(dynamic cellValue, dynamic filterValue) {
    if (filterValue is! Map) return true;
    final fromStr = filterValue['from'];
    final toStr = filterValue['to'];
    final hasFrom = fromStr is String && fromStr.isNotEmpty;
    final hasTo = toStr is String && toStr.isNotEmpty;
    if (!hasFrom && !hasTo) return true;
    if (cellValue == null) return false;
    final cellNum = cellValue is num
        ? cellValue
        : num.tryParse(cellValue.toString());
    if (cellNum == null) return false;
    if (hasFrom) {
      final from = num.tryParse(fromStr);
      if (from != null && cellNum < from) return false;
    }
    if (hasTo) {
      final to = num.tryParse(toStr);
      if (to != null && cellNum > to) return false;
    }
    return true;
  }

  bool _matchesStringRange(dynamic cellValue, dynamic filterValue) {
    // ISO date / yearMonth strings sort lexicographically — same trick
    // the backend relies on for these column types.
    if (filterValue is! Map) return true;
    final from = filterValue['from'];
    final to = filterValue['to'];
    final hasFrom = from is String && from.isNotEmpty;
    final hasTo = to is String && to.isNotEmpty;
    if (!hasFrom && !hasTo) return true;
    if (cellValue == null) return false;
    final cellStr = cellValue.toString();
    if (hasFrom && cellStr.compareTo(from) < 0) return false;
    if (hasTo && cellStr.compareTo(to) > 0) return false;
    return true;
  }

  /// Effective rows for the GRID — pending when the parent isn't saved
  /// yet, committed otherwise. Mutually exclusive in current behaviour.
  List<TrinaRow> _effectiveRows() {
    if (widget.entityId == null) {
      return _buildPendingTrinaRows();
    }
    return _trinaRows.toList();
  }

  Color _rowColor(TrinaRowColorContext ctx) {
    if (ctx.row.metadata?['pending'] == true) {
      return Colors.amber.shade50;
    }
    // Preserve zebra striping for committed rows — rowColorCallback
    // overrides TrinaGridStyleConfig.evenRowColor / oddRowColor, so we
    // re-implement the alternation here. First row (rowIdx 0) white,
    // second row tinted, matching the ENTITY_LIST surface.
    return ctx.rowIdx.isEven ? Colors.white : AppTheme.tableStripeColor;
  }

  Future<void> _confirmDelete(int rowId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm delete'),
        content: const Text('Remove this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && widget.onDeleteAction != null) {
      final success = await widget.onDeleteAction!(rowId);
      if (success) _fetchData();
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchColumnMeta();
    if (widget.entityId != null) {
      _fetchData();
    }
    // G7.8 — resolve dot-paths for any pending rows already present at
    // mount time (rare but possible: navigating away from the GRID and
    // back while the parent is still unsaved would re-mount with pending
    // rows already in widget.pendingRows).
    if (widget.pendingRows.isNotEmpty) {
      _fetchDotPathResolutionsForPending(
          [for (int i = 0; i < widget.pendingRows.length; i++) i]);
    }
  }

  @override
  void didUpdateWidget(_GridField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pending rows are owned by the parent; when its list grows or shrinks
    // (Add / Remove pending), bump the generation so the keyed TrinaGrid
    // remounts with the fresh row set, AND fire the rebuild trigger so any
    // open ENTITY_REF picker dismisses (CF3.4.4 *Open-picker invalidation*
    // — pending list mutation changes the candidate set).
    final oldLen = oldWidget.pendingRows.length;
    final newLen = widget.pendingRows.length;
    if (oldLen != newLen) {
      setState(() => _gridGeneration++);
      _gridRebuildTrigger.bump();
      // G7.8 — handle the cache for added vs removed indices.
      if (newLen > oldLen) {
        // New pending rows appeared at the end (the typical case — child
        // editor save appends). Fetch dot-path resolutions for them.
        final newIndices = [for (int i = oldLen; i < newLen; i++) i];
        _fetchDotPathResolutionsForPending(newIndices);
      } else {
        // Pending row(s) removed — drop cache entries beyond the new length.
        // Indices for surviving rows stay valid (removal happens at the end
        // in current behaviour; if mid-list removal becomes possible, this
        // logic would need reconsidering).
        for (int i = newLen; i < oldLen; i++) {
          _pendingDotPathValues.remove(i);
          _pendingDotPathDisplays.remove(i);
        }
      }
    }
  }

  Future<void> _fetchColumnMeta() async {
    try {
      final result = await graphqlClient.query(QueryOptions(
        document: gql(r'''
          query ColumnFilterMetadata($scope: ColumnFilterScopeInput!) {
            columnFilterMetadata(scope: $scope) {
              columnKey filterType entityProviderRef entityRendererRef enumValues restrictByVisibleRows
            }
          }
        '''),
        variables: {
          'scope': {
            'dataFormCode': widget.dataFormCode,
            'elementCode': widget.elementCode,
          },
        },
        fetchPolicy: FetchPolicy.noCache,
      ));
      if (result.hasException) throw result.exception!;
      final list = (result.data!['columnFilterMetadata'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      debugPrint('[columnFilterMetadata GRID] dataFormCode=${widget.dataFormCode} '
          'elementCode=${widget.elementCode} → ${list.length} entries: '
          '${list.map((m) => "${m['columnKey']}=${m['filterType']}").join(', ')}');
      debugPrint('[columnFilterMetadata GRID] frontend column keys: '
          '${widget.tableColumns.map((c) => c.key).join(", ")}');
      final next = <String, ColumnFilterMeta>{};
      for (final m in list) {
        final meta = ColumnFilterMeta.fromJson(m);
        next[meta.columnKey] = meta;
      }
      if (!mounted) return;
      setState(() => _columnMeta = next);
    } catch (e, st) {
      debugPrint('[columnFilterMetadata GRID] FAILED for '
          '${widget.dataFormCode}/${widget.elementCode}: $e\n$st');
      if (!mounted) return;
      setState(() => _columnMeta = const {});
    }
  }

  Map<String, dynamic>? _composeUserFilter() {
    final children = <Map<String, dynamic>>[];
    for (final entry in _columnFilters.entries) {
      final meta = _columnMeta[entry.key];
      if (meta == null) continue;
      final value = entry.value;
      switch (meta.filterType) {
        case ColumnFilterType.string:
          if (value is String && value.isNotEmpty) {
            children.add({
              'type': 'COMPARISON',
              'field': entry.key,
              'operator': 'LIKE',
              'value': '%$value%',
            });
          }
          break;
        case ColumnFilterType.number:
        case ColumnFilterType.date:
        case ColumnFilterType.yearMonth:
        case ColumnFilterType.datetime:
          if (value is Map) {
            final from = value['from'];
            final to = value['to'];
            if (from is String && from.isNotEmpty) {
              children.add({
                'type': 'COMPARISON',
                'field': entry.key,
                'operator': 'GREATER_THAN_OR_EQUAL',
                'value': from,
              });
            }
            if (to is String && to.isNotEmpty) {
              children.add({
                'type': 'COMPARISON',
                'field': entry.key,
                'operator': 'LESS_THAN_OR_EQUAL',
                'value': to,
              });
            }
          }
          break;
        case ColumnFilterType.boolean:
          if (value is bool) {
            children.add({
              'type': 'COMPARISON',
              'field': entry.key,
              'operator': 'EQUALS',
              'value': value ? 'true' : 'false',
            });
          }
          break;
        case ColumnFilterType.entityEnum:
          if (value is String && value.isNotEmpty) {
            children.add({
              'type': 'COMPARISON',
              'field': entry.key,
              'operator': 'EQUALS',
              'value': value,
            });
          }
          break;
        case ColumnFilterType.entityRef:
          if (value is Map && value['id'] != null) {
            children.add({
              'type': 'COMPARISON',
              'field': '${entry.key}.id',
              'operator': 'EQUALS',
              'value': value['id'].toString(),
            });
          }
          break;
        default:
          break;
      }
    }
    if (children.isEmpty) return null;
    return {'type': 'AND_GROUP', 'children': children};
  }

  bool get _hasActiveFilters => _columnFilters.values.any((v) {
        if (v is String) return v.isNotEmpty;
        return v != null;
      });

  void _onColumnFilterChanged(String columnKey, dynamic value) {
    setState(() {
      if (value == null || (value is String && value.isEmpty)) {
        _columnFilters.remove(columnKey);
      } else {
        _columnFilters[columnKey] = value;
      }
    });
    _gridRebuildTrigger.bump();
    _refreshAfterFilterOrSortChange();
  }

  void _clearColumnFilters() {
    if (_columnFilters.isEmpty) return;
    for (final controller in _filterControllers.values) {
      controller.clear();
    }
    setState(() {
      _columnFilters.clear();
    });
    _gridRebuildTrigger.bump();
    _refreshAfterFilterOrSortChange();
  }

  /// In edit mode, refetch from the backend (the userFilter / userSort just
  /// changed). In create-new mode there is no backend query (entityId is
  /// null and the GraphQL schema rejects null entityId); just bump the
  /// generation so the keyed TrinaGrid remounts with the freshly-filtered
  /// pending rows from `_effectiveRows()`. Per columnFilters.md CF1.5.1 the
  /// pending-row filter is purely client-side — no round-trip needed.
  void _refreshAfterFilterOrSortChange() {
    if (widget.entityId != null) {
      _fetchData();
    } else {
      setState(() => _gridGeneration++);
    }
  }

  TextEditingController _ensureController(String columnKey, [String subkey = '']) {
    return _filterControllers.putIfAbsent(
        '$columnKey:$subkey', () => TextEditingController());
  }

  Widget? _buildFilterInputFor(GridTableColumn col) {
    final meta = _columnMeta[col.key];
    if (meta == null) return null;
    return buildColumnFilterInput(
      meta: meta,
      currentValue: _columnFilters[col.key],
      acquireController: (subkey) => _ensureController(col.key, subkey),
      debouncer: _filterDebouncer,
      onChanged: _onColumnFilterChanged,
      dataFormCode: widget.dataFormCode,
      elementCode: widget.elementCode,
      // CF3.4.3 — pass user-filter tree, parent editor entity, and the
      // dismiss trigger so the picker can run the inner DISTINCT correctly
      // and close on other-column filter changes.
      userFilter: _composeUserFilter(),
      editorEntityId: widget.entityId,
      dismissTrigger: _gridRebuildTrigger,
      // CF3.4.4 — pending rows' direct ENTITY_REF field values augment
      // the picker's candidate set in create-new mode. Computed once
      // per build, reused across all pickers on this GRID.
      pendingRowDirectValues: _pendingRowDirectValues(),
      // CF3.4.6 — pending rows' direct ENUM field values augment the
      // dropdown options in create-new mode.
      pendingRowEnumValues: _pendingRowEnumValues(),
    );
  }

  /// CF3.4.4 — collects, for each direct ENTITY_REF column on the row
  /// entity, the IDs the pending rows reference at that field. Drops
  /// nulls, dedupes locally. Returns an empty list when no pending rows
  /// or no direct ENTITY_REF columns exist; the picker treats null/empty
  /// the same way (no augmentation).
  List<Map<String, dynamic>> _pendingRowDirectValues() {
    if (widget.pendingRows.isEmpty) return const [];
    final result = <Map<String, dynamic>>[];
    for (final entry in _columnMeta.entries) {
      final key = entry.key;
      if (entry.value.filterType != ColumnFilterType.entityRef) continue;
      // Dot-path column keys are handled by the backend (it walks the
      // remainder over the first-segment target type) — we only send
      // direct field values here.
      if (key.contains('.')) continue;
      final ids = <int>{};
      for (final p in widget.pendingRows) {
        final v = p.values[key];
        if (v == null) continue;
        final n = v is num ? v.toInt() : int.tryParse(v.toString());
        if (n != null) ids.add(n);
      }
      if (ids.isNotEmpty) {
        result.add({'fieldName': key, 'ids': ids.toList()});
      }
    }
    return result;
  }

  /// CF3.4.6 — collects, for each direct ENUM column on the row entity,
  /// the constant names the pending rows carry at that field. Drops nulls,
  /// dedupes locally. Returns an empty list when no pending rows or no
  /// direct ENUM columns exist; the backend treats null/empty the same
  /// way (no augmentation).
  List<Map<String, dynamic>> _pendingRowEnumValues() {
    if (widget.pendingRows.isEmpty) return const [];
    final result = <Map<String, dynamic>>[];
    for (final entry in _columnMeta.entries) {
      final key = entry.key;
      if (entry.value.filterType != ColumnFilterType.entityEnum) continue;
      // Dot-path enum columns are not augmented by pending direct fields.
      if (key.contains('.')) continue;
      final values = <String>{};
      for (final p in widget.pendingRows) {
        final v = p.values[key];
        if (v == null) continue;
        values.add(v.toString());
      }
      if (values.isNotEmpty) {
        result.add({'fieldName': key, 'values': values.toList()});
      }
    }
    return result;
  }

  bool get _anyColumnFilterable {
    for (final c in widget.tableColumns) {
      if (_buildFilterInputFor(c) != null) return true;
    }
    return false;
  }

  /// Builds the full column list for the GRID:
  /// `[edit-action?, ...data, delete-action?]`. Only present when the
  /// corresponding handler is configured. Pending rows render the
  /// "remove" (×) icon in the delete column and a "pending" badge on
  /// the first cell of the first pending data column.
  List<TrinaColumn> _buildAllTrinaColumns() {
    final cols = <TrinaColumn>[];
    final hasEdit = widget.onEditAction != null;
    final hasDelete = widget.onDeleteAction != null;
    final hasRemove = widget.onRemovePending != null;
    final hasTrailing = hasDelete || hasRemove;

    if (hasEdit) {
      cols.add(buildTrinaActionColumn(
        field: '__edit',
        width: 40,
        cellRenderer: (ctx) {
          final entity = entityFromRow(ctx.row);
          final isPending = ctx.row.metadata?['pending'] == true;
          if (isPending) return const SizedBox.shrink();
          final rowId = (entity?['id'] as num?)?.toInt();
          if (rowId == null) return const SizedBox.shrink();
          return Center(
            child: AppTheme.actionIcon(
              icon: Icons.edit, tooltip: 'Edit',
              onTap: () => widget.onEditAction!(rowId),
            ),
          );
        },
      ));
    }

    for (var i = 0; i < widget.tableColumns.length; i++) {
      final col = widget.tableColumns[i];
      final isFirstDataColumn = i == 0;
      final isLastDataColumn = i == widget.tableColumns.length - 1;
      cols.add(buildTrinaColumn(
        columnKey: col.key,
        header: col.header,
        rebuildOn: _gridRebuildTrigger,
        getIsSortActive: () => _sortColumnKey == col.key,
        getSortDirection: () =>
            _sortColumnKey == col.key ? _sortDirection : null,
        onSortToggle: _onSortToggle,
        buildFilterInput: () => _buildFilterInputFor(col),
        enableResize: !(isLastDataColumn && hasTrailing),
        cellRenderer: _dataCellRenderer(col, isFirstDataColumn: isFirstDataColumn),
      ));
    }

    if (hasTrailing) {
      cols.add(buildTrinaActionColumn(
        field: '__delete',
        width: 40,
        cellRenderer: (ctx) {
          final entity = entityFromRow(ctx.row);
          final isPending = ctx.row.metadata?['pending'] == true;
          if (isPending) {
            if (!hasRemove) return const SizedBox.shrink();
            final pendingIndex = ctx.row.metadata!['pendingIndex'] as int;
            return Center(
              child: AppTheme.actionIcon(
                icon: Icons.close,
                tooltip: 'Remove',
                onTap: () => widget.onRemovePending!(pendingIndex),
              ),
            );
          }
          if (!hasDelete) return const SizedBox.shrink();
          final rowId = (entity?['id'] as num?)?.toInt();
          if (rowId == null) return const SizedBox.shrink();
          return Center(
            child: AppTheme.actionIcon(
              icon: Icons.delete, tooltip: 'Delete',
              onTap: () => _confirmDelete(rowId),
            ),
          );
        },
      ));
    }

    return cols;
  }

  TrinaColumnRenderer _dataCellRenderer(
    GridTableColumn col, {
    required bool isFirstDataColumn,
  }) {
    return (ctx) {
      final entity = entityFromRow(ctx.row);
      final isPending = ctx.row.metadata?['pending'] == true;
      final value = entity?[col.key];
      final text = value == null ? '' : value.toString();
      final showBadge = isPending && ctx.rowIdx == 0 && isFirstDataColumn;

      Widget textCell() => Tooltip(
            message: text,
            waitDuration: const Duration(milliseconds: 600),
            child: Text(
              text,
              style: isPending
                  ? const TextStyle(fontStyle: FontStyle.italic)
                  : null,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );

      if (showBadge) {
        return Row(children: [
          Flexible(child: textCell()),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber.shade200,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('pending', style: TextStyle(fontSize: 10)),
          ),
        ]);
      }
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: textCell(),
      );
    };
  }

  void _onSortToggle(String columnKey) {
    final isActive = _sortColumnKey == columnKey;
    final next = cycleSortDirection(_sortDirection, isActive: isActive);
    setState(() {
      _sortColumnKey = next == null ? null : columnKey;
      _sortDirection = next;
    });
    _gridRebuildTrigger.bump();
    _refreshAfterFilterOrSortChange();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final mySeq = ++_fetchSeq;

    // Build formState as Map<String, String> for the backend
    final formStateStrings = <String, String>{};
    for (final entry in widget.formState.entries) {
      if (entry.value != null) {
        formStateStrings[entry.key] = entry.value.toString();
      }
    }

    try {
      final formStateEntries = formStateStrings.entries
          .map((e) => {'key': e.key, 'value': e.value})
          .toList();
      final List<Map<String, String>>? userSort =
          (_sortColumnKey != null && _sortDirection != null)
              ? [{'field': _sortColumnKey!, 'direction': _sortDirection!.wireValue}]
              : null;
      final userFilter = _composeUserFilter();
      // Embedded GRIDs omit `size` so the backend treats it as "all rows"
      // (gridElement.md G1.6.4). `baselineTotal` is the unfiltered count
      // used by the (N of M) row-count badge per G1.6.9.
      final result = await graphqlClient.query(QueryOptions(
        document: gql(r'''
          query GridData($input: GridDataInput!) {
            gridData(input: $input) {
              items totalCount baselineTotal
            }
          }
        '''),
        variables: {
          'input': {
            'dataFormCode': widget.dataFormCode,
            'elementCode': widget.elementCode,
            'entityId': widget.entityId,
            'formState': formStateEntries,
            if (userSort != null) 'userSort': userSort,
            if (userFilter != null) 'userFilter': userFilter,
          },
        },
        fetchPolicy: FetchPolicy.noCache,
      ));
      if (mySeq != _fetchSeq || !mounted) return;
      if (result.hasException) throw result.exception!;
      final data = result.data!['gridData'] as Map<String, dynamic>;
      final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      final fieldKeys = widget.tableColumns.map((c) => c.key).toList();
      setState(() {
        _trinaRows = items
            .map((e) => buildTrinaRow(entity: e, fieldKeys: fieldKeys))
            .toList();
        _gridGeneration++;
        _baselineTotal = (data['baselineTotal'] as num?)?.toInt() ?? items.length;
        _loading = false;
      });
    } catch (e) {
      if (mySeq != _fetchSeq || !mounted) return;
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
    // 30 % lighter than the form-input border so the in-table separator
    // recedes a bit relative to the GRID's outer border.
    final separatorColor =
        Color.lerp(borderColor, Colors.white, 0.3) ?? borderColor;

    return SizedBox(
      width: double.infinity,
      // GRIDs use the same border colour as the form inputs around them
      // for visual consistency inside a DataForm editor.
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel header
            Container(
              width: double.infinity,
              padding: AppTheme.panelHeaderPadding,
              decoration: const BoxDecoration(
                color: AppTheme.panelHeaderBackground,
              ),
              child: Row(
                children: [
                  Text(widget.label, style: AppTheme.panelHeaderTitle),
                  if (_rowCountBadge() != null) ...[
                    const SizedBox(width: AppTheme.spacingSm),
                    Text(
                      _rowCountBadge()!,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                  const Spacer(),
                  if (widget.onAddAction != null)
                    IconButton(
                      icon: const Icon(Icons.add, size: AppTheme.iconSize),
                      tooltip: 'Add',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: widget.onAddAction,
                    ),
                  if (widget.onAddAction != null)
                    const SizedBox(width: AppTheme.spacingSm),
                  // Clear-filters is available whenever the GRID has any
                  // filterable columns (independent of entityId), because
                  // pending rows are filtered client-side too per
                  // columnFilters.md CF1.5.1.
                  if (_anyColumnFilterable)
                    IconButton(
                      icon: const Icon(Icons.filter_alt_off, size: AppTheme.iconSize),
                      tooltip: 'Clear filters',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _hasActiveFilters ? _clearColumnFilters : null,
                    ),
                  if (_anyColumnFilterable)
                    const SizedBox(width: AppTheme.spacingSm),
                  // Reload icon swaps for a same-sized spinner during any
                  // refetch so users see "we're working" without the table
                  // flickering away (gridElement.md G1.6.5 — Option A).
                  if (widget.entityId != null)
                    IconButton(
                      icon: _loading
                          ? const SizedBox(
                              width: AppTheme.iconSize,
                              height: AppTheme.iconSize,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: AppTheme.iconSize),
                      tooltip: 'Reload',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _loading ? null : _fetchData,
                    ),
                ],
              ),
            ),
          Container(height: 1, color: separatorColor),
          // Errors replace the grid (rare, recoverable via Retry).
          // Otherwise the GRID always renders — loading is signalled by
          // the toolbar Reload→spinner swap (G1.6.5 / Option A); the
          // empty-state message and the first-load spinner both render
          // inside TrinaGrid's noRowsWidget at the same single-row
          // height (G1.6.8).
          if (widget.entityId != null && _error != null)
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
          else
            // Sized host: TrinaGrid is a virtualised list and needs a
            // bounded parent. Height tracks the actual rendered row
            // count (gridElement.md G1.6.8); rowCount==0 reserves one
            // row for the empty/first-load state.
            SizedBox(
              height: computeGridBodyHeight(
                rowCount: _effectiveRows().length,
                headerHeight: _anyColumnFilterable
                    ? kTrinaColumnHeightWithFilter
                    : kTrinaColumnHeightNoFilter,
              ),
              width: double.infinity,
              child: TrinaGrid(
                key: ValueKey(
                    'grid:${widget.dataFormCode}:${widget.elementCode}:$_gridGeneration'),
                columns: _buildAllTrinaColumns(),
                rows: _effectiveRows(),
                rowColorCallback: _rowColor,
                configuration: trinaGridConfigForApp(
                  columnHeight: _anyColumnFilterable
                      ? kTrinaColumnHeightWithFilter
                      : kTrinaColumnHeightNoFilter,
                ),
                // First-load: rows haven't arrived yet, no pending rows
                // either → centred spinner sized to fit one row.
                // Steady-state empty: contextual "no entries" message.
                noRowsWidget: _loading && _effectiveRows().isEmpty
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(AppTheme.spacingMd),
                        child: Text(
                          widget.entityId == null
                              ? 'No entries yet. Use + to add.'
                              : 'No entries.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  /// Row-count badge per gridElement.md G1.6.9.
  /// `N = visibleCommitted + visiblePending`,
  /// `M = totalCommitted   + totalPending`. Returns null when both are
  /// zero (the empty-state message owns the slot).
  String? _rowCountBadge() {
    final visibleCommitted = widget.entityId == null ? 0 : _trinaRows.length;
    final totalCommitted = widget.entityId == null ? 0 : _baselineTotal;
    final visiblePending =
        widget.entityId == null ? _effectiveRows().length : 0;
    final totalPending =
        widget.entityId == null ? widget.pendingRows.length : 0;
    final n = visibleCommitted + visiblePending;
    final m = totalCommitted + totalPending;
    if (n == 0 && m == 0) return null;
    return n == m ? '($n)' : '($n of $m)';
  }
}
