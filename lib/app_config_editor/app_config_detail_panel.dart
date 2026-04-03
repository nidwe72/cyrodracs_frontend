import 'package:flutter/material.dart';
import '../models/app_config_node.dart';
import 'app_config_service.dart';

const _kTypeValues = [
  'INPUT_STRING',
  'INPUT_NUMBER',
  'INPUT_EMAIL',
  'INPUT_PASSWORD',
  'TEXTAREA',
  'SELECT',
  'MULTI_SELECT',
  'CHECKBOX_GROUP',
  'RADIO_GROUP',
  'CHECKBOX',
  'TOGGLE',
  'DATE_PICKER',
  'TIME_PICKER',
  'DATE_TIME_PICKER',
  'DATE_RANGE_PICKER',
  'SLIDER',
  'RATING',
];

/// Detail panel for the AppConfigEditorView.
///
/// * No node selected  → placeholder hint.
/// * Collection node   → "Add child" form.
/// * Instance node     → edit primitives (code, type enum), save, delete.
///
/// A [ValueKey] keyed on the selected node's tree key is used by
/// [AppConfigEditorView] so this widget is fully recreated on every new
/// double-click, keeping [initState] as the single initialisation point.
class AppConfigDetailPanel extends StatefulWidget {
  final AppConfigNode? node;
  final bool stale;
  final AppConfigService service;
  final void Function(AppConfigNode updatedTree) onTreeChanged;

  const AppConfigDetailPanel({
    super.key,
    this.node,
    this.stale = false,
    required this.service,
    required this.onTreeChanged,
  });

  @override
  State<AppConfigDetailPanel> createState() => _AppConfigDetailPanelState();
}

class _AppConfigDetailPanelState extends State<AppConfigDetailPanel> {
  late TextEditingController _codeCtrl;
  String _selectedType = _kTypeValues.first;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _codeCtrl = TextEditingController(
        text: (n != null && n.isInstance) ? n.label : '');
    _selectedType = n?.typeValue ?? _kTypeValues.first;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    Widget content;
    final n = widget.node;

    if (n == null) {
      content = const Center(
        child: Text(
          'Select a node and double-click\nto view details',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    } else if (n.isCollection) {
      content = _buildAddForm(n);
    } else {
      content = _buildEditForm(n);
    }

    if (!widget.stale) return content;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0,    0,    0,    0.4, 0,
      ]),
      child: content,
    );
  }

  // ---------------------------------------------------------------------------
  // Add form  (collection node)
  // ---------------------------------------------------------------------------

  Widget _buildAddForm(AppConfigNode col) {
    final isElement = col.childTypeCode == 'DataFormElement';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isElement ? 'Add DataFormElement' : 'Add DataForm',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _codeField(),
          if (isElement) ...[
            const SizedBox(height: 12),
            _typeDropdown(),
          ],
          const SizedBox(height: 16),
          _errorText(),
          ElevatedButton(
            onPressed: _loading ? null : () => _onAdd(col),
            child: _loading ? _spinner() : const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _onAdd(AppConfigNode col) async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Code must not be empty.');
      return;
    }
    if (col.childTypeCode == 'DataFormElement') {
      await _run(() => widget.service.addDataFormElement(
            parentFormId: col.parentId!,
            code: code,
            typeValue: _selectedType,
          ));
    } else {
      await _run(() => widget.service.addNode(
            parentObjectId: col.parentId,
            typeCode: col.childTypeCode!,
            code: code,
          ));
    }
  }

  // ---------------------------------------------------------------------------
  // Edit form  (instance node)
  // ---------------------------------------------------------------------------

  Widget _buildEditForm(AppConfigNode n) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n.typeCode ?? n.label,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _codeField(),
          if (n.hasTypeField) ...[
            const SizedBox(height: 12),
            _typeDropdown(),
          ],
          const SizedBox(height: 16),
          _errorText(),
          Row(
            children: [
              ElevatedButton(
                onPressed: _loading ? null : () => _onSave(n),
                child: _loading ? _spinner() : const Text('Save'),
              ),
              if (n.isDeletable) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _loading ? null : () => _onDelete(n),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onSave(AppConfigNode n) async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Code must not be empty.');
      return;
    }
    final codeChanged = code != n.label;
    final typeChanged = n.hasTypeField && _selectedType != (n.typeValue ?? '');

    if (!codeChanged && !typeChanged) return;

    if (n.hasTypeField) {
      await _run(() => widget.service.updateDataFormElement(
            elementId: n.id!,
            elementCode: n.label,
            typeNodeId: n.typeNodeId,
            newCode: codeChanged ? code : null,
            newTypeValue: typeChanged ? _selectedType : null,
          ));
    } else {
      await _run(() => widget.service.updateNode(n.id!, code: code));
    }
  }

  Future<void> _onDelete(AppConfigNode n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm delete'),
        content: Text('Delete "${n.label}" and all its children?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => widget.service.deleteNode(n.id!));
    }
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  Future<void> _run(Future<AppConfigNode?> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tree = await action();
      if (!mounted) return;
      if (tree != null) widget.onTreeChanged(tree);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _codeField() => TextField(
        controller: _codeCtrl,
        decoration: const InputDecoration(
          labelText: 'Code',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );

  Widget _typeDropdown() {
    final value = _kTypeValues.contains(_selectedType)
        ? _selectedType
        : _kTypeValues.first;
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
        labelText: 'Type',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: _kTypeValues
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectedType = v);
      },
    );
  }

  Widget _errorText() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(_error!,
          style: const TextStyle(color: Colors.red, fontSize: 12)),
    );
  }

  Widget _spinner() => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2));
}
