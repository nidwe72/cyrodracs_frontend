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
        elementNodes.add(AppConfigNode(
          label: elem['code'] as String,
          kind: AppConfigNodeKind.instance,
          id: (elem['id'] as num?)?.toInt(),
          typeCode: 'DataFormElement',
          typeValue: elem['type'] as String?,
          typeNodeId: (elem['typeNodeId'] as num?)?.toInt(),
          dataBinding: elem['dataBinding'] as String?,
          dataBindingNodeId: (elem['dataBindingNodeId'] as num?)?.toInt(),
          entityProviderRef: elem['entityProviderRef'] as String?,
          entityProviderRefNodeId: (elem['entityProviderRefNodeId'] as num?)?.toInt(),
          entityRendererRef: elem['entityRendererRef'] as String?,
          entityRendererRefNodeId: (elem['entityRendererRefNodeId'] as num?)?.toInt(),
          children: const [],
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
      providerNodes.add(AppConfigNode(
        label: prov['code'] as String,
        kind: AppConfigNodeKind.instance,
        id: (prov['id'] as num?)?.toInt(),
        typeCode: 'EntityProvider',
        entityValue: prov['entityType'] as String?,
        entityNodeId: (prov['entityTypeNodeId'] as num?)?.toInt(),
        children: const [],
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
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers used by the service after mutations
  // ---------------------------------------------------------------------------

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
