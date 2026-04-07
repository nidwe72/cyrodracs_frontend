enum AppConfigNodeKind { instance, collection }

/// A node in the client-side AppConfig tree.
///
/// Two kinds exist:
/// * [AppConfigNodeKind.instance] – a concrete Coded object (AppConfig, DataForm,
///   DataFormElement).  Carries a DB [id], a [typeCode], and optionally a
///   [typeValue] / [typeNodeId] for DataFormElement nodes.
/// * [AppConfigNodeKind.collection] – a named grouping of instance children
///   (e.g. "dataForms", "elements").  Carries [childTypeCode] (the type to create
///   when adding a child) and [parentId] (the DB id of the enclosing instance node).
class AppConfigNode {
  final String label;
  final AppConfigNodeKind kind;

  // instance-node fields
  final int? id;
  final String? typeCode;
  final String? typeValue;       // rendered enum value on DataFormElement
  final int? typeNodeId;         // DB id of the DataFormElementType child object
  final String? dataBinding;     // entity attribute path on DataFormElement
  final int? dataBindingNodeId;  // DB id of the DataBinding child object
  final String? entityValue;     // rendered enum value on DataForm (DataFormEntityType)
  final int? entityNodeId;       // DB id of the DataFormEntityType child object
  final String? entityProviderRef;     // EntityProvider code ref on DataFormElement
  final int? entityProviderRefNodeId;
  final String? entityRendererRef;     // EntityRenderer code ref on DataFormElement
  final int? entityRendererRefNodeId;
  final String? template;              // Mustache template on EntityRenderer
  final int? templateNodeId;
  final String? filterInjectableRef;   // Expression code ref on EntityProvider
  final int? filterInjectableRefNodeId;

  // ViewNode fields
  final String? viewNodeLabel;         // display label on ViewNode
  final int? viewNodeLabelNodeId;
  final String? dataFormRef;           // DataForm code ref on ViewNode
  final int? dataFormRefNodeId;
  final String? viewContent;           // content identifier on STATIC_PAGE
  final int? viewContentNodeId;

  // collection-node fields
  final String? childTypeCode; // typeCode of children, e.g. "DataForm"
  final int? parentId;         // DB id of the enclosing instance node

  final List<AppConfigNode> children;

  const AppConfigNode({
    required this.label,
    required this.kind,
    required this.children,
    this.id,
    this.typeCode,
    this.typeValue,
    this.typeNodeId,
    this.dataBinding,
    this.dataBindingNodeId,
    this.entityValue,
    this.entityNodeId,
    this.entityProviderRef,
    this.entityProviderRefNodeId,
    this.entityRendererRef,
    this.entityRendererRefNodeId,
    this.template,
    this.templateNodeId,
    this.filterInjectableRef,
    this.filterInjectableRefNodeId,
    this.viewNodeLabel,
    this.viewNodeLabelNodeId,
    this.dataFormRef,
    this.dataFormRefNodeId,
    this.viewContent,
    this.viewContentNodeId,
    this.childTypeCode,
    this.parentId,
  });

  bool get isInstance => kind == AppConfigNodeKind.instance;
  bool get isCollection => kind == AppConfigNodeKind.collection;

  /// True for instance nodes that may be deleted (everything except the root AppConfig).
  bool get isDeletable => isInstance && typeCode != 'AppConfig';

  /// True when this instance node exposes a "type" enum field (DataFormElement).
  bool get hasTypeField => typeCode == 'DataFormElement';

  /// True when this instance node exposes an "entity" enum field (DataForm).
  bool get hasEntityField => typeCode == 'DataForm';

  /// True when this instance node exposes a "dataBinding" field (DataFormElement).
  bool get hasDataBindingField => typeCode == 'DataFormElement';

  /// True when this instance node exposes entityProvider/entityRenderer ref fields.
  bool get hasEntitySelectFields => typeCode == 'DataFormElement';

  /// True for EntityProvider nodes.
  bool get isEntityProvider => typeCode == 'EntityProvider';

  /// True for EntityRenderer nodes.
  bool get isEntityRenderer => typeCode == 'EntityRenderer';

  /// True when this node exposes a template field (EntityRenderer).
  bool get hasTemplateField => typeCode == 'EntityRenderer';

  /// True for ViewNode nodes.
  bool get isViewNode => typeCode == 'ViewNode';

  /// True for TableColumn nodes.
  bool get isTableColumn => typeCode == 'TableColumn';

  /// True for Expression nodes.
  bool get isExpression => typeCode == 'Expression';

