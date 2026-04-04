import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_config_editor/app_config_service.dart';
import '../basic/form_renderer_view.dart';
import '../models/app_config_node.dart';
import '../models/data_form.dart';
import '../models/data_form_element.dart';

/// Converts a SCREAMING_SNAKE_CASE backend type value to the camelCase name
/// expected by [DataFormElementType.byName].
String _toCamelCase(String screaming) {
  final parts = screaming.toLowerCase().split('_').where((p) => p.isNotEmpty).toList();
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

DataForm? _buildDataFormForEntity(AppConfigNode root, String entityValue) {
  for (final child in root.children) {
    if (child.isCollection && child.label == 'dataForms') {
      for (final formNode in child.children) {
        if (formNode.entityValue == entityValue) {
          final elements = <DataFormElement>[];
          for (final c in formNode.children) {
            if (c.isCollection && c.label == 'elements') {
              for (final elem in c.children) {
                final raw = elem.typeValue;
                DataFormElementType type = DataFormElementType.inputString;
                if (raw != null) {
                  try {
                    type = DataFormElementType.values.byName(_toCamelCase(raw));
                  } catch (_) {}
                }
                elements.add(DataFormElement(
                  key: elem.label,
                  label: elem.label,
                  type: type,
                  entityProviderRef: elem.entityProviderRef,
                  entityRendererRef: elem.entityRendererRef,
                ));
              }
            }
          }
          return DataForm(
            code: formNode.label,
            entityValue: formNode.entityValue,
            elements: elements,
          );
        }
      }
    }
  }
  return null;
}

/// Describes an entity type shown in the App tree.
class _EntityDef {
  final String label;
  final String apiPath;
  final String entityTypeValue;
  final List<_ColDef> columns;

  const _EntityDef({
    required this.label,
    required this.apiPath,
    required this.entityTypeValue,
    required this.columns,
  });
}

class _ColDef {
  final String header;
  final String key;
  const _ColDef(this.header, this.key);
}

const _entityDefs = [
  _EntityDef(
    label: 'CameraProducers',
    apiPath: '/api/camera-producers',
    entityTypeValue: 'CAMERA_PRODUCER',
    columns: [
      _ColDef('ID', 'id'),
      _ColDef('Name', 'name'),
      _ColDef('Foundation', 'foundationYear'),
      _ColDef('Shutdown', 'shutdownYear'),
    ],
  ),
  _EntityDef(
    label: 'CameraLensMounts',
    apiPath: '/api/camera-lens-mounts',
    entityTypeValue: 'CAMERA_LENS_MOUNT',
    columns: [
      _ColDef('ID', 'id'),
      _ColDef('Name', 'name'),
    ],
  ),
  _EntityDef(
    label: 'Cameras',
    apiPath: '/api/cameras',
    entityTypeValue: 'CAMERA',
    columns: [
      _ColDef('ID', 'id'),
      _ColDef('Name', 'name'),
      _ColDef('Release Year', 'releaseYear'),
    ],
  ),
];

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

enum _DetailMode { table, edit }

class _AppViewState extends State<AppView> {
  final _service = AppConfigService();

  _EntityDef? _selectedDef;
  List<Map<String, dynamic>> _entities = [];
  bool _loading = false;
  String? _error;

  _DetailMode _mode = _DetailMode.table;
  int? _editEntityId;
  DataForm? _editForm;
  Map<String, dynamic>? _editValues;

  Future<void> _fetchEntities(_EntityDef def) async {
    setState(() {
      _selectedDef = def;
      _loading = true;
      _error = null;
      _mode = _DetailMode.table;
    });
    try {
      final response = await http.get(
        Uri.parse('http://localhost:8080${def.apiPath}'),
      );
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        setState(() {
          _entities = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'HTTP ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteEntity(int id) async {
    final def = _selectedDef!;
    try {
      final response = await http.delete(
        Uri.parse('http://localhost:8080${def.apiPath}/$id'),
      );
      if (response.statusCode == 200) {
        _fetchEntities(def);
      } else {
        setState(() => _error = 'Delete failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _error = 'Delete failed: $e');
    }
  }

  Future<void> _editEntity(int entityId) async {
    final def = _selectedDef!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = await _service.fetchTree();
      if (root == null) {
        setState(() { _error = 'AppConfig not loaded'; _loading = false; });
        return;
      }
      final form = _buildDataFormForEntity(root, def.entityTypeValue);
      if (form == null) {
        setState(() { _error = 'No DataForm configured for ${def.entityTypeValue}'; _loading = false; });
        return;
      }

      final response = await http.get(
        Uri.parse('http://localhost:8080/api/data-form-data/${form.code}/$entityId'),
      );
      if (response.statusCode != 200) {
        setState(() { _error = 'Load failed: HTTP ${response.statusCode}'; _loading = false; });
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final values = (data['values'] as Map<String, dynamic>?) ?? {};

      setState(() {
        _editEntityId = entityId;
        _editForm = form;
        _editValues = values;
        _mode = _DetailMode.edit;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _addEntity() async {
    final def = _selectedDef!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = await _service.fetchTree();
      if (root == null) {
        setState(() { _error = 'AppConfig not loaded'; _loading = false; });
        return;
      }
      final form = _buildDataFormForEntity(root, def.entityTypeValue);
      if (form == null) {
        setState(() { _error = 'No DataForm configured for ${def.entityTypeValue}'; _loading = false; });
        return;
      }
      setState(() {
        _editEntityId = null;
        _editForm = form;
        _editValues = null;
        _mode = _DetailMode.edit;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onNodeDoubleClick(_EntityDef def) {
    _fetchEntities(def);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: _buildTree(),
          ),
        ),
        Expanded(child: _buildDetailPanel()),
      ],
    );
  }

  Widget _buildTree() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: _entityDefs.map((def) => _TreeNode(
        label: def.label,
        selected: _selectedDef == def,
        onDoubleTap: () => _onNodeDoubleClick(def),
      )).toList(),
    );
  }

  Widget _buildDetailPanel() {
    if (_selectedDef == null) {
      return const Center(
        child: Text(
          'Double-click a node to view details',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
      );
    }

    if (_mode == _DetailMode.edit && _editForm != null) {
      return _buildEditView();
    }

    return _buildEntityTable();
  }

  Widget _buildEditView() {
    final def = _selectedDef!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: 'Back to list',
                onPressed: () => _fetchEntities(def),
              ),
              const SizedBox(width: 8),
              Text(
                  _editEntityId != null
                      ? 'Edit ${def.label} (id=$_editEntityId)'
                      : 'Add ${def.label}',
                  style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FormRendererView(
            key: ValueKey('edit-${def.label}-${_editEntityId ?? 'new'}'),
            form: _editForm!,
            entityId: _editEntityId,
            initialValues: _editValues,
            onSaved: () => _fetchEntities(def),
          ),
        ),
      ],
    );
  }

  Widget _buildEntityTable() {
    final def = _selectedDef!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(def.label, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add',
                onPressed: _addEntity,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Reload',
                onPressed: () => _fetchEntities(def),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_entities.isEmpty)
            Text('No ${def.label.toLowerCase()} found.',
                style: const TextStyle(color: Colors.grey))
          else
            SizedBox(
              width: double.infinity,
              child: DataTable(
                columns: [
                  ...def.columns.map((c) => DataColumn(label: Text(c.header))),
                  const DataColumn(label: Text('Actions')),
                ],
                rows: _entities.map((e) {
                  final id = (e['id'] as num).toInt();
                  return DataRow(cells: [
                    ...def.columns.map((c) => DataCell(Text('${e[c.key] ?? ''}'))),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Edit',
                          onPressed: () => _editEntity(id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(id, e['name']),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int id, String? name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm delete'),
        content: Text('Delete "${name ?? id}"?'),
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
    if (confirmed == true) {
      _deleteEntity(id);
    }
  }
}

class _TreeNode extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onDoubleTap;

  const _TreeNode({
    required this.label,
    required this.selected,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade50 : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(Icons.folder, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
