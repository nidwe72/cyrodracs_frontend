import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  'DATE_PICKER__YEAR_MONTH',
];

const _kEntityValues = [
  'CAMERA_PRODUCER',
  'CAMERA_LENS_MOUNT',
  'CAMERA',
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
  final AppConfigNode? root;
  final bool stale;
  final AppConfigService service;
  final void Function(AppConfigNode updatedTree) onTreeChanged;

  const AppConfigDetailPanel({
    super.key,
    this.node,
    this.root,
    this.stale = false,
    required this.service,
    required this.onTreeChanged,
  });

  @override
  State<AppConfigDetailPanel> createState() => _AppConfigDetailPanelState();
}

class _AppConfigDetailPanelState extends State<AppConfigDetailPanel> {
  late TextEditingController _codeCtrl;
  late TextEditingController _dataBindingCtrl;
  String _selectedType = _kTypeValues.first;
  String? _selectedEntity;
  bool _loading = false;
  String? _error;

  // Data binding auto-completion state
  List<BindingCompletion> _completions = [];
  String? _completionEntityLabel;
  bool _showCompletions = false;
  int _completionIndex = -1;
  String? _parentEntityType;
  final FocusNode _dataBindingFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _codeCtrl = TextEditingController(
        text: (n != null && n.isInstance) ? n.label : '');
    _dataBindingCtrl = TextEditingController(
        text: n?.dataBinding ?? '');
    _selectedType = n?.typeValue ?? _kTypeValues.first;
    _selectedEntity = n?.entityValue;
    _parentEntityType = _findParentEntityType();
    final shouldFetchCompletions = _parentEntityType != null && n != null
        && (n.hasDataBindingField
            || (n.isCollection && n.childTypeCode == 'DataFormElement'));
    if (shouldFetchCompletions) {
      _fetchCompletions();
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _dataBindingCtrl.dispose();
    _dataBindingFocus.dispose();
    super.dispose();
  }

  /// Walks the root tree to find the DataForm parent of this node
  /// and returns its entityValue (e.g. "CAMERA_PRODUCER").
  ///
  /// Works for both:
  /// - Instance nodes (DataFormElement) — finds the form containing this element
  /// - Collection nodes (elements) — finds the form that owns this collection
  String? _findParentEntityType() {
    final n = widget.node;
    final root = widget.root;
    if (n == null || root == null) return null;

    for (final child in root.children) {
      if (child.isCollection && child.label == 'dataForms') {
        for (final form in child.children) {
          // For collection nodes: the "elements" collection's parentId
          // points to the DataForm
          if (n.isCollection && n.label == 'elements' && n.parentId == form.id) {
            return form.entityValue;
          }
          // For instance nodes: search elements inside the form
          if (n.hasDataBindingField) {
            for (final coll in form.children) {
              if (coll.isCollection && coll.label == 'elements') {
                for (final elem in coll.children) {
                  if (elem.id == n.id) return form.entityValue;
                }
              }
            }
          }
        }
      }
    }
    return null;
  }

