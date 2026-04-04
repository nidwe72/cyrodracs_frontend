import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/app_config_node.dart';

class BindingCompletion {
  final String segment;
  final String javaType;
  final bool leaf;
  final String? suggestedElementType;

  const BindingCompletion({
    required this.segment,
    required this.javaType,
    required this.leaf,
    this.suggestedElementType,
  });

  factory BindingCompletion.fromJson(Map<String, dynamic> json) {
    return BindingCompletion(
      segment: json['segment'] as String,
      javaType: json['javaType'] as String,
      leaf: json['leaf'] as bool,
      suggestedElementType: json['suggestedElementType'] as String?,
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

  /// Updates a DataFormElement's code, type enum, and/or dataBinding.
  /// Creates the DataBinding child node if it does not yet exist.
  Future<AppConfigNode?> updateDataFormElementFull({
    required int elementId,
    required String elementCode,
    required int? typeNodeId,
    required int? dataBindingNodeId,
    String? newCode,
    String? newTypeValue,
    String? newDataBinding,
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

    return tree;
  }
}
