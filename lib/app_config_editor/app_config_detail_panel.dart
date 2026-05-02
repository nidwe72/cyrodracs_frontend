import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config_node.dart';
import 'app_config_service.dart';
import 'expression_editor_dialog.dart';

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
  'ENTITY_SELECT',
  'GRID',
];

const _kEntityValues = [
  'CAMERA_PRODUCER',
  'CAMERA_LENS_MOUNT',
  'CAMERA_LENS_MOUNT_2_CAMERA_PRODUCER',
  'CAMERA',
];

const _kViewNodeTypes = [
  'ENTITY_LIST',
  'GROUP',
  'STATIC_PAGE',
];

const _kFilterNodeTypes = [
  'COMPARISON',
  'AND_GROUP',
  'OR_GROUP',
];

const _kFilterOperators = [
  'EQUALS',
  'NOT_EQUALS',
  'GREATER_THAN',
  'GREATER_THAN_OR_EQUAL',
  'LESS_THAN',
  'LESS_THAN_OR_EQUAL',
  'IS_NULL',
  'IS_NOT_NULL',
  'IN',
  'LIKE',
];

const _kSortDirections = [
  'ASC',
  'DESC',
];

const _kExpressionTypes = [
  'CONTEXT_PATH',
  'SPEL',
  'STATIC',
  'INJECTABLE_SNIPPET',
  'INJECTABLE_CLASS',
];

