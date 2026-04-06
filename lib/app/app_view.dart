import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_config_editor/app_config_service.dart';
import '../basic/form_renderer_view.dart';
import '../models/app_config_node.dart';
import '../models/data_form.dart';
import '../models/data_form_element.dart';
import '../theme/app_theme.dart';

/// Converts a SCREAMING_SNAKE_CASE backend type value to the camelCase name
/// expected by [DataFormElementType.byName].
String _toCamelCase(String screaming) {
  final parts = screaming.toLowerCase().split('_').where((p) => p.isNotEmpty).toList();
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

DataForm? _buildDataFormByCode(AppConfigNode root, String dataFormCode) {
  for (final child in root.children) {
    if (child.isCollection && child.label == 'dataForms') {
      for (final formNode in child.children) {
        if (formNode.label == dataFormCode) {
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
                // Parse GridTableColumns from tableColumns collection child
                final tableColumns = <GridTableColumn>[];
                for (final elemChild in elem.children) {
                  if (elemChild.isCollection && elemChild.label == 'tableColumns') {
                    for (final colNode in elemChild.children) {
                      tableColumns.add(GridTableColumn(
                        key: colNode.dataBinding ?? colNode.label,
                        header: colNode.viewNodeLabel ?? colNode.label,
                        entityRendererRef: colNode.entityRendererRef,
                      ));
                    }
                  }
                }
                elements.add(DataFormElement(
                  key: elem.label,
                  label: elem.label,
                  type: type,
                  entityProviderRef: elem.entityProviderRef,
                  entityRendererRef: elem.entityRendererRef,
                  tableColumns: tableColumns,
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

/// A resolved ViewNode from the AppConfig tree used for navigation.
class _ViewDef {
  final String code;
  final String label;
  final String type; // ENTITY_LIST, GROUP, STATIC_PAGE
  final String? dataFormRef;
  final String? content;
  final List<_ColDef> columns;
  final List<_ViewDef> children;

  const _ViewDef({
    required this.code,
    required this.label,
    required this.type,
    this.dataFormRef,
    this.content,
    this.columns = const [],
    this.children = const [],
  });
}

class _ColDef {
  final String header;
  final String key;
  const _ColDef(this.header, this.key);
}

List<_ViewDef> _buildViewDefs(AppConfigNode root) {
  for (final child in root.children) {
    if (child.isCollection && child.label == 'viewTree') {
      return child.children.map(_buildViewDef).toList();
    }
  }
  return [];
}

_ViewDef _buildViewDef(AppConfigNode node) {
  final columns = <_ColDef>[];
  final children = <_ViewDef>[];

  for (final child in node.children) {
    if (child.isCollection && child.label == 'tableColumns') {
      for (final col in child.children) {
        final key = col.dataBinding ?? col.label;
        final header = col.viewNodeLabel ?? col.label;
        columns.add(_ColDef(header, key));
      }
    } else if (child.isCollection && child.label == 'children') {
      for (final childNode in child.children) {
        children.add(_buildViewDef(childNode));
      }
    }
  }

  return _ViewDef(
    code: node.label,
    label: node.viewNodeLabel ?? node.label,
    type: node.typeValue ?? 'GROUP',
    dataFormRef: node.dataFormRef,
    content: node.viewContent,
    columns: columns,
    children: children,
  );
}

class AppView extends StatefulWidget {
  const AppView({super.key});

  @override
  State<AppView> createState() => _AppViewState();
}

enum _DetailMode { table, edit, staticPage }

class _AppViewState extends State<AppView> {
  final _service = AppConfigService();

  List<_ViewDef> _viewDefs = [];
  _ViewDef? _selectedDef;
  List<Map<String, dynamic>> _entities = [];
  bool _loading = true;
  String? _error;

  _DetailMode _mode = _DetailMode.table;
  int? _editEntityId;
  DataForm? _editForm;
  Map<String, dynamic>? _editValues;

  // Pagination state
  int _page = 0;
  final int _pageSize = 10;
  int _totalCount = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _loadViewTree();
  }

  Future<void> _loadViewTree() async {
    try {
      final root = await _service.fetchTree();
      if (root == null) {
        setState(() { _error = 'AppConfig not loaded'; _loading = false; });
        return;
      }
      setState(() {
        _viewDefs = _buildViewDefs(root);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _fetchEntities(_ViewDef def, {int page = 0}) async {
    setState(() {
      _selectedDef = def;
      _loading = true;
      _error = null;
      _mode = _DetailMode.table;
    });
    try {
      final response = await http.get(
        Uri.parse(
          'http://localhost:8080/api/view/${def.code}/data?page=$page&size=$_pageSize',
        ),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (body['items'] as List<dynamic>).cast<Map<String, dynamic>>();
        setState(() {
          _entities = items;
          _page = body['page'] as int;
          _totalCount = body['totalCount'] as int;
          _totalPages = body['totalPages'] as int;
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
        Uri.parse('http://localhost:8080/api/view/${def.code}/$id'),
      );
      if (response.statusCode == 200) {
        _fetchEntities(def, page: _page);
      } else {
        setState(() => _error = 'Delete failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _error = 'Delete failed: $e');
    }
  }

  Future<void> _editEntity(int entityId) async {
    final def = _selectedDef!;
    if (def.dataFormRef == null) {
      setState(() => _error = 'No dataForm configured for ${def.label}');
      return;
    }
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
      final form = _buildDataFormByCode(root, def.dataFormRef!);
      if (form == null) {
        setState(() { _error = 'DataForm "${def.dataFormRef}" not found'; _loading = false; });
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
    if (def.dataFormRef == null) {
      setState(() => _error = 'No dataForm configured for ${def.label}');
      return;
    }
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
      final form = _buildDataFormByCode(root, def.dataFormRef!);
      if (form == null) {
        setState(() { _error = 'DataForm "${def.dataFormRef}" not found'; _loading = false; });
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

  void _onNodeActivated(_ViewDef def) {
    if (def.type == 'ENTITY_LIST') {
      _fetchEntities(def);
    } else if (def.type == 'STATIC_PAGE') {
      setState(() {
        _selectedDef = def;
        _mode = _DetailMode.staticPage;
        _loading = false;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _viewDefs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _viewDefs.isEmpty) {
      return Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)));
    }

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
      children: _buildTreeNodes(_viewDefs, 0),
    );
  }

  List<Widget> _buildTreeNodes(List<_ViewDef> defs, int depth) {
    final widgets = <Widget>[];
    for (final def in defs) {
      widgets.add(_TreeNode(
        label: def.label,
        depth: depth,
        isGroup: def.type == 'GROUP',
        selected: _selectedDef?.code == def.code,
        onDoubleTap: () => _onNodeActivated(def),
      ));
      if (def.type == 'GROUP' && def.children.isNotEmpty) {
        widgets.addAll(_buildTreeNodes(def.children, depth + 1));
      }
    }
    return widgets;
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

    if (_mode == _DetailMode.staticPage) {
      return _buildStaticPage();
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
                onPressed: () => _fetchEntities(def, page: _page),
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
            key: ValueKey('edit-${def.code}-${_editEntityId ?? 'new'}'),
            form: _editForm!,
            entityId: _editEntityId,
            initialValues: _editValues,
            onSaved: () => _fetchEntities(def, page: _page),
          ),
        ),
      ],
    );
  }

  Widget _buildStaticPage() {
    final def = _selectedDef!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(def.label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(def.content ?? '(No content configured)',
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildEntityTable() {
    final def = _selectedDef!;
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Panel header
            Container(
              width: double.infinity,
              padding: AppTheme.panelHeaderPadding,
              decoration: const BoxDecoration(color: AppTheme.panelHeaderBackground),
              child: Row(
                children: [
                  Text(def.label, style: AppTheme.panelHeaderTitle),
                  const SizedBox(width: AppTheme.spacingSm),
                  Text('($_totalCount total)',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const Spacer(),
                  if (def.dataFormRef != null)
                    IconButton(
                      icon: const Icon(Icons.add, size: AppTheme.iconSize),
                      tooltip: 'Add',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _addEntity,
                    ),
                  const SizedBox(width: AppTheme.spacingSm),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: AppTheme.iconSize),
                    tooltip: 'Reload',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _fetchEntities(def, page: _page),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            // Content — fills remaining height, scrollable
            if (_entities.isEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacingMd),
                  child: Text('No ${def.label.toLowerCase()} found.',
                      style: const TextStyle(color: Colors.grey)),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: [
                        ...def.columns.map((c) => DataColumn(label: Text(c.header))),
                        const DataColumn(label: Text('Actions')),
                      ],
                      rows: _entities.asMap().entries.map((entry) {
                        final index = entry.key;
                        final e = entry.value;
                        final id = (e['id'] as num).toInt();
                        return DataRow(
                          color: AppTheme.stripeColor(index),
                          cells: [
                            ...def.columns.map((c) => DataCell(Text('${e[c.key] ?? ''}'))),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (def.dataFormRef != null)
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: AppTheme.iconSize),
                                    tooltip: 'Edit',
                                    onPressed: () => _editEntity(id),
                                  ),
                                IconButton(
                                  icon: Icon(Icons.delete, size: AppTheme.iconSize, color: Colors.red),
                                  tooltip: 'Delete',
                                  onPressed: () => _confirmDelete(id, e['name']),
                                ),
                              ],
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
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
                      tooltip: 'First page',
                      onPressed: _page > 0
                          ? () => _fetchEntities(def, page: 0)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: AppTheme.iconSize),
                      tooltip: 'Previous page',
                      onPressed: _page > 0
                          ? () => _fetchEntities(def, page: _page - 1)
                          : null,
                    ),
                    Text('Page ${_page + 1} of $_totalPages',
                        style: const TextStyle(fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: AppTheme.iconSize),
                      tooltip: 'Next page',
                      onPressed: _page < _totalPages - 1
                          ? () => _fetchEntities(def, page: _page + 1)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.last_page, size: AppTheme.iconSize),
                      tooltip: 'Last page',
                      onPressed: _page < _totalPages - 1
                          ? () => _fetchEntities(def, page: _totalPages - 1)
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int id, dynamic name) async {
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
  final int depth;
  final bool isGroup;
  final bool selected;
  final VoidCallback onDoubleTap;

  const _TreeNode({
    required this.label,
    required this.depth,
    required this.isGroup,
    required this.selected,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Container(
        padding: EdgeInsets.only(left: 8.0 + depth * 16.0, top: 6, bottom: 6, right: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade50 : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              isGroup ? Icons.folder : Icons.list_alt,
              size: 18,
              color: Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
