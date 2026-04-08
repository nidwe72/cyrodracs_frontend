import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_config_editor/app_config_service.dart';
import '../basic/form_renderer_view.dart';
import '../models/app_config_node.dart';
import '../models/data_form.dart';
import '../models/data_form_element.dart';
import '../models/editor_stack.dart';
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
                // Parse GridTableColumns and AddAction from children
                final tableColumns = <GridTableColumn>[];
                AddActionConfig? addAction;
                for (final elemChild in elem.children) {
                  if (elemChild.isCollection && elemChild.label == 'tableColumns') {
                    for (final colNode in elemChild.children) {
                      tableColumns.add(GridTableColumn(
                        key: colNode.dataBinding ?? colNode.label,
                        header: colNode.viewNodeLabel ?? colNode.label,
                        entityRendererRef: colNode.entityRendererRef,
                      ));
                    }
                  } else if (elemChild.isInstance && elemChild.typeCode == 'AddAction') {
                    // Parse AddAction with contextBindings
                    String? targetRef;
                    String? childLabel;
                    final bindings = <AddActionContextBinding>[];
                    for (final actionChild in elemChild.children) {
                      if (actionChild.typeCode == 'AddActionTarget') {
                        targetRef = actionChild.label;
                      } else if (actionChild.typeCode == 'AddActionLabel') {
                        childLabel = actionChild.label;
                      } else if (actionChild.isCollection && actionChild.label == 'contextBindings') {
                        for (final bindingNode in actionChild.children) {
                          String? target;
                          String? source;
                          for (final bc in bindingNode.children) {
                            if (bc.typeCode == 'ContextBindingTarget') target = bc.label;
                            if (bc.typeCode == 'ContextBindingSource') source = bc.label;
                          }
                          if (target != null && source != null) {
                            bindings.add(AddActionContextBinding(target: target, source: source));
                          }
                        }
                      }
                    }
                    if (targetRef != null) {
                      addAction = AddActionConfig(
                        targetDataFormRef: targetRef,
                        childLabel: childLabel,
                        contextBindings: bindings,
                      );
                    }
                  }
                }
                elements.add(DataFormElement(
                  key: elem.label,
                  label: elem.label,
                  type: type,
                  dataBinding: elem.dataBinding,
                  dataBindingNodeId: elem.dataBindingNodeId,
                  entityProviderRef: elem.entityProviderRef,
                  entityRendererRef: elem.entityRendererRef,
                  tableColumns: tableColumns,
                  reloadOnChangeOf: elem.reloadOnChangeOf,
                  mandatory: elem.mandatory,
                  addAction: addAction,
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

class _AppViewState extends State<AppView> {
  final _service = AppConfigService();

  List<_ViewDef> _viewDefs = [];
  _ViewDef? _selectedDef;
  List<Map<String, dynamic>> _entities = [];
  bool _loading = true;
  String? _error;

  // Editor stack replaces the flat _mode/_editEntityId/_editForm/_editValues
  final EditorStack _editorStack = EditorStack();

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
      _editorStack.clear();
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

  Future<void> _pushEditor({
    required String dataFormCode,
    int? entityId,
    String? label,
    Map<String, dynamic> contextBindings = const {},
    String? sourceElementCode,
  }) async {
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
      final form = _buildDataFormByCode(root, dataFormCode);
      if (form == null) {
        setState(() { _error = 'DataForm "$dataFormCode" not found'; _loading = false; });
        return;
      }

      Map<String, dynamic>? values;
      if (entityId != null) {
        final response = await http.get(
          Uri.parse('http://localhost:8080/api/data-form-data/${form.code}/$entityId'),
        );
        if (response.statusCode != 200) {
          setState(() { _error = 'Load failed: HTTP ${response.statusCode}'; _loading = false; });
          return;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        values = (data['values'] as Map<String, dynamic>?) ?? {};
      }

      final frame = EditorFrame(
        dataFormCode: dataFormCode,
        entityId: entityId,
        contextBindings: contextBindings,
        breadcrumbLabel: label,
        sourceElementCode: sourceElementCode,
        form: form,
        initialValues: values,
      );

      setState(() {
        _editorStack.push(frame);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _popEditor({bool saved = false, Map<String, dynamic>? childValues, Map<String, dynamic>? childDisplayValues}) {
    final poppedFrame = _editorStack.current;
    setState(() {
      _editorStack.pop();

      // If child saved and parent exists: check if parent has no ID → collect as pending
      if (saved && poppedFrame != null && _editorStack.isNotEmpty) {
        final parentFrame = _editorStack.current!;
        if (parentFrame.entityId == null && poppedFrame.sourceElementCode != null) {
          // Parent has no ID — collect child as pending
          // Find the contextBindingTarget (the field that would receive the parent ID)
          String? bindingTarget;
          for (final entry in poppedFrame.contextBindings.entries) {
            bindingTarget = entry.key;
            break; // First binding is the parent reference
          }
          if (bindingTarget != null && childValues != null) {
            parentFrame.pendingChildren.add(PendingChild(
              dataFormCode: poppedFrame.dataFormCode,
              contextBindingTarget: bindingTarget,
              values: childValues,
              sourceElementCode: poppedFrame.sourceElementCode,
              displayValues: childDisplayValues ?? {},
            ));
          }
        }
      }

      if (_editorStack.isEmpty) {
        // Back to list — reload entities
        if (saved && _selectedDef != null) {
          _fetchEntities(_selectedDef!, page: _page);
        }
      }
    });
  }

  Future<void> _popToIndex(int index) async {
    if (_editorStack.hasUnsavedChanges) {
      final confirmed = await _showUnsavedChangesDialog();
      if (!confirmed) return;
    }
    setState(() {
      if (index < 0) {
        // Pop to list view
        _editorStack.clear();
      } else {
        _editorStack.popTo(index);
      }
    });
  }

  Future<bool> _showUnsavedChangesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('You have unsaved changes. Discard and go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _onNodeActivated(_ViewDef def) {
    if (def.type == 'ENTITY_LIST') {
      _fetchEntities(def);
    } else if (def.type == 'STATIC_PAGE') {
      setState(() {
        _selectedDef = def;
        _editorStack.clear();
        _loading = false;
        _error = null;
      });
    }
  }

  void _editEntity(int entityId) {
    final def = _selectedDef!;
    if (def.dataFormRef == null) {
      setState(() => _error = 'No dataForm configured for ${def.label}');
      return;
    }
    _pushEditor(
      dataFormCode: def.dataFormRef!,
      entityId: entityId,
      label: '${def.label} #$entityId',
    );
  }

  void _addEntity() {
    final def = _selectedDef!;
    if (def.dataFormRef == null) {
      setState(() => _error = 'No dataForm configured for ${def.label}');
      return;
    }
    _pushEditor(
      dataFormCode: def.dataFormRef!,
      label: 'New ${def.label}',
    );
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

    return Column(
      children: [
        _buildStackPathTree(),
        const Divider(height: 1),
        Expanded(child: _buildContent()),
      ],
    );
  }

  /// Builds the vertical stack path tree above the editor area.
  Widget _buildStackPathTree() {
    final def = _selectedDef!;
    final frames = _editorStack.frames;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Root: ViewNode
          _StackPathNode(
            label: def.label,
            depth: 0,
            isActive: frames.isEmpty,
            onTap: frames.isEmpty ? null : () => _popToIndex(-1),
          ),
          // Editor frames
          for (int i = 0; i < frames.length; i++)
            _StackPathNode(
              label: frames[i].label,
              depth: i + 1,
              isActive: i == frames.length - 1,
              onTap: i == frames.length - 1
                  ? null
                  : () => _popToIndex(i),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_editorStack.isNotEmpty) {
      return _buildEditorView();
    }

    final def = _selectedDef!;
    if (def.type == 'STATIC_PAGE') {
      return _buildStaticPage();
    }

    return _buildEntityTable();
  }

  Widget _buildEditorView() {
    final frame = _editorStack.current!;
    if (frame.form == null) {
      return const Center(child: Text('Form not loaded'));
    }

    // Build pending children map grouped by source element code
    final pendingByElement = <String, List<PendingChild>>{};
    for (final pending in frame.pendingChildren) {
      final key = pending.sourceElementCode ?? '';
      pendingByElement.putIfAbsent(key, () => []).add(pending);
    }

    // Check if this is a child frame where the parent has no ID
    // In that case, the child should NOT persist — it should collect as pending
    final bool isChildOfUnsavedParent = _editorStack.depth >= 2 &&
        _editorStack.frames[_editorStack.depth - 2].entityId == null;

    return FormRendererView(
      key: ValueKey('edit-${frame.dataFormCode}-${frame.entityId ?? 'new'}-${_editorStack.depth}'),
      form: frame.form!,
      entityId: frame.entityId,
      initialValues: frame.formState ?? frame.initialValues,
      contextBindings: frame.contextBindings,
      onValuesChanged: (values) {
        frame.formState = values;
      },
      pendingChildrenByElement: pendingByElement,
      onBeforeSave: isChildOfUnsavedParent
          ? (Map<String, dynamic> values, Map<String, dynamic> displayValues) async {
              // Don't persist to DB — collect as pending on parent frame
              _popEditor(saved: true, childValues: values, childDisplayValues: displayValues);
              return false; // Skip normal persistence
            }
          : null,
      onSaved: () {
        _popEditor(saved: true);
      },
      onGridAction: ({
        required String targetDataFormRef,
        int? entityId,
        Map<String, dynamic> contextBindings = const {},
        String? childLabel,
        String? sourceElementCode,
      }) {
        _pushEditor(
          dataFormCode: targetDataFormRef,
          entityId: entityId,
          label: childLabel,
          contextBindings: contextBindings,
          sourceElementCode: sourceElementCode,
        );
      },
      onGridDelete: ({
        required String dataFormCode,
        required String elementCode,
        required int entityId,
      }) async {
        try {
          final response = await http.delete(
            Uri.parse('http://localhost:8080/api/view/grid-data/$dataFormCode/$elementCode/$entityId'),
          );
          return response.statusCode == 200;
        } catch (e) {
          return false;
        }
      },
      onRemovePending: (String elementCode, int index) {
        setState(() {
          final matching = frame.pendingChildren
              .where((p) => p.sourceElementCode == elementCode)
              .toList();
          if (index < matching.length) {
            frame.pendingChildren.remove(matching[index]);
          }
        });
      },
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
                        if (def.columns.isNotEmpty)
                          AppTheme.headerWithActionsOffset(def.columns.first.header),
                        ...def.columns.skip(1).map((c) => DataColumn(label: Text(c.header))),
                      ],
                      rows: _entities.asMap().entries.map((entry) {
                        final index = entry.key;
                        final e = entry.value;
                        final id = (e['id'] as num).toInt();
                        final lastColIndex = def.columns.length - 1;
                        final deleteAction = AppTheme.actionIcon(
                          icon: Icons.delete,
                          tooltip: 'Delete',
                          onTap: () => _confirmDelete(id, e['name']),
                        );
                        final editActions = [
                          if (def.dataFormRef != null)
                            AppTheme.actionIcon(
                              icon: Icons.edit,
                              tooltip: 'Edit',
                              onTap: () => _editEntity(id),
                            ),
                        ];
                        return DataRow(
                          color: AppTheme.stripeColor(index),
                          cells: [
                            if (def.columns.length == 1)
                              // Single column: edit + data + delete all in one cell
                              DataCell(Row(
                                children: [
                                  ...editActions,
                                  if (editActions.isNotEmpty) const SizedBox(width: 8),
                                  Expanded(child: Text('${e[def.columns.first.key] ?? ''}', overflow: TextOverflow.ellipsis)),
                                  const SizedBox(width: 8),
                                  deleteAction,
                                ],
                              )),
                            if (def.columns.length > 1) ...[
                              // First column: edit icon + data
                              AppTheme.cellWithActions(
                                '${e[def.columns.first.key] ?? ''}',
                                editActions,
                              ),
                              // Middle data columns
                              ...def.columns.skip(1).take(lastColIndex > 0 ? lastColIndex - 1 : 0)
                                  .map((c) => DataCell(Text('${e[c.key] ?? ''}'))),
                              // Last column: data + delete icon
                              AppTheme.cellWithTrailingActions(
                                '${e[def.columns.last.key] ?? ''}',
                                [deleteAction],
                              ),
                            ],
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
                padding: const EdgeInsets.only(
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

/// A single node in the stack path tree rendered above the editor.
class _StackPathNode extends StatelessWidget {
  final String label;
  final int depth;
  final bool isActive;
  final VoidCallback? onTap;

  const _StackPathNode({
    required this.label,
    required this.depth,
    required this.isActive,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive ? Icons.circle : Icons.play_arrow,
                size: 10,
                color: isActive ? Colors.blue.shade700 : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive
                      ? Colors.blue.shade700
                      : onTap != null
                          ? Colors.blue.shade400
                          : Colors.grey.shade600,
                  decoration: onTap != null && !isActive
                      ? TextDecoration.underline
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
