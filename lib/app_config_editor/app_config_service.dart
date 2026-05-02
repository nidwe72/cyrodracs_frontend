import 'package:graphql/client.dart';
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

// ---------------------------------------------------------------------------
// GraphQL query fragments — define which fields to fetch
// ---------------------------------------------------------------------------

const _appConfigFields = r'''
  fragment AppConfigFields on AppConfig {
    id
    code
    dataForms {
      id code entity
      elements {
        id code type dataBinding
        entityProviderRef entityRendererRef
        mandatory
        reloadOnChangeOf
        visibilityRule { expressionRef }
        tableColumns { id code key header entityRendererRef restrictByVisibleRows }
        addAction {
          id code targetDataFormRef childLabel
          contextBindings { id code target source }
        }
      }
    }
    entityProviders {
      id code entityType
      filterInjectableRef
      filter { ...FilterFields }
      sortFields { id code field direction }
    }
    entityRenderers { id code entityType template }
    viewTree { ...ViewNodeFields }
    expressions { id code type baseClass expression description }
  }

  fragment FilterFields on FilterNode {
    id code type field operator value values expressionRef
    children { id code type field operator value values expressionRef
      children { id code type field operator value values expressionRef }
    }
  }

  fragment ViewNodeFields on ViewNode {
    id code type label entityProviderRef dataFormRef content
    tableColumns { id code key header entityRendererRef restrictByVisibleRows }
    children {
      id code type label entityProviderRef dataFormRef content
      tableColumns { id code key header entityRendererRef restrictByVisibleRows }
      children {
        id code type label entityProviderRef dataFormRef content
        tableColumns { id code key header entityRendererRef restrictByVisibleRows }
      }
    }
  }
''';