  /// True for FilterNode nodes.
  bool get isFilterNode => typeCode == 'FilterNode';

  /// True for SortField nodes.
  bool get isSortField => typeCode == 'SortField';

  // ---------------------------------------------------------------------------
  // JSON parsing
  // ---------------------------------------------------------------------------

  static AppConfigNode fromJson(Map<String, dynamic> json) {
    final rootId = (json['id'] as num).toInt();
    final rootCode = json['code'] as String;

    // --- DataForms ---
    final dataFormsRaw =
        (json['dataForms'] as Map<String, dynamic>?) ?? {};
    final dataFormNodes = <AppConfigNode>[];

    for (final formEntry in dataFormsRaw.entries) {
      final form = formEntry.value as Map<String, dynamic>;
      final formId = (form['id'] as num).toInt();
      final formCode = form['code'] as String;

      final elementsRaw =
          (form['elements'] as Map<String, dynamic>?) ?? {};
      final elementNodes = <AppConfigNode>[];

      for (final elemEntry in elementsRaw.entries) {
        final elem = elemEntry.value as Map<String, dynamic>;
        final elemId = (elem['id'] as num?)?.toInt();
        final elemType = elem['type'] as String?;

        // Parse GridTableColumn children for GRID elements
        final gridColumnNodes = <AppConfigNode>[];
        final columnsRaw = (elem['tableColumns'] as List<dynamic>?) ?? [];
        for (final col in columnsRaw) {
          final c = col as Map<String, dynamic>;
          gridColumnNodes.add(AppConfigNode(
            label: c['code'] as String,
            kind: AppConfigNodeKind.instance,
            id: (c['id'] as num?)?.toInt(),
            typeCode: 'TableColumn',
            dataBinding: c['key'] as String?,
            dataBindingNodeId: (c['keyNodeId'] as num?)?.toInt(),
            viewNodeLabel: c['header'] as String?,
            viewNodeLabelNodeId: (c['headerNodeId'] as num?)?.toInt(),
            entityRendererRef: c['entityRendererRef'] as String?,
            entityRendererRefNodeId: (c['entityRendererRefNodeId'] as num?)?.toInt(),
            children: const [],
          ));
        }

        // Parse AddAction for GRID elements
        final addActionRaw = elem['addAction'] as Map<String, dynamic>?;
        AppConfigNode? addActionNode;
        if (addActionRaw != null && addActionRaw['targetDataFormRef'] != null) {
          final bindingsRaw = (addActionRaw['contextBindings'] as List<dynamic>?) ?? [];
          final bindingNodes = <AppConfigNode>[];
          for (final b in bindingsRaw) {
            final bm = b as Map<String, dynamic>;
            bindingNodes.add(AppConfigNode(
              label: bm['code'] as String? ?? '',
              kind: AppConfigNodeKind.instance,
              id: (bm['id'] as num?)?.toInt(),
              typeCode: 'ContextBinding',
              children: [
                AppConfigNode(
                  label: bm['target'] as String? ?? '',
                  kind: AppConfigNodeKind.instance,
                  typeCode: 'ContextBindingTarget',
                  children: const [],
                ),
                AppConfigNode(
                  label: bm['source'] as String? ?? '',
                  kind: AppConfigNodeKind.instance,
                  typeCode: 'ContextBindingSource',
                  children: const [],
                ),
              ],
            ));
          }
          addActionNode = AppConfigNode(
            label: addActionRaw['code'] as String? ?? 'addAction',
            kind: AppConfigNodeKind.instance,
            id: (addActionRaw['id'] as num?)?.toInt(),
            typeCode: 'AddAction',
            children: [
              AppConfigNode(
                label: addActionRaw['targetDataFormRef'] as String? ?? '',
                kind: AppConfigNodeKind.instance,
                typeCode: 'AddActionTarget',
                children: const [],
              ),
              if (addActionRaw['childLabel'] != null)
                AppConfigNode(
                  label: addActionRaw['childLabel'] as String,
                  kind: AppConfigNodeKind.instance,
                  typeCode: 'AddActionLabel',
                  children: const [],
                ),
              AppConfigNode(
                label: 'contextBindings',
                kind: AppConfigNodeKind.collection,
                childTypeCode: 'ContextBinding',
                children: bindingNodes,
              ),
            ],
          );
        }

        final elemChildren = <AppConfigNode>[];
        if (elemType == 'GRID' || gridColumnNodes.isNotEmpty) {
          elemChildren.add(AppConfigNode(
            label: 'tableColumns',
            kind: AppConfigNodeKind.collection,
            childTypeCode: 'GridTableColumn',
            parentId: elemId,
            children: gridColumnNodes,
          ));
        }
        if (addActionNode != null) {
          elemChildren.add(addActionNode);
        }

        elementNodes.add(AppConfigNode(
          label: elem['code'] as String,
          kind: AppConfigNodeKind.instance,
          id: elemId,
          typeCode: 'DataFormElement',
          typeValue: elemType,
          typeNodeId: (elem['typeNodeId'] as num?)?.toInt(),
          dataBinding: elem['dataBinding'] as String?,
          dataBindingNodeId: (elem['dataBindingNodeId'] as num?)?.toInt(),
          entityProviderRef: elem['entityProviderRef'] as String?,
          entityProviderRefNodeId: (elem['entityProviderRefNodeId'] as num?)?.toInt(),
          entityRendererRef: elem['entityRendererRef'] as String?,
          entityRendererRefNodeId: (elem['entityRendererRefNodeId'] as num?)?.toInt(),
          children: elemChildren,
        ));
      }

      dataFormNodes.add(AppConfigNode(
        label: formCode,
        kind: AppConfigNodeKind.instance,
        id: formId,
        typeCode: 'DataForm',
        entityValue: form['entity'] as String?,
        entityNodeId: (form['entityNodeId'] as num?)?.toInt(),
        children: [
          AppConfigNode(
            label: 'elements',
            kind: AppConfigNodeKind.collection,
            childTypeCode: 'DataFormElement',
            parentId: formId,
            children: elementNodes,
          ),
        ],
      ));
    }

    // --- EntityProviders ---
    final providersRaw =
        (json['entityProviders'] as Map<String, dynamic>?) ?? {};
    final providerNodes = <AppConfigNode>[];

    for (final provEntry in providersRaw.entries) {
      final prov = provEntry.value as Map<String, dynamic>;
      final provId = (prov['id'] as num?)?.toInt();
      final provChildren = <AppConfigNode>[];

      // Parse filter — wrap in a collection-like node so the admin can add/manage it
      final filterChildren = <AppConfigNode>[];
      if (prov['filter'] != null) {
        final filterNode = _parseFilterNode(prov['filter'] as Map<String, dynamic>);
        filterChildren.add(filterNode);
      }
      provChildren.add(AppConfigNode(
        label: 'filter',
        kind: AppConfigNodeKind.collection,
        childTypeCode: 'FilterNode',
        parentId: provId,
        children: filterChildren,
      ));

      // Parse sortFields (always show collection so user can add)
      final sortFieldsRaw = (prov['sortFields'] as List<dynamic>?) ?? [];
      final sortNodes = <AppConfigNode>[];
      for (final sf in sortFieldsRaw) {
        final s = sf as Map<String, dynamic>;
        sortNodes.add(AppConfigNode(
          label: s['code'] as String,
          kind: AppConfigNodeKind.instance,
          id: (s['id'] as num?)?.toInt(),
          typeCode: 'SortField',
          dataBinding: s['field'] as String?,
          dataBindingNodeId: (s['fieldNodeId'] as num?)?.toInt(),
          typeValue: s['direction'] as String?,
          typeNodeId: (s['directionNodeId'] as num?)?.toInt(),
          children: const [],
        ));
      }
      provChildren.add(AppConfigNode(
        label: 'sortFields',
        kind: AppConfigNodeKind.collection,
        childTypeCode: 'SortField',
        parentId: provId,
        children: sortNodes,
      ));

      providerNodes.add(AppConfigNode(
        label: prov['code'] as String,
        kind: AppConfigNodeKind.instance,
        id: provId,
        typeCode: 'EntityProvider',
        entityValue: prov['entityType'] as String?,
        entityNodeId: (prov['entityTypeNodeId'] as num?)?.toInt(),
        filterInjectableRef: prov['filterInjectableRef'] as String?,
        filterInjectableRefNodeId: (prov['filterInjectableRefNodeId'] as num?)?.toInt(),
        children: provChildren,
      ));
    }

    // --- EntityRenderers ---
    final renderersRaw =
        (json['entityRenderers'] as Map<String, dynamic>?) ?? {};
    final rendererNodes = <AppConfigNode>[];

    for (final renEntry in renderersRaw.entries) {
      final ren = renEntry.value as Map<String, dynamic>;
      rendererNodes.add(AppConfigNode(
        label: ren['code'] as String,
        kind: AppConfigNodeKind.instance,
        id: (ren['id'] as num?)?.toInt(),
        typeCode: 'EntityRenderer',
        entityValue: ren['entityType'] as String?,
        entityNodeId: (ren['entityTypeNodeId'] as num?)?.toInt(),
        template: ren['template'] as String?,
        templateNodeId: (ren['templateNodeId'] as num?)?.toInt(),
        children: const [],
      ));
    }

    // --- ViewTree ---
    final viewTreeRaw =
        (json['viewTree'] as Map<String, dynamic>?) ?? {};
    final viewNodeNodes = <AppConfigNode>[];

    for (final vnEntry in viewTreeRaw.entries) {
      viewNodeNodes.add(_parseViewNode(vnEntry.value as Map<String, dynamic>));
    }

    // --- Expressions ---
    final expressionsRaw =
        (json['expressions'] as Map<String, dynamic>?) ?? {};
    final expressionNodes = <AppConfigNode>[];

    for (final exprEntry in expressionsRaw.entries) {
      final expr = exprEntry.value as Map<String, dynamic>;
      expressionNodes.add(AppConfigNode(
        label: expr['code'] as String,
        kind: AppConfigNodeKind.instance,
        id: (expr['id'] as num?)?.toInt(),
        typeCode: 'Expression',
        typeValue: expr['type'] as String?,
        typeNodeId: (expr['typeNodeId'] as num?)?.toInt(),
        entityValue: expr['baseClass'] as String?,
        entityNodeId: (expr['baseClassNodeId'] as num?)?.toInt(),
        dataBinding: expr['expression'] as String?,
        dataBindingNodeId: (expr['expressionNodeId'] as num?)?.toInt(),
        template: expr['description'] as String?,
        templateNodeId: (expr['descriptionNodeId'] as num?)?.toInt(),
        children: const [],
      ));
    }

    return AppConfigNode(
      label: rootCode,
      kind: AppConfigNodeKind.instance,
      id: rootId,
      typeCode: 'AppConfig',
      children: [
        AppConfigNode(
          label: 'dataForms',
          kind: AppConfigNodeKind.collection,
          childTypeCode: 'DataForm',
          parentId: rootId,
          children: dataFormNodes,
        ),
        AppConfigNode(
          label: 'entityProviders',
          kind: AppConfigNodeKind.collection,
          childTypeCode: 'EntityProvider',
          parentId: rootId,
          children: providerNodes,
        ),
        AppConfigNode(
          label: 'entityRenderers',
          kind: AppConfigNodeKind.collection,
          childTypeCode: 'EntityRenderer',
          parentId: rootId,
          children: rendererNodes,
        ),
        AppConfigNode(
          label: 'viewTree',
          kind: AppConfigNodeKind.collection,
          childTypeCode: 'ViewNode',
          parentId: rootId,
          children: viewNodeNodes,
        ),
        AppConfigNode(
          label: 'expressions',
          kind: AppConfigNodeKind.collection,
          childTypeCode: 'Expression',
          parentId: rootId,
          children: expressionNodes,
        ),
      ],
    );
  }