const _kInjectableBaseClasses = [
  'SCALAR_VALUE',
  'BOOLEAN_VALUE',
  'LIST_VALUE',
  'FILTER',
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
  late TextEditingController _templateCtrl;
  late TextEditingController _viewLabelCtrl;
  late TextEditingController _viewContentCtrl;
  late TextEditingController _tableColKeyCtrl;
  late TextEditingController _tableColHeaderCtrl;
  String _selectedType = _kTypeValues.first;
  String? _selectedEntity;
  String? _selectedEntityProviderRef;
  String? _selectedEntityRendererRef;
  String? _selectedFilterInjectableRef;
  String? _selectedVisibilityExpressionRef;
  // Expression state
  String _selectedExpressionType = _kExpressionTypes.first;
  String _selectedInjectableBaseClass = _kInjectableBaseClasses.first;
  late TextEditingController _expressionBodyCtrl;
  late TextEditingController _expressionDescCtrl;
  String _selectedViewNodeType = _kViewNodeTypes.first;
  String? _selectedDataFormRef;
  String? _selectedTableColRendererRef;
  // CF3.4.5 — admin opt-out for the visible-rows restriction (TableColumn /
  // GridTableColumn). Default true mirrors the backend.
  bool _tableColRestrictByVisibleRows = true;
  // FilterNode state
  String _selectedFilterNodeType = _kFilterNodeTypes.first;
  String _selectedFilterOperator = _kFilterOperators.first;
  late TextEditingController _filterFieldCtrl;
  late TextEditingController _filterValueCtrl;
  // SortField state
  late TextEditingController _sortFieldCtrl;
  String _selectedSortDirection = _kSortDirections.first;
  bool _loading = false;
  String? _error;

  // Data binding auto-completion state
  List<BindingCompletion> _completions = [];
  String? _completionEntityLabel;
  bool _showCompletions = false;
  int _completionIndex = -1;
  String? _parentEntityType;
  final FocusNode _dataBindingFocus = FocusNode();

  // Template auto-completion state (for EntityRenderer)
  List<BindingCompletion> _templateCompletions = [];
  bool _showTemplateCompletions = false;
  int _templateCompletionIndex = -1;
  final FocusNode _templateFocus = FocusNode();

  // TableColumn key auto-completion state
  bool _showTableColKeyCompletions = false;
  int _tableColKeyCompletionIndex = -1;
  final FocusNode _tableColKeyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _codeCtrl = TextEditingController(
        text: (n != null && n.isInstance) ? n.label : '');
    _dataBindingCtrl = TextEditingController(
        text: n?.dataBinding ?? '');
    _templateCtrl = TextEditingController(
        text: n?.template ?? '');
    _viewLabelCtrl = TextEditingController(
        text: n?.viewNodeLabel ?? '');
    _viewContentCtrl = TextEditingController(
        text: n?.viewContent ?? '');
    _tableColKeyCtrl = TextEditingController(
        text: n?.dataBinding ?? '');
    _tableColHeaderCtrl = TextEditingController(
        text: n?.viewNodeLabel ?? '');
    _selectedType = n?.typeValue ?? _kTypeValues.first;
    _selectedEntity = n?.entityValue;
    _selectedEntityProviderRef = n?.entityProviderRef;
    _selectedEntityRendererRef = n?.entityRendererRef;
    _selectedFilterInjectableRef = n?.filterInjectableRef;
    _selectedVisibilityExpressionRef = n?.visibilityExpressionRef;
    // Expression
    _selectedExpressionType = (n?.typeValue != null && _kExpressionTypes.contains(n!.typeValue))
        ? n.typeValue! : _kExpressionTypes.first;
    _selectedInjectableBaseClass = (n?.entityValue != null && _kInjectableBaseClasses.contains(n!.entityValue))
        ? n.entityValue! : _kInjectableBaseClasses.first;
    _expressionBodyCtrl = TextEditingController(text: n?.dataBinding ?? '');
    _expressionDescCtrl = TextEditingController(text: n?.template ?? '');
    _selectedViewNodeType = n?.typeValue ?? _kViewNodeTypes.first;
    _selectedDataFormRef = n?.dataFormRef;
    _selectedTableColRendererRef = n?.entityRendererRef;
    _tableColRestrictByVisibleRows = n?.restrictByVisibleRows ?? true;
    _filterFieldCtrl = TextEditingController(text: n?.dataBinding ?? '');
    _filterValueCtrl = TextEditingController(text: n?.viewNodeLabel ?? '');
    _sortFieldCtrl = TextEditingController(text: n?.dataBinding ?? '');
    _selectedFilterNodeType = (n?.typeValue != null && _kFilterNodeTypes.contains(n!.typeValue))
        ? n.typeValue! : _kFilterNodeTypes.first;
    _selectedFilterOperator = (n?.entityValue != null && _kFilterOperators.contains(n!.entityValue))
        ? n.entityValue! : _kFilterOperators.first;
    _selectedSortDirection = (n?.typeValue != null && _kSortDirections.contains(n!.typeValue))
        ? n.typeValue! : _kSortDirections.first;
    _parentEntityType = _findParentEntityType();
    final shouldFetchCompletions = _parentEntityType != null && n != null
        && (n.hasDataBindingField
            || n.isAnyTableColumn          // TableColumn or GridTableColumn — CF3.6
            || n.isFilterNode
            || n.isSortField
            || (n.isCollection && n.childTypeCode == 'DataFormElement')
            || (n.isCollection && n.childTypeCode == 'TableColumn')
            || (n.isCollection && n.childTypeCode == 'GridTableColumn')
            || (n.isCollection && n.childTypeCode == 'FilterNode')
            || (n.isCollection && n.childTypeCode == 'SortField'));
    if (shouldFetchCompletions) {
      _fetchCompletions();
    }
    // Fetch template completions for EntityRenderer nodes
    if (n != null && n.isEntityRenderer && n.entityValue != null) {
      _fetchTemplateCompletions(n.entityValue!);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _dataBindingCtrl.dispose();
    _dataBindingFocus.dispose();
    _templateCtrl.dispose();
    _templateFocus.dispose();
    _viewLabelCtrl.dispose();
    _viewContentCtrl.dispose();
    _tableColKeyCtrl.dispose();
    _tableColHeaderCtrl.dispose();
    _tableColKeyFocus.dispose();
    _filterFieldCtrl.dispose();
    _filterValueCtrl.dispose();
    _sortFieldCtrl.dispose();
    super.dispose();
  }

  /// Walks the root tree to find the entity type for this node.
  ///
  /// Works for:
  /// - DataFormElement instances — finds the parent DataForm's entityValue
  /// - "elements" collections — finds the owning DataForm's entityValue
  /// - TableColumn instances — finds the parent ViewNode's entityProvider → entityType
  /// - "tableColumns" collections — finds the owning ViewNode's entityProvider → entityType
  String? _findParentEntityType() {
    final n = widget.node;
    final root = widget.root;
    if (n == null || root == null) return null;

    // DataForm-based: DataFormElement or "elements" collection
    for (final child in root.children) {
      if (child.isCollection && child.label == 'dataForms') {
        for (final form in child.children) {
          if (n.isCollection && n.label == 'elements' && n.parentId == form.id) {
            return form.entityValue;
          }
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

    // ViewNode-based: TableColumn or "tableColumns" collection under a ViewNode
    String? providerRef = _findParentViewNodeProviderRef();
    if (providerRef != null) {
      return _resolveProviderEntityType(providerRef);
    }

    // GRID-based: GridTableColumn or "tableColumns" collection under a GRID
    // DataFormElement (per columnFilters.md CF3.6's GridTableColumn parity).
    providerRef = _findParentGridProviderRef();
    if (providerRef != null) {
      return _resolveProviderEntityType(providerRef);
    }

    // EntityProvider-based: FilterNode, SortField, or their collections
    // Walk up to find the parent EntityProvider's entityType
    if (n.isFilterNode || n.isSortField
        || (n.isCollection && (n.childTypeCode == 'FilterNode' || n.childTypeCode == 'SortField'))) {
      final providerEntityType = _findParentProviderEntityType();
      if (providerEntityType != null) return providerEntityType;
    }

    return null;
  }

  /// Finds the entityType of the EntityProvider that owns this FilterNode or SortField.
  String? _findParentProviderEntityType() {
    final n = widget.node;
    final root = widget.root;
    if (n == null || root == null) return null;

    for (final child in root.children) {
      if (child.isCollection && child.label == 'entityProviders') {
        for (final prov in child.children) {
          // Check if this provider contains the node (directly or nested)
          if (_nodeIsDescendant(prov, n)) {
            return prov.entityValue;
          }
        }
      }
    }
    return null;
  }

  bool _nodeIsDescendant(AppConfigNode parent, AppConfigNode target) {
    if (_nodesMatch(parent, target)) return true;
    for (final child in parent.children) {
      if (_nodesMatch(child, target)) return true;
      if (_nodeIsDescendant(child, target)) return true;
    }
    return false;
  }

  bool _nodesMatch(AppConfigNode a, AppConfigNode b) {
    if (a.isInstance && b.isInstance) {
      // Instance nodes: match by DB id (must be non-null)
      return a.id != null && a.id == b.id && a.typeCode == b.typeCode;
    }
    if (a.isCollection && b.isCollection) {
      // Collection nodes: match by label + parentId (unique within a parent)
      return a.label == b.label && a.parentId != null && a.parentId == b.parentId;
    }
    return false;
  }

  /// Finds the entityProviderRef of the ViewNode that owns this TableColumn or tableColumns collection.
  String? _findParentViewNodeProviderRef() {
    final n = widget.node;
    final root = widget.root;
    if (n == null || root == null) return null;

    // Search all ViewNodes (recursively)
    String? result;
    void searchViewNodes(List<AppConfigNode> nodes) {
      for (final vn in nodes) {
        if (vn.typeCode != 'ViewNode') continue;
        // Check if this ViewNode owns the tableColumns collection
        if (n.isCollection && n.label == 'tableColumns' && n.parentId == vn.id) {
          result = vn.entityProviderRef;
          return;
        }
        // Check if this ViewNode contains this TableColumn
        if (n.isTableColumn) {
          for (final col in vn.children) {
            if (col.isCollection && col.label == 'tableColumns') {
              for (final tc in col.children) {
                if (tc.id == n.id) { result = vn.entityProviderRef; return; }
              }
            }
          }
        }
        // Recurse into children
        for (final child in vn.children) {
          if (child.isCollection && child.label == 'children') {
            searchViewNodes(child.children);
            if (result != null) return;
          }
        }
      }
    }

    for (final child in root.children) {
      if (child.isCollection && child.label == 'viewTree') {
        searchViewNodes(child.children);
        if (result != null) return result;
      }
    }
    return null;
  }

  /// Looks up an EntityProvider by code and returns its entityType value.
  String? _resolveProviderEntityType(String providerCode) {
    final root = widget.root;
    if (root == null) return null;
    for (final child in root.children) {
      if (child.isCollection && child.label == 'entityProviders') {
        for (final prov in child.children) {
          if (prov.label == providerCode) return prov.entityValue;
        }
      }
    }
    return null;
  }

  /// CF3.6 — walks DataForm.elements looking for a GRID DataFormElement
  /// that owns this GridTableColumn or its parent tableColumns collection.
  /// Returns the GRID's entityProviderRef value, or null if not found.
  String? _findParentGridProviderRef() {
    final n = widget.node;
    final root = widget.root;
    if (n == null || root == null) return null;

    for (final dataForms in root.children) {
      if (!dataForms.isCollection || dataForms.label != 'dataForms') continue;
      for (final form in dataForms.children) {
        for (final elements in form.children) {
          if (!elements.isCollection || elements.label != 'elements') continue;
          for (final elem in elements.children) {
            for (final tc in elem.children) {
              if (!tc.isCollection || tc.label != 'tableColumns') continue;
              // Is this node the tableColumns collection under a GRID?
              if (n.id == tc.id) return elem.entityProviderRef;
              // Or is this node a GridTableColumn directly under it?
              for (final col in tc.children) {
                if (col.id == n.id) return elem.entityProviderRef;
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

  Future<void> _fetchTemplateCompletions(String entityType) async {
    try {
      final response = await widget.service
          .fetchBindingProposals(entityType);
      if (!mounted) return;
      setState(() {
        _templateCompletions = response.completions;
      });
    } catch (_) {}
  }

  /// Collects available EntityProvider codes from the root tree.
  List<String> _entityProviderCodes() {
    final root = widget.root;
    if (root == null) return [];
    final codes = <String>[];
    for (final child in root.children) {
      if (child.isCollection && child.label == 'entityProviders') {
        for (final prov in child.children) {
          codes.add(prov.label);
        }
      }
    }
    return codes;
  }

  /// Collects available EntityRenderer codes from the root tree.
  List<String> _entityRendererCodes() {
    final root = widget.root;
    if (root == null) return [];
    final codes = <String>[];
    for (final child in root.children) {
      if (child.isCollection && child.label == 'entityRenderers') {
        for (final ren in child.children) {
          codes.add(ren.label);
        }
      }
    }
    return codes;
  }

  /// Collects available Expression codes from the root tree.
  List<String> _expressionCodes() {
    final root = widget.root;
    if (root == null) return [];
    final codes = <String>[];
    for (final child in root.children) {
      if (child.isCollection && child.label == 'expressions') {
        for (final expr in child.children) {
          codes.add(expr.label);
        }
      }
    }
    return codes;
  }

  /// Collects available DataForm codes from the root tree.
  List<String> _dataFormCodes() {
    final root = widget.root;
    if (root == null) return [];
    final codes = <String>[];
    for (final child in root.children) {
      if (child.isCollection && child.label == 'dataForms') {
        for (final form in child.children) {
          codes.add(form.label);
        }
      }
    }
    return codes;
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
    final isProvider = col.childTypeCode == 'EntityProvider';
    final isRenderer = col.childTypeCode == 'EntityRenderer';
    final isViewNode = col.childTypeCode == 'ViewNode';
    // GridTableColumn lives under DataFormElement.tableColumns (typeCode
    // 'GridTableColumn'); TableColumn lives under ViewNode.tableColumns
    // (typeCode 'TableColumn'). Same UI, same fields — different typeCodes
    // for the saved children. Per columnFilters.md CF3.6.
    final isTableColumn = col.childTypeCode == 'TableColumn'
        || col.childTypeCode == 'GridTableColumn';
    final isGridTableColumn = col.childTypeCode == 'GridTableColumn';
    final isFilterNode = col.childTypeCode == 'FilterNode';
    final isSortField = col.childTypeCode == 'SortField';
    final showBinding = isElement && _parentEntityType != null;
    final showEntitySelectRefs = isElement && _selectedType == 'ENTITY_SELECT';

    String title;
    if (isElement) {
      title = 'Add DataFormElement';
    } else if (isProvider) {
      title = 'Add EntityProvider';
    } else if (isRenderer) {
      title = 'Add EntityRenderer';
    } else if (isViewNode) {
      title = 'Add ViewNode';
    } else if (isTableColumn) {
      title = isGridTableColumn ? 'Add GridTableColumn' : 'Add TableColumn';
    } else if (isFilterNode) {
      title = 'Add Filter Condition';
    } else if (isSortField) {
      title = 'Add Sort Field';
    } else {
      title = 'Add DataForm';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _codeField(),
          if (isElement) ...[
            const SizedBox(height: 12),
            _typeDropdown(),
          ],
          if (isViewNode) ...[
            const SizedBox(height: 12),
            _viewNodeTypeDropdown(),
            const SizedBox(height: 12),
            _labelField(),
            if (_selectedViewNodeType == 'ENTITY_LIST') ...[
              const SizedBox(height: 12),
              _entityProviderRefDropdown(),
              const SizedBox(height: 12),
              _dataFormRefDropdown(),
            ],
            if (_selectedViewNodeType == 'STATIC_PAGE') ...[
              const SizedBox(height: 12),
              _contentField(),
            ],
          ],
          if (isTableColumn) ...[
            const SizedBox(height: 12),
            _tableColumnKeyField(),
            const SizedBox(height: 12),
            _tableColumnHeaderField(),
            const SizedBox(height: 12),
            _tableColumnRendererDropdown(),
            const SizedBox(height: 8),
            _tableColumnRestrictByVisibleRowsCheckbox(),
          ],
          if (isFilterNode) ...[
            const SizedBox(height: 12),
            _filterNodeTypeDropdown(),
            if (_selectedFilterNodeType == 'COMPARISON') ...[
              const SizedBox(height: 12),
              _filterFieldField(),
              const SizedBox(height: 12),
              _filterOperatorDropdown(),
              if (_selectedFilterOperator != 'IS_NULL' && _selectedFilterOperator != 'IS_NOT_NULL') ...[
                const SizedBox(height: 12),
                _filterValueField(),
              ],
            ],
          ],
          if (isSortField) ...[
            const SizedBox(height: 12),
            _sortFieldField(),
            const SizedBox(height: 12),
            _sortDirectionDropdown(),
          ],
          if (showBinding) ...[
            const SizedBox(height: 12),
            _dataBindingField(),
          ],
          if (showEntitySelectRefs) ...[
            const SizedBox(height: 12),
            _entityProviderRefDropdown(),
            const SizedBox(height: 12),
            _entityRendererRefDropdown(),
          ],
          if (isProvider || isRenderer) ...[
            const SizedBox(height: 12),
            _entityDropdown(),
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
        // Persist entityProviderRef and entityRendererRef for ENTITY_SELECT
        if (_selectedType == 'ENTITY_SELECT' && tree != null) {
          final newElem = tree.findDataFormElement(col.parentId!, code);
          if (newElem?.id != null) {
            if (_selectedEntityProviderRef != null && _selectedEntityProviderRef!.isNotEmpty) {
              tree = await widget.service.addNode(
                parentObjectId: newElem!.id,
                typeCode: 'EntityProviderRef',
                code: _selectedEntityProviderRef!,
              );
            }
            // Re-fetch to get updated tree for the second child node
            final elemForRenderer = tree?.findDataFormElement(col.parentId!, code);
            if (_selectedEntityRendererRef != null && _selectedEntityRendererRef!.isNotEmpty
                && (elemForRenderer?.id ?? newElem?.id) != null) {
              tree = await widget.service.addNode(
                parentObjectId: (elemForRenderer?.id ?? newElem!.id),
                typeCode: 'EntityRendererRef',
                code: _selectedEntityRendererRef!,
              );
            }
          }
        }
        return tree;
      });
    } else if (col.childTypeCode == 'EntityProvider') {
      await _run(() async {
        AppConfigNode? tree = await widget.service.addNode(
          parentObjectId: col.parentId,
          typeCode: 'EntityProvider',
          code: code,
        );
        // Set entityType if selected
        if (_selectedEntity != null && tree != null) {
          // Find the newly created provider to get its ID
          tree = await widget.service.fetchTree();
          // Re-fetch and find the new provider
          if (tree != null) {
            for (final child in tree.children) {
              if (child.isCollection && child.label == 'entityProviders') {
                for (final prov in child.children) {
                  if (prov.label == code && prov.id != null) {
                    tree = await widget.service.addNode(
                      parentObjectId: prov.id,
                      typeCode: 'EntityProviderEntityType',
                      code: '${code}_entityType',
                      enumValue: _selectedEntity,
                    );
                    break;
                  }
                }
              }
            }
          }
        }
        return tree;
      });
    } else if (col.childTypeCode == 'EntityRenderer') {
      await _run(() async {
        AppConfigNode? tree = await widget.service.addNode(
          parentObjectId: col.parentId,
          typeCode: 'EntityRenderer',
          code: code,
        );
        // Set entityType if selected
        if (_selectedEntity != null && tree != null) {
          tree = await widget.service.fetchTree();
          if (tree != null) {
            for (final child in tree.children) {
              if (child.isCollection && child.label == 'entityRenderers') {
                for (final ren in child.children) {
                  if (ren.label == code && ren.id != null) {
                    tree = await widget.service.addNode(
                      parentObjectId: ren.id,
                      typeCode: 'EntityRendererEntityType',
                      code: '${code}_entityType',
                      enumValue: _selectedEntity,
                    );
                    break;
                  }
                }
              }
            }
          }
        }
        return tree;
      });
    } else if (col.childTypeCode == 'ViewNode') {
      await _run(() async {
        AppConfigNode? tree = await widget.service.addNode(
          parentObjectId: col.parentId,
          typeCode: 'ViewNode',
          code: code,
        );
        // Create child nodes for type, label, and refs
        tree = await widget.service.fetchTree();
        if (tree != null) {
          // Find the newly created ViewNode
          int? newId;
          void searchNode(List<AppConfigNode> nodes) {
            for (final n in nodes) {
              if (n.isCollection && (n.label == 'viewTree' || n.label == 'children')) {
                for (final vn in n.children) {
                  if (vn.label == code && vn.id != null) { newId = vn.id; return; }
                  for (final c in vn.children) { searchNode([c]); }
                }
              }
              for (final c in n.children) { searchNode([c]); }
            }
          }
          searchNode(tree.children);

          if (newId != null) {
            tree = await widget.service.addNode(
              parentObjectId: newId,
              typeCode: 'ViewNodeType',
              code: '${code}_type',
              enumValue: _selectedViewNodeType,
            );
            final label = _viewLabelCtrl.text.trim();
            if (label.isNotEmpty) {
              tree = await widget.service.addNode(
                parentObjectId: newId,
                typeCode: 'ViewNodeLabel',
                code: label,
              );
            }
            if (_selectedViewNodeType == 'ENTITY_LIST') {
              if (_selectedEntityProviderRef != null && _selectedEntityProviderRef!.isNotEmpty) {
                tree = await widget.service.addNode(
                  parentObjectId: newId,
                  typeCode: 'ViewNodeProviderRef',
                  code: _selectedEntityProviderRef!,
                );
              }
              if (_selectedDataFormRef != null && _selectedDataFormRef!.isNotEmpty) {
                tree = await widget.service.addNode(
                  parentObjectId: newId,
                  typeCode: 'ViewNodeDataFormRef',
                  code: _selectedDataFormRef!,
                );
              }
            } else if (_selectedViewNodeType == 'STATIC_PAGE') {
              final content = _viewContentCtrl.text.trim();
              if (content.isNotEmpty) {
                tree = await widget.service.addNode(
                  parentObjectId: newId,
                  typeCode: 'ViewNodeContent',
                  code: content,
                );
              }
            }
          }
        }
        return tree;
      });
    } else if (col.childTypeCode == 'TableColumn'
        || col.childTypeCode == 'GridTableColumn') {
      // Same Add flow for both TableColumn (under ViewNode) and
      // GridTableColumn (under DataFormElement). The parent's collection
      // childTypeCode determines which child typeCodes to use for
      // key/header/rendererRef. Per columnFilters.md CF3.6.
      final bool isGrid = col.childTypeCode == 'GridTableColumn';
      final String columnTypeCode = isGrid ? 'GridTableColumn' : 'TableColumn';
      final String keyTypeCode = isGrid ? 'GridTableColumnKey' : 'TableColumnKey';
      final String headerTypeCode =
          isGrid ? 'GridTableColumnHeader' : 'TableColumnHeader';
      final String rendererRefTypeCode =
          isGrid ? 'GridTableColumnRendererRef' : 'TableColumnRendererRef';
      final String restrictTypeCode = isGrid
          ? 'GridTableColumnRestrictByVisibleRows'
          : 'TableColumnRestrictByVisibleRows';
      await _run(() async {
        AppConfigNode? tree = await widget.service.addNode(
          parentObjectId: col.parentId,
          typeCode: columnTypeCode,
          code: code,
        );
        // Find the new column to add key/header children
        tree = await widget.service.fetchTree();
        if (tree != null) {
          // Re-fetch to get the ID — search all tableColumns collections
          // for one whose new child matches.
          int? colId;
          void searchColumns(List<AppConfigNode> nodes) {
            for (final n in nodes) {
              if (n.isCollection && n.label == 'tableColumns') {
                for (final c in n.children) {
                  if (c.label == code) { colId = c.id; return; }
                }
              }
              for (final c in n.children) { searchColumns([c]); }
            }
          }
          searchColumns(tree.children);

          if (colId != null) {
            final key = _tableColKeyCtrl.text.trim();
            if (key.isNotEmpty) {
              tree = await widget.service.addNode(
                parentObjectId: colId,
                typeCode: keyTypeCode,
                code: key,
              );
            }
            final header = _tableColHeaderCtrl.text.trim();
            if (header.isNotEmpty) {
              tree = await widget.service.addNode(
                parentObjectId: colId,
                typeCode: headerTypeCode,
                code: header,
              );
            }
            if (_selectedTableColRendererRef != null && _selectedTableColRendererRef!.isNotEmpty) {
              tree = await widget.service.addNode(
                parentObjectId: colId,
                typeCode: rendererRefTypeCode,
                code: _selectedTableColRendererRef!,
              );
            }
            // CF3.4.5 — only seed an explicit child when the user opted
            // out (default true matches the field initialiser on
            // TableColumn, so no node is needed when restrict==true).
            if (!_tableColRestrictByVisibleRows) {
              tree = await widget.service.addNode(
                parentObjectId: colId,
                typeCode: restrictTypeCode,
                code: 'false',
              );
            }
          }
        }
        return tree;
      });
    } else if (col.childTypeCode == 'FilterNode') {
      await _run(() async {
        AppConfigNode? tree = await widget.service.addNode(
          parentObjectId: col.parentId,
          typeCode: 'FilterNode',
          code: code,
        );
        // Re-fetch to find new node ID
        tree = await widget.service.fetchTree();
        if (tree == null) return tree;
        // Search for the new FilterNode
        int? newId;
        void search(List<AppConfigNode> nodes) {
          for (final n in nodes) {
            if (n.isFilterNode && n.label == code) { newId = n.id; return; }
            for (final c in n.children) { search([c]); }
          }
        }
        search(tree.children);
        if (newId != null) {
          tree = await widget.service.addNode(
            parentObjectId: newId,
            typeCode: 'FilterNodeType',
            code: '${code}_type',
            enumValue: _selectedFilterNodeType,
          );
          if (_selectedFilterNodeType == 'COMPARISON') {
            final field = _filterFieldCtrl.text.trim();
            if (field.isNotEmpty) {
              tree = await widget.service.addNode(
                parentObjectId: newId, typeCode: 'FilterField', code: field,
              );
            }
            tree = await widget.service.addNode(
              parentObjectId: newId, typeCode: 'FilterOperator',
              code: '${code}_op', enumValue: _selectedFilterOperator,
            );
            final value = _filterValueCtrl.text.trim();
            if (value.isNotEmpty && _selectedFilterOperator != 'IS_NULL' && _selectedFilterOperator != 'IS_NOT_NULL') {
              tree = await widget.service.addNode(
                parentObjectId: newId, typeCode: 'FilterValue', code: value,
              );
            }
          }
        }
        return tree;
      });
    } else if (col.childTypeCode == 'SortField') {
      await _run(() async {
        AppConfigNode? tree = await widget.service.addNode(
          parentObjectId: col.parentId,
          typeCode: 'SortField',
          code: code,
        );
        tree = await widget.service.fetchTree();
        if (tree == null) return tree;
        int? newId;
        void search(List<AppConfigNode> nodes) {
          for (final n in nodes) {
            if (n.isSortField && n.label == code) { newId = n.id; return; }
            for (final c in n.children) { search([c]); }
          }
        }
        search(tree.children);
        if (newId != null) {
          final field = _sortFieldCtrl.text.trim();
          if (field.isNotEmpty) {
            tree = await widget.service.addNode(
              parentObjectId: newId, typeCode: 'SortFieldField', code: field,
            );
          }
          tree = await widget.service.addNode(
            parentObjectId: newId, typeCode: 'SortDirection',
            code: '${code}_dir', enumValue: _selectedSortDirection,
          );
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
    final showEntitySelectRefs = n.hasEntitySelectFields
        && _selectedType == 'ENTITY_SELECT';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n.typeCode ?? n.label,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _codeField(),
          if (n.hasEntityField || n.isEntityProvider || n.isEntityRenderer) ...[
            const SizedBox(height: 12),
            _entityDropdown(),
          ],
          if (n.isEntityProvider) ...[
            const SizedBox(height: 12),
            _filterInjectableRefDropdown(),
          ],
          if (n.isExpression) ...[
            const SizedBox(height: 12),
            _expressionTypeDropdown(),
            const SizedBox(height: 12),
            _injectableBaseClassDropdown(),
            const SizedBox(height: 12),
            if (_selectedExpressionType == 'INJECTABLE_CLASS' ||
                _selectedExpressionType == 'INJECTABLE_SNIPPET')
              _expressionEditSourceButton()
            else
              _expressionBodyField(),
            const SizedBox(height: 12),
            _expressionDescField(),
          ],
          if (n.hasTypeField) ...[
            const SizedBox(height: 12),
            _typeDropdown(),
          ],
          if (n.isViewNode) ...[
            const SizedBox(height: 12),
            _viewNodeTypeDropdown(),
            const SizedBox(height: 12),
            _labelField(),
            if (_selectedViewNodeType == 'ENTITY_LIST') ...[
              const SizedBox(height: 12),
              _entityProviderRefDropdown(),
              const SizedBox(height: 12),
              _dataFormRefDropdown(),
            ],
            if (_selectedViewNodeType == 'STATIC_PAGE') ...[
              const SizedBox(height: 12),
              _contentField(),
            ],
          ],
          if (n.isAnyTableColumn) ...[
            const SizedBox(height: 12),
            _tableColumnKeyField(),
            const SizedBox(height: 12),
            _tableColumnHeaderField(),
            const SizedBox(height: 12),
            _tableColumnRendererDropdown(),
            const SizedBox(height: 8),
            _tableColumnRestrictByVisibleRowsCheckbox(),
          ],
          if (n.isFilterNode) ...[
            const SizedBox(height: 12),
            _filterNodeTypeDropdown(),
            if (_selectedFilterNodeType == 'COMPARISON') ...[
              const SizedBox(height: 12),
              _filterFieldField(),
              const SizedBox(height: 12),
              _filterOperatorDropdown(),
              if (_selectedFilterOperator != 'IS_NULL' && _selectedFilterOperator != 'IS_NOT_NULL') ...[
                const SizedBox(height: 12),
                _filterValueField(),
              ],
            ],
          ],
          if (n.isSortField) ...[
            const SizedBox(height: 12),
            _sortFieldField(),
            const SizedBox(height: 12),
            _sortDirectionDropdown(),
          ],
          if (n.hasDataBindingField && _parentEntityType != null) ...[
            const SizedBox(height: 12),
            _dataBindingField(),
          ],
          if (showEntitySelectRefs) ...[
            const SizedBox(height: 12),
            _entityProviderRefDropdown(),
            const SizedBox(height: 12),
            _entityRendererRefDropdown(),
          ],
          if (n.hasTypeField) ...[
            const SizedBox(height: 12),
            _visibilityExpressionRefDropdown(),
          ],
          if (n.hasTemplateField) ...[
            const SizedBox(height: 12),
            _templateField(),
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
                  onPressed: _loading ? null : () => _onCopy(n),
                  child: const Text('Copy'),
                ),
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
    final entityChanged = (n.hasEntityField || n.isEntityProvider || n.isEntityRenderer)
        && _selectedEntity != n.entityValue;
    final dataBindingText = _dataBindingCtrl.text.trim();
    final dataBindingChanged = n.hasDataBindingField
        && dataBindingText != (n.dataBinding ?? '');
    final providerRefChanged = n.hasEntitySelectFields
        && _selectedEntityProviderRef != (n.entityProviderRef ?? '');
    final rendererRefChanged = n.hasEntitySelectFields
        && _selectedEntityRendererRef != (n.entityRendererRef ?? '');
    final templateText = _templateCtrl.text;
    final templateChanged = n.hasTemplateField
        && templateText != (n.template ?? '');

    // ViewNode-specific change detection
    final viewLabelChanged = n.isViewNode
        && _viewLabelCtrl.text.trim() != (n.viewNodeLabel ?? '');
    final viewNodeTypeChanged = n.isViewNode
        && _selectedViewNodeType != (n.typeValue ?? '');
    final dataFormRefChanged = n.isViewNode
        && (_selectedDataFormRef ?? '') != (n.dataFormRef ?? '');
    final viewProviderRefChanged = n.isViewNode
        && (_selectedEntityProviderRef ?? '') != (n.entityProviderRef ?? '');
    final viewContentChanged = n.isViewNode
        && _viewContentCtrl.text.trim() != (n.viewContent ?? '');
    // TableColumn / GridTableColumn-specific change detection (CF3.6 — same
    // editor for both variants).
    final tableColKeyChanged = n.isAnyTableColumn
        && _tableColKeyCtrl.text.trim() != (n.dataBinding ?? '');
    final tableColHeaderChanged = n.isAnyTableColumn
        && _tableColHeaderCtrl.text.trim() != (n.viewNodeLabel ?? '');
    final tableColRendererChanged = n.isAnyTableColumn
        && (_selectedTableColRendererRef ?? '') != (n.entityRendererRef ?? '');
    final tableColRestrictChanged = n.isAnyTableColumn
        && _tableColRestrictByVisibleRows != n.restrictByVisibleRows;
    // FilterNode-specific change detection
    final filterTypeChanged = n.isFilterNode
        && _selectedFilterNodeType != (n.typeValue ?? '');
    final filterFieldChanged = n.isFilterNode
        && _filterFieldCtrl.text.trim() != (n.dataBinding ?? '');
    final filterOperatorChanged = n.isFilterNode
        && _selectedFilterOperator != (n.entityValue ?? '');
    final filterValueChanged = n.isFilterNode
        && _filterValueCtrl.text.trim() != (n.viewNodeLabel ?? '');
    // SortField-specific change detection
    final sortFieldChanged = n.isSortField
        && _sortFieldCtrl.text.trim() != (n.dataBinding ?? '');
    final sortDirectionChanged = n.isSortField
        && _selectedSortDirection != (n.typeValue ?? '');
    // Expression-specific change detection
    final exprTypeChanged = n.isExpression
        && _selectedExpressionType != (n.typeValue ?? '');
    final exprBaseClassChanged = n.isExpression
        && _selectedInjectableBaseClass != (n.entityValue ?? '');
    final exprBodyChanged = n.isExpression
        && _expressionBodyCtrl.text != (n.dataBinding ?? '');
    final exprDescChanged = n.isExpression
        && _expressionDescCtrl.text != (n.template ?? '');
    // EntityProvider filterInjectableRef
    final filterInjectableRefChanged = n.isEntityProvider
        && (_selectedFilterInjectableRef ?? '') != (n.filterInjectableRef ?? '');
    // DataFormElement visibility expression ref
    final visibilityExprRefChanged = n.hasTypeField
        && (_selectedVisibilityExpressionRef ?? '') != (n.visibilityExpressionRef ?? '');

    if (!codeChanged && !typeChanged && !entityChanged && !dataBindingChanged
        && !providerRefChanged && !rendererRefChanged && !templateChanged
        && !viewLabelChanged && !viewNodeTypeChanged && !dataFormRefChanged
        && !viewProviderRefChanged && !viewContentChanged
        && !tableColKeyChanged && !tableColHeaderChanged && !tableColRendererChanged
        && !tableColRestrictChanged
        && !filterTypeChanged && !filterFieldChanged && !filterOperatorChanged && !filterValueChanged
        && !sortFieldChanged && !sortDirectionChanged
        && !exprTypeChanged && !exprBaseClassChanged && !exprBodyChanged && !exprDescChanged
        && !filterInjectableRefChanged && !visibilityExprRefChanged) {
      return;
    }

    if (n.isEntityProvider) {
      await _run(() async {
        AppConfigNode? tree = await widget.service.updateEntityProvider(
              providerId: n.id!,
              providerCode: n.label,
              entityTypeNodeId: n.entityNodeId,
              newCode: codeChanged ? code : null,
              newEntityTypeValue: entityChanged ? _selectedEntity : null,
            );
        // FilterInjectableRef
        if (filterInjectableRefChanged) {
          final ref = _selectedFilterInjectableRef;
          if (ref != null && ref.isNotEmpty) {
            if (n.filterInjectableRefNodeId != null) {
              tree = await widget.service.updateNode(n.filterInjectableRefNodeId!, code: ref);
            } else {
              tree = await widget.service.addNode(
                parentObjectId: n.id, typeCode: 'FilterInjectableRef', code: ref,
              );
            }
          }
        }
        return tree;
      });
    } else if (n.isEntityRenderer) {
      await _run(() => widget.service.updateEntityRenderer(
            rendererId: n.id!,
            rendererCode: n.label,
            entityTypeNodeId: n.entityNodeId,
            templateNodeId: n.templateNodeId,
            newCode: codeChanged ? code : null,
            newEntityTypeValue: entityChanged ? _selectedEntity : null,
            newTemplate: templateChanged ? templateText : null,
          ));
    } else if (n.hasEntityField) {
      await _run(() => widget.service.updateDataForm(
            formId: n.id!,
            formCode: n.label,
            entityNodeId: n.entityNodeId,
            newCode: codeChanged ? code : null,
            newEntityValue: entityChanged ? _selectedEntity : null,
          ));
    } else if (n.hasTypeField) {
      await _run(() async {
        AppConfigNode? tree = await widget.service.updateDataFormElementFull(
            elementId: n.id!,
            elementCode: n.label,
            typeNodeId: n.typeNodeId,
            dataBindingNodeId: n.dataBindingNodeId,
            entityProviderRefNodeId: n.entityProviderRefNodeId,
            entityRendererRefNodeId: n.entityRendererRefNodeId,
            newCode: codeChanged ? code : null,
            newTypeValue: typeChanged ? _selectedType : null,
            newDataBinding: dataBindingChanged
                ? (dataBindingText.isEmpty ? null : dataBindingText)
                : null,
            newEntityProviderRef: providerRefChanged
                ? (_selectedEntityProviderRef?.isEmpty ?? true ? null : _selectedEntityProviderRef)
                : null,
            newEntityRendererRef: rendererRefChanged
                ? (_selectedEntityRendererRef?.isEmpty ?? true ? null : _selectedEntityRendererRef)
                : null,
          );
        if (visibilityExprRefChanged) {
          final ref = _selectedVisibilityExpressionRef;
          if (n.visibilityExpressionRefNodeId != null) {
            if (ref != null && ref.isNotEmpty) {
              tree = await widget.service.updateNode(n.visibilityExpressionRefNodeId!, code: ref);
            } else {
              tree = await widget.service.deleteNode(n.visibilityExpressionRefNodeId!);
            }
          } else if (ref != null && ref.isNotEmpty) {
            // Need to create VisibilityRule + VisibilityExpressionRef
            tree = await widget.service.addNode(
              parentObjectId: n.id!, typeCode: 'VisibilityRule',
              code: '${n.label}_visibility',
            );
            // Find the newly created VisibilityRule node to add the ref child
            final visRuleNode = tree?.findChild(n.id!, 'VisibilityRule');
            if (visRuleNode != null) {
              tree = await widget.service.addNode(
                parentObjectId: visRuleNode.id!, typeCode: 'VisibilityExpressionRef',
                code: ref,
              );
            }
          }
        }
        return tree;
      });
    } else if (n.isViewNode) {
      await _run(() async {
        AppConfigNode? tree;
        if (codeChanged) {
          tree = await widget.service.updateNode(n.id!, code: code);
        }
        // ViewNodeType
        final vnTypeChanged = _selectedViewNodeType != (n.typeValue ?? '');
        if (vnTypeChanged) {
          if (n.typeNodeId != null) {
            tree = await widget.service.updateNode(n.typeNodeId!, enumValue: _selectedViewNodeType);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ViewNodeType',
              code: '${code}_type', enumValue: _selectedViewNodeType,
            );
          }
        }
        // Label
        final labelText = _viewLabelCtrl.text.trim();
        final labelChanged = labelText != (n.viewNodeLabel ?? '');
        if (labelChanged) {
          if (n.viewNodeLabelNodeId != null) {
            tree = await widget.service.updateNode(n.viewNodeLabelNodeId!, code: labelText);
          } else if (labelText.isNotEmpty) {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ViewNodeLabel', code: labelText,
            );
          }
        }
        // EntityProviderRef
        final provRefChanged = _selectedEntityProviderRef != (n.entityProviderRef ?? '');
        if (provRefChanged && _selectedEntityProviderRef != null && _selectedEntityProviderRef!.isNotEmpty) {
          if (n.entityProviderRefNodeId != null) {
            tree = await widget.service.updateNode(n.entityProviderRefNodeId!, code: _selectedEntityProviderRef!);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ViewNodeProviderRef', code: _selectedEntityProviderRef!,
            );
          }
        }
        // DataFormRef
        final dfRefChanged = _selectedDataFormRef != (n.dataFormRef ?? '');
        if (dfRefChanged && _selectedDataFormRef != null && _selectedDataFormRef!.isNotEmpty) {
          if (n.dataFormRefNodeId != null) {
            tree = await widget.service.updateNode(n.dataFormRefNodeId!, code: _selectedDataFormRef!);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ViewNodeDataFormRef', code: _selectedDataFormRef!,
            );
          }
        }
        // Content
        final contentText = _viewContentCtrl.text.trim();
        final contentChanged = contentText != (n.viewContent ?? '');
        if (contentChanged && contentText.isNotEmpty) {
          if (n.viewContentNodeId != null) {
            tree = await widget.service.updateNode(n.viewContentNodeId!, code: contentText);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ViewNodeContent', code: contentText,
            );
          }
        }
        return tree;
      });
    } else if (n.isAnyTableColumn) {
      // Same save flow for TableColumn (under ViewNode) and
      // GridTableColumn (under DataFormElement). The parent's typeCode
      // determines which child typeCodes the new key/header/rendererRef
      // nodes should carry. Per columnFilters.md CF3.6.
      final String keyTypeCode =
          n.isGridTableColumn ? 'GridTableColumnKey' : 'TableColumnKey';
      final String headerTypeCode =
          n.isGridTableColumn ? 'GridTableColumnHeader' : 'TableColumnHeader';
      final String rendererRefTypeCode = n.isGridTableColumn
          ? 'GridTableColumnRendererRef'
          : 'TableColumnRendererRef';
      final String restrictTypeCode = n.isGridTableColumn
          ? 'GridTableColumnRestrictByVisibleRows'
          : 'TableColumnRestrictByVisibleRows';
      await _run(() async {
        AppConfigNode? tree;
        if (codeChanged) {
          tree = await widget.service.updateNode(n.id!, code: code);
        }
        final keyText = _tableColKeyCtrl.text.trim();
        final keyChanged = keyText != (n.dataBinding ?? '');
        if (keyChanged && keyText.isNotEmpty) {
          if (n.dataBindingNodeId != null) {
            tree = await widget.service.updateNode(n.dataBindingNodeId!, code: keyText);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: keyTypeCode, code: keyText,
            );
          }
        }
        final headerText = _tableColHeaderCtrl.text.trim();
        final headerChanged = headerText != (n.viewNodeLabel ?? '');
        if (headerChanged && headerText.isNotEmpty) {
          if (n.viewNodeLabelNodeId != null) {
            tree = await widget.service.updateNode(n.viewNodeLabelNodeId!, code: headerText);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: headerTypeCode, code: headerText,
            );
          }
        }
        final renRefChanged = _selectedTableColRendererRef != (n.entityRendererRef ?? '');
        if (renRefChanged && _selectedTableColRendererRef != null && _selectedTableColRendererRef!.isNotEmpty) {
          if (n.entityRendererRefNodeId != null) {
            tree = await widget.service.updateNode(n.entityRendererRefNodeId!, code: _selectedTableColRendererRef!);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: rendererRefTypeCode, code: _selectedTableColRendererRef!,
            );
          }
        }
        // CF3.4.5 — restrictByVisibleRows checkbox. The child node's
        // 'code' carries 'true' / 'false'; backend reads it via
        // Boolean.parseBoolean. NodeId is currently always null
        // (SDL hides *NodeId), so each toggle creates a new child;
        // last-write-wins on read inside AppConfigTreeBuilder.
        if (tableColRestrictChanged) {
          final restrictCode = _tableColRestrictByVisibleRows ? 'true' : 'false';
          if (n.restrictByVisibleRowsNodeId != null) {
            tree = await widget.service.updateNode(
              n.restrictByVisibleRowsNodeId!, code: restrictCode);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: restrictTypeCode,
              code: restrictCode,
            );
          }
        }
        return tree;
      });
    } else if (n.isFilterNode) {
      await _run(() async {
        AppConfigNode? tree;
        if (codeChanged) {
          tree = await widget.service.updateNode(n.id!, code: code);
        }
        if (filterTypeChanged) {
          if (n.typeNodeId != null) {
            tree = await widget.service.updateNode(n.typeNodeId!, enumValue: _selectedFilterNodeType);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'FilterNodeType',
              code: '${code}_type', enumValue: _selectedFilterNodeType,
            );
          }
        }
        final fieldText = _filterFieldCtrl.text.trim();
        if (filterFieldChanged && fieldText.isNotEmpty) {
          if (n.dataBindingNodeId != null) {
            tree = await widget.service.updateNode(n.dataBindingNodeId!, code: fieldText);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'FilterField', code: fieldText,
            );
          }
        }
        if (filterOperatorChanged) {
          if (n.entityNodeId != null) {
            tree = await widget.service.updateNode(n.entityNodeId!, enumValue: _selectedFilterOperator);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'FilterOperator',
              code: '${code}_op', enumValue: _selectedFilterOperator,
            );
          }
        }
        final valText = _filterValueCtrl.text.trim();
        if (filterValueChanged && valText.isNotEmpty) {
          if (n.viewNodeLabelNodeId != null) {
            tree = await widget.service.updateNode(n.viewNodeLabelNodeId!, code: valText);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'FilterValue', code: valText,
            );
          }
        }
        return tree;
      });
    } else if (n.isSortField) {
      await _run(() async {
        AppConfigNode? tree;
        if (codeChanged) {
          tree = await widget.service.updateNode(n.id!, code: code);
        }
        final fieldText = _sortFieldCtrl.text.trim();
        if (sortFieldChanged && fieldText.isNotEmpty) {
          if (n.dataBindingNodeId != null) {
            tree = await widget.service.updateNode(n.dataBindingNodeId!, code: fieldText);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'SortFieldField', code: fieldText,
            );
          }
        }
        if (sortDirectionChanged) {
          if (n.typeNodeId != null) {
            tree = await widget.service.updateNode(n.typeNodeId!, enumValue: _selectedSortDirection);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'SortDirection',
              code: '${code}_dir', enumValue: _selectedSortDirection,
            );
          }
        }
        return tree;
      });
    } else if (n.isExpression) {
      await _run(() async {
        AppConfigNode? tree;
        if (codeChanged) {
          tree = await widget.service.updateNode(n.id!, code: code);
        }
        // ExpressionType
        if (exprTypeChanged) {
          if (n.typeNodeId != null) {
            tree = await widget.service.updateNode(n.typeNodeId!, enumValue: _selectedExpressionType);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ExpressionType',
              code: '${code}_type', enumValue: _selectedExpressionType,
            );
          }
        }
        // InjectableBaseClass
        if (exprBaseClassChanged) {
          if (n.entityNodeId != null) {
            tree = await widget.service.updateNode(n.entityNodeId!, enumValue: _selectedInjectableBaseClass);
          } else {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'InjectableBaseClass',
              code: '${code}_baseClass', enumValue: _selectedInjectableBaseClass,
            );
          }
        }
        // Expression body (source code)
        final bodyText = _expressionBodyCtrl.text;
        if (exprBodyChanged) {
          if (n.dataBindingNodeId != null) {
            tree = await widget.service.updateNode(n.dataBindingNodeId!, code: bodyText);
          } else if (bodyText.isNotEmpty) {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ExpressionBody', code: bodyText,
            );
          }
        }
        // Description
        final descText = _expressionDescCtrl.text;
        if (exprDescChanged) {
          if (n.templateNodeId != null) {
            tree = await widget.service.updateNode(n.templateNodeId!, code: descText);
          } else if (descText.isNotEmpty) {
            tree = await widget.service.addNode(
              parentObjectId: n.id, typeCode: 'ExpressionDescription', code: descText,
            );
          }
        }
        return tree;
      });
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

  Future<void> _onCopy(AppConfigNode n) async {
    final codeCtrl = TextEditingController(text: '${n.label}_copy');
    final newCode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Copy "${n.label}"'),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New code',

            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, codeCtrl.text.trim()),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    codeCtrl.dispose();
    if (newCode != null && newCode.isNotEmpty) {
      await _run(() => widget.service.copyNode(n.id!, newCode));
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
    _dataBindingCtrl.text = c.segment;
    _dataBindingCtrl.selection = TextSelection.collapsed(
        offset: _dataBindingCtrl.text.length);
    setState(() {
      _showCompletions = false;
      _completionIndex = -1;
    });
    // For non-leaf (relationship) completions, auto-switch type to ENTITY_SELECT
    if (!c.leaf && c.suggestedElementType == 'ENTITY_SELECT') {
      setState(() => _selectedType = 'ENTITY_SELECT');
    }
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

  // ---------------------------------------------------------------------------
  // Entity Provider / Renderer ref dropdowns (for ENTITY_SELECT elements)
  // ---------------------------------------------------------------------------

  Widget _entityProviderRefDropdown() {
    final codes = _entityProviderCodes();
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none)')),
      ...codes.map((c) => DropdownMenuItem(value: c, child: Text(c))),
    ];
    return DropdownButtonFormField<String>(
      value: codes.contains(_selectedEntityProviderRef) ? _selectedEntityProviderRef : null,
      decoration: const InputDecoration(
        labelText: 'Entity Provider',

        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _selectedEntityProviderRef = v),
    );
  }

  Widget _entityRendererRefDropdown() {
    final codes = _entityRendererCodes();
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none)')),
      ...codes.map((c) => DropdownMenuItem(value: c, child: Text(c))),
    ];
    return DropdownButtonFormField<String>(
      value: codes.contains(_selectedEntityRendererRef) ? _selectedEntityRendererRef : null,
      decoration: const InputDecoration(
        labelText: 'Entity Renderer',

        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _selectedEntityRendererRef = v),
    );
  }

  Widget _expressionTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedExpressionType,
      decoration: const InputDecoration(
        labelText: 'Expression Type',

        isDense: true,
      ),
      items: _kExpressionTypes
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedExpressionType = v ?? _kExpressionTypes.first),
    );
  }

  Widget _injectableBaseClassDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedInjectableBaseClass,
      decoration: const InputDecoration(
        labelText: 'Base Class',

        isDense: true,
      ),
      items: _kInjectableBaseClasses
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedInjectableBaseClass = v ?? _kInjectableBaseClasses.first),
    );
  }

  Widget _expressionBodyField() {
    return TextFormField(
      controller: _expressionBodyCtrl,
      decoration: const InputDecoration(
        labelText: 'Expression Body',

        alignLabelWithHint: true,
      ),
      maxLines: 4,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
    );
  }

  Widget _expressionEditSourceButton() {
    final n = widget.node;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expression Body (source code)',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        if (_expressionBodyCtrl.text.isNotEmpty)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 160), // ~10 lines
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              color: Colors.grey.shade50,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _expressionBodyCtrl.text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.code, size: 16),
          label: const Text('Edit Source'),
          onPressed: () async {
            final result = await ExpressionEditorDialog.show(
              context,
              expressionCode: n?.label ?? '',
              expressionType: _selectedExpressionType,
              baseClass: _selectedInjectableBaseClass,
              initialSource: _expressionBodyCtrl.text,
            );
            if (result != null) {
              setState(() {
                _expressionBodyCtrl.text = result;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _expressionDescField() {
    return TextFormField(
      controller: _expressionDescCtrl,
      decoration: const InputDecoration(
        labelText: 'Description',

      ),
    );
  }

  Widget _filterInjectableRefDropdown() {
    final codes = _expressionCodes();
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none)')),
      ...codes.map((c) => DropdownMenuItem(value: c, child: Text(c))),
    ];
    return DropdownButtonFormField<String>(
      value: codes.contains(_selectedFilterInjectableRef) ? _selectedFilterInjectableRef : null,
      decoration: const InputDecoration(
        labelText: 'Filter Injectable (Expression)',

        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _selectedFilterInjectableRef = v),
    );
  }

  Widget _visibilityExpressionRefDropdown() {
    final codes = _expressionCodes();
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none — always visible)')),
      ...codes.map((c) => DropdownMenuItem(value: c, child: Text(c))),
    ];
    return DropdownButtonFormField<String>(
      value: codes.contains(_selectedVisibilityExpressionRef) ? _selectedVisibilityExpressionRef : null,
      decoration: const InputDecoration(
        labelText: 'Visibility Expression (Boolean)',
        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _selectedVisibilityExpressionRef = v),
    );
  }

  // ---------------------------------------------------------------------------
  // Mustache template field with auto-proposals (for EntityRenderer)
  // ---------------------------------------------------------------------------

  List<BindingCompletion> _filteredTemplateCompletions(String filter) {
    return _templateCompletions.where((c) {
      if (filter.isEmpty) return true;
      return c.segment.toLowerCase().contains(filter.toLowerCase());
    }).toList();
  }

  Widget _templateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          onKeyEvent: _onTemplateKey,
          child: TextField(
            controller: _templateCtrl,
            focusNode: _templateFocus,
            decoration: const InputDecoration(
              labelText: 'Mustache Template',
  
              isDense: true,
              hintText: '{{name}}{{#field}} ({{field}}){{/field}}',
            ),
            maxLines: 3,
            onChanged: (value) {
              // Check if cursor is right after {{ to trigger completions
              final pos = _templateCtrl.selection.baseOffset;
              if (pos >= 2) {
                final before = value.substring(0, pos);
                final lastOpen = before.lastIndexOf('{{');
                if (lastOpen >= 0) {
                  final afterBraces = before.substring(lastOpen + 2);
                  // Only show completions if we haven't closed the braces yet
                  if (!afterBraces.contains('}}')) {
                    setState(() {
                      _showTemplateCompletions = true;
                      _templateCompletionIndex = -1;
                    });
                    return;
                  }
                }
              }
              setState(() => _showTemplateCompletions = false);
            },
            onTap: () {
              // Show completions on tap if cursor is inside {{ }}
              final pos = _templateCtrl.selection.baseOffset;
              if (pos >= 2) {
                final before = _templateCtrl.text.substring(0, pos);
                final lastOpen = before.lastIndexOf('{{');
                if (lastOpen >= 0 && !before.substring(lastOpen + 2).contains('}}')) {
                  setState(() => _showTemplateCompletions = true);
                }
              }
            },
          ),
        ),
        if (_showTemplateCompletions && _templateCompletions.isNotEmpty)
          _buildTemplateCompletionList(),
      ],
    );
  }

  String _currentTemplateFilter() {
    final pos = _templateCtrl.selection.baseOffset;
    if (pos < 2) return '';
    final before = _templateCtrl.text.substring(0, pos);
    final lastOpen = before.lastIndexOf('{{');
    if (lastOpen < 0) return '';
    final afterBraces = before.substring(lastOpen + 2);
    if (afterBraces.contains('}}')) return '';
    return afterBraces.replaceFirst(RegExp(r'^[#^/]'), '');
  }

  String _currentTemplatePrefix() {
    final pos = _templateCtrl.selection.baseOffset;
    if (pos < 2) return '';
    final before = _templateCtrl.text.substring(0, pos);
    final lastOpen = before.lastIndexOf('{{');
    if (lastOpen < 0) return '';
    final afterBraces = before.substring(lastOpen + 2);
    if (afterBraces.contains('}}')) return '';
    // Return the prefix characters (#, ^, /) if present
    if (afterBraces.startsWith('#') || afterBraces.startsWith('^') || afterBraces.startsWith('/')) {
      return afterBraces.substring(0, 1);
    }
    return '';
  }

  void _acceptTemplateCompletion(BindingCompletion c) {
    final pos = _templateCtrl.selection.baseOffset;
    final text = _templateCtrl.text;
    final before = text.substring(0, pos);
    final lastOpen = before.lastIndexOf('{{');
    if (lastOpen < 0) return;

    final prefix = _currentTemplatePrefix();
    final after = text.substring(pos);
    String insertion;

    if (prefix == '#') {
      // Conditional section: insert field}}...{{/field}}
      insertion = '${c.segment}}}}\u200B{{/${c.segment}}}';
    } else if (prefix == '^') {
      // Inverted section
      insertion = '${c.segment}}}}\u200B{{/${c.segment}}}';
    } else if (prefix == '/') {
      // Closing tag
      insertion = '${c.segment}}}';
    } else {
      // Simple interpolation
      insertion = '${c.segment}}}';
    }

    final newText = text.substring(0, lastOpen + 2 + prefix.length) + insertion + after;
    final cursorPos = lastOpen + 2 + prefix.length + insertion.length;
    _templateCtrl.text = newText;
    _templateCtrl.selection = TextSelection.collapsed(offset: cursorPos);

    setState(() {
      _showTemplateCompletions = false;
      _templateCompletionIndex = -1;
    });
  }

  KeyEventResult _onTemplateKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_showTemplateCompletions || _templateCompletions.isEmpty) {
      return KeyEventResult.ignored;
    }

    final filtered = _filteredTemplateCompletions(_currentTemplateFilter());
    if (filtered.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _templateCompletionIndex = (_templateCompletionIndex + 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _templateCompletionIndex = (_templateCompletionIndex - 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_templateCompletionIndex >= 0 && _templateCompletionIndex < filtered.length) {
        _acceptTemplateCompletion(filtered[_templateCompletionIndex]);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _showTemplateCompletions = false;
        _templateCompletionIndex = -1;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildTemplateCompletionList() {
    final filtered = _filteredTemplateCompletions(_currentTemplateFilter());
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
          final isHighlighted = i == _templateCompletionIndex;
          return InkWell(
            onTap: () => _acceptTemplateCompletion(c),
            child: Container(
              color: isHighlighted ? Colors.blue.shade50 : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    c.leaf ? Icons.text_fields : Icons.link,
                    size: 14,
                    color: isHighlighted ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '{{${c.segment}}}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    c.javaType,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ViewNode-specific fields
  // ---------------------------------------------------------------------------

  Widget _viewNodeTypeDropdown() {
    final value = _kViewNodeTypes.contains(_selectedViewNodeType)
        ? _selectedViewNodeType
        : _kViewNodeTypes.first;
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
        labelText: 'View Node Type',

        isDense: true,
      ),
      items: _kViewNodeTypes
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectedViewNodeType = v);
      },
    );
  }

  Widget _labelField() => TextField(
        controller: _viewLabelCtrl,
        decoration: const InputDecoration(
          labelText: 'Label',
  
          isDense: true,
        ),
      );

  Widget _dataFormRefDropdown() {
    final codes = _dataFormCodes();
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none)')),
      ...codes.map((c) => DropdownMenuItem(value: c, child: Text(c))),
    ];
    return DropdownButtonFormField<String>(
      value: codes.contains(_selectedDataFormRef) ? _selectedDataFormRef : null,
      decoration: const InputDecoration(
        labelText: 'Data Form',

        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _selectedDataFormRef = v),
    );
  }

  Widget _contentField() => TextField(
        controller: _viewContentCtrl,
        decoration: const InputDecoration(
          labelText: 'Content',
  
          isDense: true,
        ),
        maxLines: 3,
      );

  // ---------------------------------------------------------------------------
  // TableColumn-specific fields
  // ---------------------------------------------------------------------------

  /// CF3.6 — extracts the prefix (everything before the last dot) from the
  /// TableColumn key field. Mirrors `_filterFieldPrefix` for FilterNode keys.
  /// E.g., "producer.name" → "producer", "producer." → "producer", "name" → "".
  String _tableColKeyPrefix() {
    final text = _tableColKeyCtrl.text;
    final lastDot = text.lastIndexOf('.');
    if (lastDot < 0) return '';
    return text.substring(0, lastDot);
  }

  /// Last segment (everything after the last dot) — what the proposal list
  /// filters against per CF3.6's dot-path-accumulating completion.
  String _tableColKeyLastSegment() {
    final text = _tableColKeyCtrl.text;
    final lastDot = text.lastIndexOf('.');
    if (lastDot < 0) return text;
    return text.substring(lastDot + 1);
  }

  List<BindingCompletion> _filteredTableColKeyCompletions() {
    final lastSegment = _tableColKeyLastSegment().toLowerCase();
    return _completions.where((c) {
      if (lastSegment.isEmpty) return true;
      final getterName =
          'get${c.segment[0].toUpperCase()}${c.segment.substring(1)}';
      return c.segment.toLowerCase().contains(lastSegment) ||
          getterName.toLowerCase().contains(lastSegment);
    }).toList();
  }

  /// CF3.6 — dot-path-accumulating accept. Leaf segments commit the full
  /// dot-path (`prefix.segment`); non-leaf relationship segments append
  /// `prefix.segment.` and re-fetch the next level's completions so the
  /// user can keep navigating.
  void _acceptTableColKeyCompletion(BindingCompletion c) {
    final prefix = _tableColKeyPrefix();
    if (c.leaf) {
      final fullPath = prefix.isEmpty ? c.segment : '$prefix.${c.segment}';
      _tableColKeyCtrl.text = fullPath;
      _tableColKeyCtrl.selection = TextSelection.collapsed(
          offset: _tableColKeyCtrl.text.length);
      setState(() {
        _showTableColKeyCompletions = false;
        _tableColKeyCompletionIndex = -1;
      });
    } else {
      // Relationship segment — append `.`, fetch the next level.
      final newPrefix = prefix.isEmpty ? c.segment : '$prefix.${c.segment}';
      _tableColKeyCtrl.text = '$newPrefix.';
      _tableColKeyCtrl.selection = TextSelection.collapsed(
          offset: _tableColKeyCtrl.text.length);
      setState(() {
        _tableColKeyCompletionIndex = -1;
      });
      _fetchCompletions(prefix: newPrefix);
    }
  }

  KeyEventResult _onTableColKeyKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_showTableColKeyCompletions || _completions.isEmpty) {
      return KeyEventResult.ignored;
    }
    final filtered = _filteredTableColKeyCompletions();
    if (filtered.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _tableColKeyCompletionIndex = (_tableColKeyCompletionIndex + 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _tableColKeyCompletionIndex = (_tableColKeyCompletionIndex - 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_tableColKeyCompletionIndex >= 0 && _tableColKeyCompletionIndex < filtered.length) {
        _acceptTableColKeyCompletion(filtered[_tableColKeyCompletionIndex]);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _showTableColKeyCompletions = false;
        _tableColKeyCompletionIndex = -1;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _tableColumnKeyField() {
    final entityLabel = _completionEntityLabel ?? _parentEntityType ?? '';
    final hasCompletions = _completions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          onKeyEvent: hasCompletions ? _onTableColKeyKey : null,
          child: TextField(
            controller: _tableColKeyCtrl,
            focusNode: _tableColKeyFocus,
            decoration: InputDecoration(
              labelText: 'Key (entity attribute, dot-path)',

              isDense: true,
              prefixText: hasCompletions ? '$entityLabel.' : null,
              prefixStyle: const TextStyle(
                  color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            onChanged: (value) {
              // CF3.6 — re-fetch completions whenever the prefix segment
              // changes (user typed `.` or modified text before the last
              // dot). Mirrors the FilterField dot-path completion.
              final lastDot = value.lastIndexOf('.');
              if (lastDot >= 0) {
                _fetchCompletions(prefix: value.substring(0, lastDot));
              } else {
                _fetchCompletions();
              }
              setState(() {
                _showTableColKeyCompletions = true;
                _tableColKeyCompletionIndex = -1;
              });
            },
            onTap: () {
              if (hasCompletions) {
                setState(() => _showTableColKeyCompletions = true);
              }
            },
          ),
        ),
        if (_showTableColKeyCompletions && _completions.isNotEmpty)
          _buildTableColKeyCompletionList(),
      ],
    );
  }

  Widget _buildTableColKeyCompletionList() {
    final filtered = _filteredTableColKeyCompletions();
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
          final isHighlighted = i == _tableColKeyCompletionIndex;

          return InkWell(
            onTap: () => _acceptTableColKeyCompletion(c),
            child: Container(
              color: isHighlighted ? Colors.blue.shade50 : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    c.leaf ? Icons.text_fields : Icons.link,
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

  Widget _tableColumnHeaderField() => TextField(
        controller: _tableColHeaderCtrl,
        decoration: const InputDecoration(
          labelText: 'Header (display text)',
  
          isDense: true,
        ),
      );

  Widget _tableColumnRendererDropdown() {
    final codes = _entityRendererCodes();
    final items = [
      const DropdownMenuItem<String>(value: null, child: Text('(none)')),
      ...codes.map((c) => DropdownMenuItem(value: c, child: Text(c))),
    ];
    return DropdownButtonFormField<String>(
      value: codes.contains(_selectedTableColRendererRef) ? _selectedTableColRendererRef : null,
      decoration: const InputDecoration(
        labelText: 'Renderer (for relationship columns)',

        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _selectedTableColRendererRef = v),
    );
  }

  /// CF3.4.5 — admin opt-out for the visible-rows restriction. Default
  /// true (mirrors backend). Affects ENUM dropdowns and ENTITY_REF
  /// pickers; no effect for STRING / NUMBER / DATE / BOOLEAN.
  Widget _tableColumnRestrictByVisibleRowsCheckbox() {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: const Text('Restrict filter options to visible rows'),
      subtitle: const Text(
        'When on, ENUM and ENTITY_REF filter inputs only show values '
        'present in the rows that match the column\'s other filters. '
        'No effect on STRING / NUMBER / DATE / BOOLEAN columns.',
        style: TextStyle(fontSize: 11),
      ),
      value: _tableColRestrictByVisibleRows,
      onChanged: (v) =>
          setState(() => _tableColRestrictByVisibleRows = v ?? true),
    );
  }

  // ---------------------------------------------------------------------------
  // FilterNode-specific fields
  // ---------------------------------------------------------------------------

  Widget _filterNodeTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _kFilterNodeTypes.contains(_selectedFilterNodeType)
          ? _selectedFilterNodeType : _kFilterNodeTypes.first,
      decoration: const InputDecoration(
        labelText: 'Filter Type',

        isDense: true,
      ),
      items: _kFilterNodeTypes
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectedFilterNodeType = v);
      },
    );
  }

  /// Extracts the prefix (all segments before the last dot) from the filter field.
  /// E.g., "producer.name" → prefix="producer", lastSegment="name"
  /// E.g., "producer." → prefix="producer", lastSegment=""
  /// E.g., "name" → prefix="", lastSegment="name"
  String _filterFieldPrefix() {
    final text = _filterFieldCtrl.text;
    final lastDot = text.lastIndexOf('.');
    if (lastDot < 0) return '';
    return text.substring(0, lastDot);
  }

  String _filterFieldLastSegment() {
    final text = _filterFieldCtrl.text;
    final lastDot = text.lastIndexOf('.');
    if (lastDot < 0) return text;
    return text.substring(lastDot + 1);
  }

  Widget _filterFieldField() {
    final entityLabel = _completionEntityLabel ?? _parentEntityType ?? '';
    final hasCompletions = _completions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _filterFieldCtrl,
          decoration: InputDecoration(
            labelText: 'Field (dot-path)',


            isDense: true,
            prefixText: hasCompletions ? '$entityLabel.' : null,
            prefixStyle: const TextStyle(
                color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          onChanged: (value) {
            // Determine the prefix (everything before the last dot)
            final lastDot = value.lastIndexOf('.');
            if (lastDot >= 0) {
              final prefix = value.substring(0, lastDot);
              // Re-fetch whenever the prefix segment changes
              _fetchCompletions(prefix: prefix);
            } else {
              // No dot — back to root level
              _fetchCompletions();
            }
            setState(() {});
          },
          onTap: () => setState(() {}),
        ),
        if (_completions.isNotEmpty) _buildFilterFieldCompletionList(),
      ],
    );
  }

  Widget _buildFilterFieldCompletionList() {
    final lastSegment = _filterFieldLastSegment().toLowerCase();
    final filtered = _completions.where((c) {
      if (lastSegment.isEmpty) return true;
      return c.segment.toLowerCase().contains(lastSegment);
    }).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 2),
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemExtent: 32,
        itemBuilder: (context, i) {
          final c = filtered[i];
          final prefix = _filterFieldPrefix();
          return InkWell(
            onTap: () {
              if (c.leaf) {
                // Leaf: set the full dot-path
                final fullPath = prefix.isEmpty ? c.segment : '$prefix.${c.segment}';
                _filterFieldCtrl.text = fullPath;
                _filterFieldCtrl.selection = TextSelection.collapsed(
                    offset: fullPath.length);
                setState(() {});
              } else {
                // Non-leaf (relationship): append segment + dot, fetch next level
                final newPrefix = prefix.isEmpty ? c.segment : '$prefix.${c.segment}';
                _filterFieldCtrl.text = '$newPrefix.';
                _filterFieldCtrl.selection = TextSelection.collapsed(
                    offset: _filterFieldCtrl.text.length);
                _fetchCompletions(prefix: newPrefix);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(c.leaf ? Icons.text_fields : Icons.arrow_forward,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.segment,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                  Text(c.javaType,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filterOperatorDropdown() {
    return DropdownButtonFormField<String>(
      value: _kFilterOperators.contains(_selectedFilterOperator)
          ? _selectedFilterOperator : _kFilterOperators.first,
      decoration: const InputDecoration(
        labelText: 'Operator',

        isDense: true,
      ),
      items: _kFilterOperators
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectedFilterOperator = v);
      },
    );
  }

  Widget _filterValueField() => TextField(
        controller: _filterValueCtrl,
        decoration: const InputDecoration(
          labelText: 'Value',
  
          isDense: true,
        ),
      );

  // ---------------------------------------------------------------------------
  // SortField-specific fields
  // ---------------------------------------------------------------------------

  Widget _sortFieldField() {
    final entityLabel = _completionEntityLabel ?? _parentEntityType ?? '';
    final hasCompletions = _completions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _sortFieldCtrl,
          decoration: InputDecoration(
            labelText: 'Field (dot-path)',


            isDense: true,
            prefixText: hasCompletions ? '$entityLabel.' : null,
            prefixStyle: const TextStyle(
                color: Colors.grey, fontWeight: FontWeight.w500),
          ),
          onChanged: (_) => setState(() {}),
          onTap: () => setState(() {}),
        ),
        if (_completions.isNotEmpty) _buildSortFieldCompletionList(),
      ],
    );
  }

  Widget _buildSortFieldCompletionList() {
    final filter = _sortFieldCtrl.text.toLowerCase();
    final filtered = _completions.where((c) {
      if (filter.isEmpty) return true;
      return c.segment.toLowerCase().contains(filter);
    }).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 2),
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filtered.length,
        itemExtent: 32,
        itemBuilder: (context, i) {
          final c = filtered[i];
          return InkWell(
            onTap: () {
              _sortFieldCtrl.text = c.segment;
              _sortFieldCtrl.selection = TextSelection.collapsed(
                  offset: c.segment.length);
              setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(c.leaf ? Icons.text_fields : Icons.link,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.segment,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
                  Text(c.javaType,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sortDirectionDropdown() {
    return DropdownButtonFormField<String>(
      value: _kSortDirections.contains(_selectedSortDirection)
          ? _selectedSortDirection : _kSortDirections.first,
      decoration: const InputDecoration(
        labelText: 'Direction',

        isDense: true,
      ),
      items: _kSortDirections
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectedSortDirection = v);
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