class AppConfigService {
  static final _client = GraphQLClient(
    link: HttpLink('http://localhost:8080/graphql'),
    cache: GraphQLCache(),
  );

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  Future<AppConfigNode?> fetchTree() async {
    final result = await _client.query(QueryOptions(
      document: gql('''
        query { appConfig { ...AppConfigFields } }
        $_appConfigFields
      '''),
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) {
      throw Exception('Failed to load AppConfig: ${result.exception}');
    }
    return AppConfigNode.fromJson(
        result.data!['appConfig'] as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Mutations – all return the updated tree on success
  // ---------------------------------------------------------------------------

  Future<AppConfigNode?> _mutate(String mutation) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        $mutation
        $_appConfigFields
      '''),
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) {
      throw Exception('Mutation failed: ${result.exception}');
    }
    // Find the first non-null operation result that returns AppConfigView
    final data = result.data!;
    for (final value in data.values) {
      if (value is Map<String, dynamic> && value.containsKey('code')) {
        return AppConfigNode.fromJson(value);
      }
    }
    return null;
  }

  Future<AppConfigNode?> _mutateWithVars(String mutation, Map<String, dynamic> variables) async {
    final result = await _client.mutate(MutationOptions(
      document: gql('''
        $mutation
        $_appConfigFields
      '''),
      variables: variables,
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) {
      throw Exception('Mutation failed: ${result.exception}');
    }
    final data = result.data!;
    for (final value in data.values) {
      if (value is Map<String, dynamic> && value.containsKey('code')) {
        return AppConfigNode.fromJson(value);
      }
    }
    return null;
  }

  Future<AppConfigNode?> addNode({
    required int? parentObjectId,
    required String typeCode,
    required String code,
    String? enumValue,
  }) async {
    return _mutateWithVars(
      r'''
        mutation AddNode($input: AddNodeInput!) {
          addAppConfigNode(input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'input': {
          'parentObjectId': parentObjectId,
          'typeCode': typeCode,
          'code': code,
          if (enumValue != null) 'enumValue': enumValue,
        },
      },
    );
  }

  Future<AppConfigNode?> addDataFormElement({
    required int parentFormId,
    required String code,
    String? typeValue,
  }) async {
    return _mutateWithVars(
      r'''
        mutation AddElement($input: AddDataFormElementInput!) {
          addDataFormElement(input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'input': {
          'parentFormId': parentFormId,
          'code': code,
          if (typeValue != null) 'type': typeValue,
        },
      },
    );
  }

  Future<AppConfigNode?> deleteNode(int id) async {
    return _mutateWithVars(
      r'''
        mutation DeleteNode($id: Int!) {
          deleteAppConfigNode(id: $id) { ...AppConfigFields }
        }
      ''',
      {'id': id},
    );
  }

  Future<AppConfigNode?> copyNode(int id, String newCode) async {
    return _mutateWithVars(
      r'''
        mutation CopyNode($id: Int!, $newCode: String!) {
          copyAppConfigNode(id: $id, newCode: $newCode) { ...AppConfigFields }
        }
      ''',
      {'id': id, 'newCode': newCode},
    );
  }

  Future<AppConfigNode?> updateNode(int id,
      {String? code, String? enumValue}) async {
    return _mutateWithVars(
      r'''
        mutation UpdateNode($id: Int!, $input: UpdateNodeInput!) {
          updateAppConfigNode(id: $id, input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'id': id,
        'input': {
          if (code != null) 'code': code,
          if (enumValue != null) 'enumValue': enumValue,
        },
      },
    );
  }

  Future<AppConfigNode?> updateDataForm({
    required int formId,
    required String formCode,
    required int? entityNodeId,
    String? newCode,
    String? newEntityValue,
  }) async {
    return _mutateWithVars(
      r'''
        mutation UpdateForm($input: UpdateDataFormInput!) {
          updateDataForm(input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'input': {
          'formId': formId,
          if (newCode != null) 'code': newCode,
          if (newEntityValue != null) 'entity': newEntityValue,
        },
      },
    );
  }

  Future<AppConfigNode?> updateDataFormElement({
    required int elementId,
    required String elementCode,
    required int? typeNodeId,
    String? newCode,
    String? newTypeValue,
  }) async {
    return _mutateWithVars(
      r'''
        mutation UpdateElement($input: UpdateDataFormElementFullInput!) {
          updateDataFormElementFull(input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'input': {
          'elementId': elementId,
          if (newCode != null) 'code': newCode,
          if (newTypeValue != null) 'type': newTypeValue,
        },
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Data Binding
  // ---------------------------------------------------------------------------

  Future<BindingProposalResponse> fetchBindingProposals(
      String entityType, {String prefix = ''}) async {
    final result = await _client.query(QueryOptions(
      document: gql(r'''
        query BindingProposals($entityType: String!, $prefix: String) {
          bindingProposals(entityType: $entityType, prefix: $prefix) {
            entityLabel
            completions { segment javaType leaf suggestedElementType referencedEntityType }
          }
        }
      '''),
      variables: {'entityType': entityType, 'prefix': prefix},
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) {
      throw Exception('Failed to fetch binding proposals: ${result.exception}');
    }
    return BindingProposalResponse.fromJson(
        result.data!['bindingProposals'] as Map<String, dynamic>);
  }

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
    return _mutateWithVars(
      r'''
        mutation UpdateElementFull($input: UpdateDataFormElementFullInput!) {
          updateDataFormElementFull(input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'input': {
          'elementId': elementId,
          if (newCode != null) 'code': newCode,
          if (newTypeValue != null) 'type': newTypeValue,
          if (newDataBinding != null) 'dataBinding': newDataBinding,
          if (newEntityProviderRef != null) 'entityProviderRef': newEntityProviderRef,
          if (newEntityRendererRef != null) 'entityRendererRef': newEntityRendererRef,
        },
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Entity Select Options
  // ---------------------------------------------------------------------------

  Future<List<EntityOption>> fetchEntityOptions(
      String providerCode, String rendererCode) async {
    final result = await _client.query(QueryOptions(
      document: gql(r'''
        query EntityOptions($provider: String!, $renderer: String!) {
          entitySelectOptions(provider: $provider, renderer: $renderer) {
            id label
          }
        }
      '''),
      variables: {'provider': providerCode, 'renderer': rendererCode},
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) {
      throw Exception('Failed to fetch entity options: ${result.exception}');
    }
    final list = result.data!['entitySelectOptions'] as List<dynamic>;
    return list
        .map((e) => EntityOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // DataForm Evaluation
  // ---------------------------------------------------------------------------

  Future<Map<String, ElementState>> fetchFormEvaluation({
    required String dataFormCode,
    int? entityId,
    String? changedElement,
    Map<String, String> formState = const {},
  }) async {
    final formStateEntries = formState.entries
        .map((e) => {'key': e.key, 'value': e.value})
        .toList();

    final result = await _client.query(QueryOptions(
      document: gql(r'''
        query Evaluate($input: EvaluateInput!) {
          evaluateDataForm(input: $input) {
            elements { key value { visible options { id label } } }
          }
        }
      '''),
      variables: {
        'input': {
          'dataFormCode': dataFormCode,
          'entityId': entityId,
          'changedElement': changedElement,
          'formState': formStateEntries,
        },
      },
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) {
      throw Exception('Failed to evaluate form: ${result.exception}');
    }
    final elements = result.data!['evaluateDataForm']['elements'] as List<dynamic>;
    return {
      for (final entry in elements)
        (entry as Map<String, dynamic>)['key'] as String:
            ElementState.fromJson(entry['value'] as Map<String, dynamic>),
    };
  }

  // ---------------------------------------------------------------------------
  // EntityProvider mutations
  // ---------------------------------------------------------------------------

  Future<AppConfigNode?> updateEntityProvider({
    required int providerId,
    required String providerCode,
    required int? entityTypeNodeId,
    String? newCode,
    String? newEntityTypeValue,
  }) async {
    return _mutateWithVars(
      r'''
        mutation UpdateProvider($input: UpdateEntityProviderInput!) {
          updateEntityProvider(input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'input': {
          'providerId': providerId,
          if (newCode != null) 'code': newCode,
          if (newEntityTypeValue != null) 'entityType': newEntityTypeValue,
        },
      },
    );
  }

  // ---------------------------------------------------------------------------
  // EntityRenderer mutations
  // ---------------------------------------------------------------------------

  Future<AppConfigNode?> updateEntityRenderer({
    required int rendererId,
    required String rendererCode,
    required int? entityTypeNodeId,
    required int? templateNodeId,
    String? newCode,
    String? newEntityTypeValue,
    String? newTemplate,
  }) async {
    return _mutateWithVars(
      r'''
        mutation UpdateRenderer($input: UpdateEntityRendererInput!) {
          updateEntityRenderer(input: $input) { ...AppConfigFields }
        }
      ''',
      {
        'input': {
          'rendererId': rendererId,
          if (newCode != null) 'code': newCode,
          if (newEntityTypeValue != null) 'entityType': newEntityTypeValue,
          if (newTemplate != null) 'template': newTemplate,
        },
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Expression Compile Check
  // ---------------------------------------------------------------------------

  Future<CompileCheckResult> compileCheck({
    required String type,
    required String baseClass,
    required String expression,
    String? expectedEntityType,
  }) async {
    final result = await _client.query(QueryOptions(
      document: gql(r'''
        query CompileCheck($input: CompileCheckInput!) {
          compileCheckExpression(input: $input) {
            valid
            errors { line message }
            warnings { message }
            typeContext {
              variables { key value }
              methods { key value { name returnType returnsResolvable } }
            }
          }
        }
      '''),
      variables: {
        'input': {
          'type': type,
          'baseClass': baseClass,
          'expression': expression,
          if (expectedEntityType != null) 'expectedEntityType': expectedEntityType,
        },
      },
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) {
      throw Exception('Compile check failed: ${result.exception}');
    }
    return CompileCheckResult.fromJson(
        result.data!['compileCheckExpression'] as Map<String, dynamic>);
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
    final vars = <String, String>{};
    final rawVars = json['variables'] as List<dynamic>?;
    if (rawVars != null) {
      for (final entry in rawVars) {
        final e = entry as Map<String, dynamic>;
        vars[e['key'] as String] = e['value'] as String;
      }
    }
    final meths = <String, List<MethodInfo>>{};
    final rawMethods = json['methods'] as List<dynamic>?;
    if (rawMethods != null) {
      for (final entry in rawMethods) {
        final e = entry as Map<String, dynamic>;
        meths[e['key'] as String] = (e['value'] as List<dynamic>)
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