  static AppConfigNode _parseViewNode(Map<String, dynamic> vn) {
    final vnId = (vn['id'] as num?)?.toInt();
    final vnCode = vn['code'] as String;
    final vnType = vn['type'] as String?;
    final vnLabel = vn['label'] as String?;

    // Parse children (recursive)
    final childrenRaw = (vn['children'] as List<dynamic>?) ?? [];
    final childViewNodes = <AppConfigNode>[];
    for (final child in childrenRaw) {
      childViewNodes.add(_parseViewNode(child as Map<String, dynamic>));
    }

    // Parse tableColumns
    final columnsRaw = (vn['tableColumns'] as List<dynamic>?) ?? [];
    final columnNodes = <AppConfigNode>[];
    for (final col in columnsRaw) {
      final c = col as Map<String, dynamic>;
      columnNodes.add(AppConfigNode(
        label: c['code'] as String,
        kind: AppConfigNodeKind.instance,
        id: (c['id'] as num?)?.toInt(),
        typeCode: 'TableColumn',
        dataBinding: c['key'] as String?,
        dataBindingNodeId: (c['keyNodeId'] as num?)?.toInt(),
        viewNodeLabel: c['header'] as String?,
        viewNodeLabelNodeId: (c['headerNodeId'] as num?)?.toInt(),
        entityRendererRef: c['entityRendererRef'] as String?,
        entityRendererRefNodeId: (c['entityRendererRefNodeId'] as num?)?.toInt(),
        children: const [],
      ));
    }

    // Build instance children list — always show collections so user can add items
    final instanceChildren = <AppConfigNode>[];
    // Always show 'children' collection for GROUP nodes (or any node that might nest)
    if (vnType == 'GROUP' || childViewNodes.isNotEmpty) {
      instanceChildren.add(AppConfigNode(
        label: 'children',
        kind: AppConfigNodeKind.collection,
        childTypeCode: 'ViewNode',
        parentId: vnId,
        children: childViewNodes,
      ));
    }
    // Always show 'tableColumns' collection for ENTITY_LIST nodes
    if (vnType == 'ENTITY_LIST' || columnNodes.isNotEmpty) {
      instanceChildren.add(AppConfigNode(
        label: 'tableColumns',
        kind: AppConfigNodeKind.collection,
        childTypeCode: 'TableColumn',
        parentId: vnId,
        children: columnNodes,
      ));
    }

    return AppConfigNode(
      label: vnCode,
      kind: AppConfigNodeKind.instance,
      id: vnId,
      typeCode: 'ViewNode',
      typeValue: vnType,
      typeNodeId: (vn['typeNodeId'] as num?)?.toInt(),
      viewNodeLabel: vnLabel,
      viewNodeLabelNodeId: (vn['labelNodeId'] as num?)?.toInt(),
      entityProviderRef: vn['entityProviderRef'] as String?,
      entityProviderRefNodeId: (vn['entityProviderRefNodeId'] as num?)?.toInt(),
      dataFormRef: vn['dataFormRef'] as String?,
      dataFormRefNodeId: (vn['dataFormRefNodeId'] as num?)?.toInt(),
      viewContent: vn['content'] as String?,
      viewContentNodeId: (vn['contentNodeId'] as num?)?.toInt(),
      children: instanceChildren,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers used by the service after mutations
  // ---------------------------------------------------------------------------

  static AppConfigNode _parseFilterNode(Map<String, dynamic> fn) {
    final fnId = (fn['id'] as num?)?.toInt();
    final fnCode = fn['code'] as String;

    // Parse children (recursive AND_GROUP / OR_GROUP)
    final childrenRaw = (fn['children'] as List<dynamic>?) ?? [];
    final childNodes = <AppConfigNode>[];
    for (final child in childrenRaw) {
      childNodes.add(_parseFilterNode(child as Map<String, dynamic>));
    }

    // Parse IN values
    final valuesRaw = (fn['values'] as List<dynamic>?) ?? [];
    final valueItems = valuesRaw.map((v) => v.toString()).toList();

    final fnType = fn['type'] as String?;
    final instanceChildren = <AppConfigNode>[];
    // Always show children collection for group types so user can add conditions
    if (fnType == 'AND_GROUP' || fnType == 'OR_GROUP' || childNodes.isNotEmpty) {
      instanceChildren.add(AppConfigNode(
        label: 'children',
        kind: AppConfigNodeKind.collection,
        childTypeCode: 'FilterNode',
        parentId: fnId,
        children: childNodes,
      ));
    }

    return AppConfigNode(
      label: fnCode,
      kind: AppConfigNodeKind.instance,
      id: fnId,
      typeCode: 'FilterNode',
      typeValue: fnType,
      typeNodeId: (fn['typeNodeId'] as num?)?.toInt(),
      dataBinding: fn['field'] as String?,         // filter field (dot-path)
      dataBindingNodeId: (fn['fieldNodeId'] as num?)?.toInt(),
      entityValue: fn['operator'] as String?,      // FilterOperator enum (reuse entityValue field)
      entityNodeId: (fn['operatorNodeId'] as num?)?.toInt(),
      viewNodeLabel: fn['value'] as String?,       // comparison value (reuse viewNodeLabel)
      viewNodeLabelNodeId: (fn['valueNodeId'] as num?)?.toInt(),
      viewContent: valueItems.join(','),           // IN values as comma-separated (reuse viewContent)
      children: instanceChildren,
    );
  }

  /// Finds a DataFormElement by its parent DataForm's id and the element's code.
  /// Used after adding a new element to retrieve its assigned DB id.
  AppConfigNode? findDataFormElement(int formId, String elementCode) {
    for (final child in children) {
      if (child.isCollection && child.label == 'dataForms') {
        for (final form in child.children) {
          if (form.id == formId) {
            for (final coll in form.children) {
              if (coll.isCollection && coll.label == 'elements') {
                for (final elem in coll.children) {
                  if (elem.label == elementCode) return elem;
                }
              }
            }
          }
        }
      }
    }
    return null;
  }
}
