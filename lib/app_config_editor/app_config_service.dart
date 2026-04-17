import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_config_node.dart';

class BindingCompletion {
  final String segment;
  final String javaType;
  final bool leaf;
  final String? suggestedElementType;
  final String? referencedEntityType;

  const BindingCompletion({
    required this.segment,
    required this.javaType,
    required this.leaf,
    this.suggestedElementType,
    this.referencedEntityType,
  });

  factory BindingCompletion.fromJson(Map<String, dynamic> json) {
    return BindingCompletion(
      segment: json['segment'] as String,
      javaType: json['javaType'] as String,
      leaf: json['leaf'] as bool,
      suggestedElementType: json['suggestedElementType'] as String?,
      referencedEntityType: json['referencedEntityType'] as String?,
    );
  }
}

class EntityOption {
  final int id;
  final String label;

  const EntityOption({required this.id, required this.label});

  factory EntityOption.fromJson(Map<String, dynamic> json) {
    return EntityOption(
      id: (json['id'] as num).toInt(),
      label: json['label'] as String,
    );
  }
}

class ElementState {
  final bool visible;
  final List<EntityOption>? options;

  const ElementState({required this.visible, this.options});

  factory ElementState.fromJson(Map<String, dynamic> json) {
    return ElementState(
      visible: json['visible'] as bool? ?? true,
      options: json['options'] != null
          ? (json['options'] as List<dynamic>)
              .map((e) => EntityOption.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

class BindingProposalResponse {
  final String entityLabel;
  final List<BindingCompletion> completions;

  const BindingProposalResponse({
    required this.entityLabel,
    required this.completions,
  });

  factory BindingProposalResponse.fromJson(Map<String, dynamic> json) {
    return BindingProposalResponse(
      entityLabel: json['entityLabel'] as String,
      completions: (json['completions'] as List<dynamic>)
          .map((e) => BindingCompletion.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AppConfigService {
  static const _base = 'http://localhost:8080/api/app-config';
  static const _bindingBase = 'http://localhost:8080/api/data-binding';
  static const _entitySelectBase = 'http://localhost:8080/api/entity-select';
  static const _dataFormBase = 'http://localhost:8080/api/data-form';

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  Future<AppConfigNode?> fetchTree() async {
    final response = await http.get(Uri.parse(_base));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Failed to load AppConfig: HTTP ${response.statusCode}');
    }
    return AppConfigNode.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Mutations – all return the updated tree on success
  // ---------------------------------------------------------------------------

  Future<AppConfigNode?> addNode({
    required int? parentObjectId,
    required String typeCode,
    required String code,
    String? enumValue,
  }) async {
    final body = <String, dynamic>{
      'typeCode': typeCode,
      'code': code,
      if (parentObjectId != null) 'parentObjectId': parentObjectId,
      if (enumValue != null) 'enumValue': enumValue,
    };
    final response = await http.post(
      Uri.parse('$_base/node'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to add node: HTTP ${response.statusCode}');
    }
    return AppConfigNode.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Adds a DataFormElement and, when [typeValue] is provided, immediately
  /// adds its DataFormElementType child in a second call.
  Future<AppConfigNode?> addDataFormElement({
    required int parentFormId,
    required String code,
    String? typeValue,
  }) async {
    AppConfigNode? tree = await addNode(
      parentObjectId: parentFormId,
      typeCode: 'DataFormElement',
      code: code,
    );
    if (tree == null || typeValue == null) return tree;

    final newElem = tree.findDataFormElement(parentFormId, code);
    if (newElem?.id == null) return tree;

    return addNode(
      parentObjectId: newElem!.id,
      typeCode: 'DataFormElementType',
      code: '${code}_type',
      enumValue: typeValue,
    );
  }

  Future<AppConfigNode?> deleteNode(int id) async {
    final response = await http.delete(Uri.parse('$_base/node/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete node: HTTP ${response.statusCode}');
    }
    return AppConfigNode.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AppConfigNode?> copyNode(int id, String newCode) async {
    final response = await http.post(
      Uri.parse('$_base/node/$id/copy'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'newCode': newCode}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to copy node: HTTP ${response.statusCode}');
    }
    return AppConfigNode.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<AppConfigNode?> updateNode(int id,
      {String? code, String? enumValue}) async {
    final body = <String, dynamic>{
      if (code != null) 'code': code,
      if (enumValue != null) 'enumValue': enumValue,
    };
    final response = await http.patch(
      Uri.parse('$_base/node/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update node: HTTP ${response.statusCode}');
    }
    return AppConfigNode.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Updates a DataForm's code and/or entity enum.
  /// If the DataFormEntityType child node does not yet exist it is created.
  Future<AppConfigNode?> updateDataForm({
    required int formId,
    required String formCode,
    required int? entityNodeId,
    String? newCode,
    String? newEntityValue,
  }) async {
    AppConfigNode? tree;

    if (newCode != null) {
      tree = await updateNode(formId, code: newCode);
    }

    if (newEntityValue != null) {
      if (entityNodeId != null) {
        tree = await updateNode(entityNodeId, enumValue: newEntityValue);
      } else {
        tree = await addNode(
          parentObjectId: formId,
          typeCode: 'DataFormEntityType',
          code: '${newCode ?? formCode}_entity',
          enumValue: newEntityValue,
        );
      }
    }

    return tree;
  }

  /// Updates a DataFormElement's code and/or type enum.
  /// If the DataFormElementType child node does not yet exist it is created.
  Future<AppConfigNode?> updateDataFormElement({
    required int elementId,
    required String elementCode,
    required int? typeNodeId,
    String? newCode,
    String? newTypeValue,
  }) async {
    AppConfigNode? tree;

    if (newCode != null) {
      tree = await updateNode(elementId, code: newCode);
    }

    if (newTypeValue != null) {
      if (typeNodeId != null) {
        tree = await updateNode(typeNodeId, enumValue: newTypeValue);
      } else {
        tree = await addNode(
          parentObjectId: elementId,
          typeCode: 'DataFormElementType',
          code: '${newCode ?? elementCode}_type',
          enumValue: newTypeValue,
        );
      }
    }

    return tree;
  }

  // ---------------------------------------------------------------------------
  // Data Binding
  // ---------------------------------------------------------------------------

  /// Fetches binding proposals for the given entity type and optional prefix.
  Future<BindingProposalResponse> fetchBindingProposals(
      String entityType, {String prefix = ''}) async {
    final uri = Uri.parse('$_bindingBase/proposals/$entityType')
        .replace(queryParameters: {'prefix': prefix});
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch binding proposals: HTTP ${response.statusCode}');
    }
    return BindingProposalResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Updates a DataFormElement's code, type enum, dataBinding, and entity refs.
  /// Creates child nodes if they do not yet exist.
  Future<AppConfigNode?> updateDataFormElementFull({
    required int elementId,
    required String elementCode,
    required int? typeNodeId,
    required int? dataBindingNodeId,
    required int? entityProviderRefNodeId,
    required int? entityRendererRefNodeId,
    String? newCode,
    String? newTypeValue,
    String? newDataBinding,
    String? newEntityProviderRef,
    String? newEntityRendererRef,
  }) async {
    AppConfigNode? tree;

    if (newCode != null) {
      tree = await updateNode(elementId, code: newCode);
    }

    if (newTypeValue != null) {
      if (typeNodeId != null) {
        tree = await updateNode(typeNodeId, enumValue: newTypeValue);
      } else {
        tree = await addNode(
          parentObjectId: elementId,
          typeCode: 'DataFormElementType',
          code: '${newCode ?? elementCode}_type',
          enumValue: newTypeValue,
        );
      }
    }

    if (newDataBinding != null) {
      if (dataBindingNodeId != null) {
        tree = await updateNode(dataBindingNodeId, code: newDataBinding);
      } else {
        tree = await addNode(
          parentObjectId: elementId,
          typeCode: 'DataBinding',
          code: newDataBinding,
        );
      }
    }

    if (newEntityProviderRef != null) {
      if (entityProviderRefNodeId != null) {
        tree = await updateNode(entityProviderRefNodeId, code: newEntityProviderRef);
      } else {
        tree = await addNode(
          parentObjectId: elementId,
          typeCode: 'EntityProviderRef',
          code: newEntityProviderRef,
        );
      }
    }

    if (newEntityRendererRef != null) {
      if (entityRendererRefNodeId != null) {
        tree = await updateNode(entityRendererRefNodeId, code: newEntityRendererRef);
      } else {
        tree = await addNode(
          parentObjectId: elementId,
          typeCode: 'EntityRendererRef',
          code: newEntityRendererRef,
        );
      }
    }

    return tree;
  }

  // ---------------------------------------------------------------------------
  // Entity Select Options
  // ---------------------------------------------------------------------------

  Future<List<EntityOption>> fetchEntityOptions(
      String providerCode, String rendererCode) async {
    final uri = Uri.parse('$_entitySelectBase/options').replace(
        queryParameters: {'provider': providerCode, 'renderer': rendererCode});
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch entity options: HTTP ${response.statusCode}');
    }
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => EntityOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // DataForm Evaluation
  // ---------------------------------------------------------------------------

  /// Evaluates visibility and options for affected elements via the unified endpoint.
  Future<Map<String, ElementState>> fetchFormEvaluation({
    required String dataFormCode,
    int? entityId,
    String? changedElement,
    Map<String, String> formState = const {},
  }) async {
    final uri = Uri.parse('$_dataFormBase/evaluate');
    final body = jsonEncode({
      'dataFormCode': dataFormCode,
      'entityId': entityId,
      'changedElement': changedElement,
      'formState': formState,
    });
    final response = await http.post(uri,
        headers: {'Content-Type': 'application/json'}, body: body);
    if (response.statusCode != 200) {
      throw Exception(
          'Failed to evaluate form: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = json['elements'] as Map<String, dynamic>;
    return elements.map((key, value) =>
        MapEntry(key, ElementState.fromJson(value as Map<String, dynamic>)));
  }

  // ---------------------------------------------------------------------------
  // EntityProvider mutations
  // ---------------------------------------------------------------------------

  /// Updates an EntityProvider's code and/or entityType.
  Future<AppConfigNode?> updateEntityProvider({
    required int providerId,
    required String providerCode,
    required int? entityTypeNodeId,
    String? newCode,
    String? newEntityTypeValue,
  }) async {
    AppConfigNode? tree;

    if (newCode != null) {
      tree = await updateNode(providerId, code: newCode);
    }

    if (newEntityTypeValue != null) {
      if (entityTypeNodeId != null) {
        tree = await updateNode(entityTypeNodeId, enumValue: newEntityTypeValue);
      } else {
        tree = await addNode(
          parentObjectId: providerId,
          typeCode: 'EntityProviderEntityType',
          code: '${newCode ?? providerCode}_entityType',
          enumValue: newEntityTypeValue,
        );
      }
    }

    return tree;
  }

  // ---------------------------------------------------------------------------
  // EntityRenderer mutations
  // ---------------------------------------------------------------------------

  /// Updates an EntityRenderer's code, entityType, and/or template.
  Future<AppConfigNode?> updateEntityRenderer({
    required int rendererId,
    required String rendererCode,
    required int? entityTypeNodeId,
    required int? templateNodeId,
    String? newCode,
    String? newEntityTypeValue,
    String? newTemplate,
  }) async {
    AppConfigNode? tree;

    if (newCode != null) {
      tree = await updateNode(rendererId, code: newCode);
    }

    if (newEntityTypeValue != null) {
      if (entityTypeNodeId != null) {
        tree = await updateNode(entityTypeNodeId, enumValue: newEntityTypeValue);
      } else {
        tree = await addNode(
          parentObjectId: rendererId,
          typeCode: 'EntityRendererEntityType',
          code: '${newCode ?? rendererCode}_entityType',
          enumValue: newEntityTypeValue,
        );
      }
    }

    if (newTemplate != null) {
      if (templateNodeId != null) {
        tree = await updateNode(templateNodeId, code: newTemplate);
      } else {
        tree = await addNode(
          parentObjectId: rendererId,
          typeCode: 'EntityRendererTemplate',
          code: newTemplate,
        );
      }
    }

    return tree;
  }

  // ---------------------------------------------------------------------------
  // Expression Compile Check
  // ---------------------------------------------------------------------------

  static const _expressionBase = 'http://localhost:8080/api/expressions';

  Future<CompileCheckResult> compileCheck({
    required String type,
    required String baseClass,
    required String expression,
    String? expectedEntityType,
  }) async {
    final response = await http.post(
      Uri.parse('$_expressionBase/compile-check'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': type,
        'baseClass': baseClass,
        'expression': expression,
        if (expectedEntityType != null) 'expectedEntityType': expectedEntityType,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Compile check failed: HTTP ${response.statusCode}');
    }
    return CompileCheckResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }
}

class CompileCheckError {
  final int line;
  final String message;
  const CompileCheckError({required this.line, required this.message});

  factory CompileCheckError.fromJson(Map<String, dynamic> json) {
    return CompileCheckError(
      line: (json['line'] as num).toInt(),
      message: json['message'] as String,
    );
  }
}

class CompileCheckWarning {
  final String message;
  const CompileCheckWarning({required this.message});

  factory CompileCheckWarning.fromJson(Map<String, dynamic> json) {
    return CompileCheckWarning(message: json['message'] as String);
  }
}

class MethodInfo {
  final String name;
  final String returnType;
  final bool returnsResolvable;

  const MethodInfo({
    required this.name,
    required this.returnType,
    required this.returnsResolvable,
  });

  factory MethodInfo.fromJson(Map<String, dynamic> json) {
    return MethodInfo(
      name: json['name'] as String,
      returnType: json['returnType'] as String,
      returnsResolvable: json['returnsResolvable'] as bool? ?? false,
    );
  }
}

class TypeContext {
  final Map<String, String> variables;
  final Map<String, List<MethodInfo>> methods;

  const TypeContext({required this.variables, required this.methods});

  factory TypeContext.fromJson(Map<String, dynamic> json) {
    final vars = (json['variables'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, v as String)) ?? {};
    final meths = <String, List<MethodInfo>>{};
    final rawMethods = json['methods'] as Map<String, dynamic>?;
    if (rawMethods != null) {
      for (final entry in rawMethods.entries) {
        meths[entry.key] = (entry.value as List<dynamic>)
            .map((m) => MethodInfo.fromJson(m as Map<String, dynamic>))
            .toList();
      }
    }
    return TypeContext(variables: vars, methods: meths);
  }
}

class CompileCheckResult {
  final bool valid;
  final List<CompileCheckError> errors;
  final List<CompileCheckWarning> warnings;
  final TypeContext? typeContext;

  const CompileCheckResult({
    required this.valid,
    required this.errors,
    required this.warnings,
    this.typeContext,
  });

  factory CompileCheckResult.fromJson(Map<String, dynamic> json) {
    return CompileCheckResult(
      valid: json['valid'] as bool,
      errors: ((json['errors'] as List<dynamic>?) ?? [])
          .map((e) => CompileCheckError.fromJson(e as Map<String, dynamic>))
          .toList(),
      warnings: ((json['warnings'] as List<dynamic>?) ?? [])
          .map((w) => CompileCheckWarning.fromJson(w as Map<String, dynamic>))
          .toList(),
      typeContext: json['typeContext'] != null
          ? TypeContext.fromJson(json['typeContext'] as Map<String, dynamic>)
          : null,
    );
  }
}