  Future<void> _fetchCompletions({String prefix = ''}) async {
    if (_parentEntityType == null) return;
    try {
      final response = await widget.service
          .fetchBindingProposals(_parentEntityType!, prefix: prefix);
      if (!mounted) return;
      setState(() {
        _completions = response.completions;
        _completionEntityLabel = response.entityLabel;
      });
    } catch (_) {
      // Silently ignore — completions are optional assistance
    }
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
    final showBinding = isElement && _parentEntityType != null;

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
          if (showBinding) ...[
            const SizedBox(height: 12),
            _dataBindingField(),
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
      final dataBinding = _dataBindingCtrl.text.trim();
      await _run(() async {
        AppConfigNode? tree = await widget.service.addDataFormElement(
          parentFormId: col.parentId!,
          code: code,
          typeValue: _selectedType,
        );
        // If a dataBinding was specified, persist it on the newly created element
        if (dataBinding.isNotEmpty && tree != null) {
          final newElem = tree.findDataFormElement(col.parentId!, code);
          if (newElem?.id != null) {
            tree = await widget.service.addNode(
              parentObjectId: newElem!.id,
              typeCode: 'DataBinding',
              code: dataBinding,
            );
          }
        }
        return tree;
      });
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
          if (n.hasEntityField) ...[
            const SizedBox(height: 12),
            _entityDropdown(),
          ],
          if (n.hasTypeField) ...[
            const SizedBox(height: 12),
            _typeDropdown(),
          ],
          if (n.hasDataBindingField && _parentEntityType != null) ...[
            const SizedBox(height: 12),
            _dataBindingField(),
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
    final entityChanged = n.hasEntityField && _selectedEntity != n.entityValue;
    final dataBindingText = _dataBindingCtrl.text.trim();
    final dataBindingChanged = n.hasDataBindingField
        && dataBindingText != (n.dataBinding ?? '');

    if (!codeChanged && !typeChanged && !entityChanged && !dataBindingChanged) {
      return;
    }

    if (n.hasEntityField) {
      await _run(() => widget.service.updateDataForm(
            formId: n.id!,
            formCode: n.label,
            entityNodeId: n.entityNodeId,
            newCode: codeChanged ? code : null,
            newEntityValue: entityChanged ? _selectedEntity : null,
          ));
    } else if (n.hasTypeField) {
      await _run(() => widget.service.updateDataFormElementFull(
            elementId: n.id!,
            elementCode: n.label,
            typeNodeId: n.typeNodeId,
            dataBindingNodeId: n.dataBindingNodeId,
            newCode: codeChanged ? code : null,
            newTypeValue: typeChanged ? _selectedType : null,
            newDataBinding: dataBindingChanged
                ? (dataBindingText.isEmpty ? null : dataBindingText)
                : null,
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

  Widget _entityDropdown() {
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none)')),
      ..._kEntityValues
          .map((v) => DropdownMenuItem(value: v, child: Text(v))),
    ];
    return DropdownButtonFormField<String>(
      value: _kEntityValues.contains(_selectedEntity) ? _selectedEntity : null,
      decoration: const InputDecoration(
        labelText: 'Entity',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _selectedEntity = v),
    );
  }

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

  // ---------------------------------------------------------------------------
  // Data Binding field with segment-based auto-completion
  // ---------------------------------------------------------------------------

  List<BindingCompletion> _filteredCompletions() {
    final filter = _dataBindingCtrl.text.toLowerCase();
    return _completions.where((c) {
      if (filter.isEmpty) return true;
      final getterName =
          'get${c.segment[0].toUpperCase()}${c.segment.substring(1)}';
      return c.segment.toLowerCase().contains(filter) ||
          getterName.toLowerCase().contains(filter);
    }).toList();
  }

  void _acceptCompletion(BindingCompletion c) {
    if (c.leaf) {
      _dataBindingCtrl.text = c.segment;
      _dataBindingCtrl.selection = TextSelection.collapsed(
          offset: _dataBindingCtrl.text.length);
      setState(() {
        _showCompletions = false;
        _completionIndex = -1;
      });
    }
    // Non-leaf navigation will be added in Task 2
  }

  KeyEventResult _onDataBindingKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (!_showCompletions || _completions.isEmpty) {
      return KeyEventResult.ignored;
    }

    final filtered = _filteredCompletions();
    if (filtered.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _completionIndex = (_completionIndex + 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _completionIndex = (_completionIndex - 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_completionIndex >= 0 && _completionIndex < filtered.length) {
        _acceptCompletion(filtered[_completionIndex]);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _showCompletions = false;
        _completionIndex = -1;
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _dataBindingField() {
    final entityLabel = _completionEntityLabel ?? _parentEntityType ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          onKeyEvent: _onDataBindingKey,
          child: TextField(
            controller: _dataBindingCtrl,
            focusNode: _dataBindingFocus,
            decoration: InputDecoration(
              labelText: 'Data Binding',
              border: const OutlineInputBorder(),
              isDense: true,
              prefixText: '$entityLabel.',
              prefixStyle: const TextStyle(
                  color: Colors.grey, fontWeight: FontWeight.w500),
              suffixIcon: IconButton(
                icon: const Icon(Icons.grid_view, size: 18),
                tooltip: 'Browse attributes',
                onPressed: _openBindingPickerDialog,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _showCompletions = true;
                _completionIndex = -1;
              });
            },
            onTap: () {
              setState(() => _showCompletions = true);
            },
          ),
        ),
        if (_showCompletions && _completions.isNotEmpty) _buildCompletionList(),
      ],
    );
  }

  Widget _buildCompletionList() {
    final filtered = _filteredCompletions();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 2),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemExtent: 36,
        itemBuilder: (context, i) {
          final c = filtered[i];
          final getterName =
              'get${c.segment[0].toUpperCase()}${c.segment.substring(1)}';
          final isHighlighted = i == _completionIndex;

          return InkWell(
            onTap: () => _acceptCompletion(c),
            child: Container(
              color: isHighlighted ? Colors.blue.shade50 : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    c.leaf ? Icons.text_fields : Icons.arrow_forward,
                    size: 14,
                    color: isHighlighted ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      getterName,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight:
                            isHighlighted ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    c.javaType,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openBindingPickerDialog() async {
    if (_parentEntityType == null) return;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _BindingPickerDialog(
        service: widget.service,
        entityType: _parentEntityType!,
        currentValue: _dataBindingCtrl.text,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _dataBindingCtrl.text = result;
        _showCompletions = false;
      });
    }
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

// =============================================================================
// Binding Picker Dialog
// =============================================================================

class _BindingPickerDialog extends StatefulWidget {
  final AppConfigService service;
  final String entityType;
  final String currentValue;

  const _BindingPickerDialog({
    required this.service,
    required this.entityType,
    required this.currentValue,
  });

  @override
  State<_BindingPickerDialog> createState() => _BindingPickerDialogState();
}

class _BindingPickerDialogState extends State<_BindingPickerDialog> {
  List<BindingCompletion> _completions = [];
  String _entityLabel = '';
  String _prefix = '';
  final List<String> _pathSegments = [];
  String _filter = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchCompletions();
  }

  Future<void> _fetchCompletions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.service
          .fetchBindingProposals(widget.entityType, prefix: _prefix);
      if (!mounted) return;
      setState(() {
        _completions = response.completions;
        _entityLabel = response.entityLabel;
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

  void _navigateInto(String segment) {
    _pathSegments.add(segment);
    _prefix = _pathSegments.join('.');
    _filter = '';
    _fetchCompletions();
  }

  void _navigateBack() {
    if (_pathSegments.isEmpty) return;
    _pathSegments.removeLast();
    _prefix = _pathSegments.join('.');
    _filter = '';
    _fetchCompletions();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _completions.where((c) {
      if (_filter.isEmpty) return true;
      final f = _filter.toLowerCase();
      return c.segment.toLowerCase().contains(f) ||
          'get${c.segment}'.toLowerCase().contains(f);
    }).toList();

    final pathDisplay = _pathSegments.isEmpty
        ? _entityLabel
        : '$_entityLabel > ${_pathSegments.join(' > ')}';

    return Dialog(
      child: SizedBox(
        width: 440,
        height: 420,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Binding',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              // Path breadcrumb
              Row(
                children: [
                  if (_pathSegments.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: _navigateBack,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (_pathSegments.isNotEmpty) const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Path: $pathDisplay',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Filter
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Filter...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 8),
              // Completions list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text('Error: $_error',
                                style: const TextStyle(color: Colors.red)))
                        : filtered.isEmpty
                            ? const Center(
                                child: Text('No attributes found',
                                    style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemExtent: 40,
                                itemBuilder: (context, i) {
                                  final c = filtered[i];
                                  final isCurrentBinding = [
                                    ..._pathSegments,
                                    c.segment
                                  ].join('.') ==
                                      widget.currentValue;

                                  return ListTile(
                                    dense: true,
                                    leading: Icon(
                                      c.leaf
                                          ? Icons.text_fields
                                          : Icons.chevron_right,
                                      size: 18,
                                    ),
                                    title: Text(
                                      c.segment,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        color: isCurrentBinding
                                            ? Colors.blue
                                            : null,
                                      ),
                                    ),
                                    trailing: Text(
                                      c.javaType,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600),
                                    ),
                                    onTap: () {
                                      if (c.leaf) {
                                        final fullPath = [
                                          ..._pathSegments,
                                          c.segment
                                        ].join('.');
                                        Navigator.pop(context, fullPath);
                                      } else {
                                        _navigateInto(c.segment);
                                      }
                                    },
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
