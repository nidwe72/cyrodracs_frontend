import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import '../theme/app_theme.dart';
import 'app_config_service.dart';

/// The import statements that InjectableExecutor adds at compile time.
const _kImports = '''
import sciens.cyrodracs.expression.*;
import sciens.cyrodracs.appconfig.*;
import sciens.cyrodracs.camera.*;
import java.util.*;
import java.time.*;''';

/// Maps InjectableBaseClass enum values to simple class names for the title.
const _kBaseClassNames = {
  'SCALAR_VALUE': 'ScalarValueInjectable',
  'BOOLEAN_VALUE': 'BooleanInjectable',
  'LIST_VALUE': 'ListValueInjectable',
  'FILTER': 'FilterInjectable',
};

/// Static autocomplete prompts for the injectable API.
const List<CodePrompt> _kDirectPrompts = [
  CodeFunctionPrompt(word: 'getInjectionContext', type: 'InjectionContext', parameters: {}),
  CodeFunctionPrompt(word: 'setResult', type: 'void', parameters: {'result': 'Object'}),
];

const Map<String, List<CodePrompt>> _kRelatedPrompts = {
  'getInjectionContext()': [
    CodeFunctionPrompt(word: 'getEditorEntity', type: 'Object', parameters: {}),
    CodeFunctionPrompt(word: 'getFormState', type: 'Map<String,String>', parameters: {}),
    CodeFunctionPrompt(word: 'getFormValue', type: 'String', parameters: {'key': 'String'}),
    CodeFunctionPrompt(word: 'getRouteParam', type: 'String', parameters: {'key': 'String'}),
    CodeFunctionPrompt(word: 'getSessionValue', type: 'String', parameters: {'key': 'String'}),
  ],
  'FilterOperator': [
    CodeFieldPrompt(word: 'EQUALS', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'NOT_EQUALS', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'GREATER_THAN', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'GREATER_THAN_OR_EQUAL', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'LESS_THAN', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'LESS_THAN_OR_EQUAL', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'IS_NULL', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'IS_NOT_NULL', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'IN', type: 'FilterOperator'),
    CodeFieldPrompt(word: 'LIKE', type: 'FilterOperator'),
  ],
};

/// Additional prompts for FilterInjectable base class.
const List<CodePrompt> _kFilterPrompts = [
  CodeFunctionPrompt(word: 'comparison', type: 'FilterNode',
      parameters: {'field': 'String', 'operator': 'FilterOperator', 'value': 'Object'}),
  CodeFunctionPrompt(word: 'and', type: 'FilterNode', parameters: {'children': 'FilterNode...'}),
  CodeFunctionPrompt(word: 'or', type: 'FilterNode', parameters: {'children': 'FilterNode...'}),
  CodeFunctionPrompt(word: 'in', type: 'FilterNode',
      parameters: {'field': 'String', 'values': 'List<Object>'}),
  CodeFunctionPrompt(word: 'isNull', type: 'FilterNode', parameters: {'field': 'String'}),
  CodeFunctionPrompt(word: 'isNotNull', type: 'FilterNode', parameters: {'field': 'String'}),
];

/// Modal dialog for editing injectable expression source code.
///
/// Opens with the current expression body and returns the edited text on Save,
/// or null on Cancel.
class ExpressionEditorDialog extends StatefulWidget {
  final String expressionCode;
  final String expressionType;  // INJECTABLE_CLASS or INJECTABLE_SNIPPET
  final String baseClass;       // e.g., FILTER, SCALAR_VALUE
  final String initialSource;

  const ExpressionEditorDialog({
    super.key,
    required this.expressionCode,
    required this.expressionType,
    required this.baseClass,
    required this.initialSource,
  });

  /// Shows the dialog and returns the edited source, or null if cancelled.
  static Future<String?> show(BuildContext context, {
    required String expressionCode,
    required String expressionType,
    required String baseClass,
    required String initialSource,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExpressionEditorDialog(
        expressionCode: expressionCode,
        expressionType: expressionType,
        baseClass: baseClass,
        initialSource: initialSource,
      ),
    );
  }

  @override
  State<ExpressionEditorDialog> createState() => _ExpressionEditorDialogState();
}

class _ExpressionEditorDialogState extends State<ExpressionEditorDialog> {
  late final CodeLineEditingController _codeController;
  final _service = AppConfigService();

  List<CompileCheckError> _errors = [];
  List<CompileCheckWarning> _warnings = [];
  bool _checking = false;
  Timer? _debounceTimer;
  late _InjectablePromptsBuilder _promptsBuilder;

  @override
  void initState() {
    super.initState();
    _codeController = CodeLineEditingController.fromText(widget.initialSource);
    _codeController.addListener(_onCodeChanged);
    _promptsBuilder = _InjectablePromptsBuilder(
      controller: _codeController,
      baseClass: widget.baseClass,
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), _compileCheck);
  }

  String get _baseClassName =>
      _kBaseClassNames[widget.baseClass] ?? widget.baseClass;

  Future<void> _compileCheck() async {
    setState(() {
      _checking = true;
      _errors = [];
      _warnings = [];
    });
    try {
      final result = await _service.compileCheck(
        type: widget.expressionType,
        baseClass: widget.baseClass,
        expression: _codeController.text,
      );
      if (!mounted) return;
      setState(() {
        _errors = result.errors;
        _warnings = result.warnings;
        _promptsBuilder.typeContext = result.typeContext;
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors = [CompileCheckError(line: -1, message: e.toString())];
        _checking = false;
      });
    }
  }

  Future<void> _save() async {
    // Run compile-check before saving — block if errors
    await _compileCheck();
    if (!mounted) return;
    if (_errors.isNotEmpty) return; // stay open, errors are displayed
    Navigator.pop(context, _codeController.text);
  }

  void _cancel() {
    Navigator.pop(context, null);
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final borderColor = Theme.of(context).inputDecorationTheme.border
        is OutlineInputBorder
        ? (Theme.of(context).inputDecorationTheme.border as OutlineInputBorder)
            .borderSide.color
        : Colors.grey;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.1,
        vertical: size.height * 0.1,
      ),
      child: SizedBox(
        width: size.width * 0.8,
        height: size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title bar
            Container(
              padding: AppTheme.panelHeaderPadding,
              decoration: BoxDecoration(
                color: AppTheme.panelHeaderBackground,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Text(
                    '${widget.expressionCode} : $_baseClassName',
                    style: AppTheme.panelHeaderTitle,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: AppTheme.iconSize),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _cancel,
                  ),
                ],
              ),
            ),
            // Code editor
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: CodeAutocomplete(
                  viewBuilder: (context, notifier, onSelected) {
                    return _AutocompletePopup(
                      notifier: notifier,
                      onSelected: onSelected,
                    );
                  },
                  promptsBuilder: _promptsBuilder,
                  child: CodeEditor(
                    controller: _codeController,
                    style: CodeEditorStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      codeTheme: CodeHighlightTheme(
                        languages: {
                          'java': CodeHighlightThemeMode(mode: langJava),
                        },
                        theme: atomOneLightTheme,
                      ),
                    ),
                    indicatorBuilder: (context, editingController,
                        chunkController, notifier) {
                      return Row(
                        children: [
                          _ErrorGutter(
                            notifier: notifier,
                            errorLines: _errors
                                .where((e) => e.line > 0)
                                .map((e) => e.line - 1) // 0-based
                                .toSet(),
                          ),
                          DefaultCodeLineNumber(
                            controller: editingController,
                            notifier: notifier,
                          ),
                          DefaultCodeChunkIndicator(
                            width: 20,
                            controller: chunkController,
                            notifier: notifier,
                          ),
                        ],
                      );
                    },
                    chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
                    sperator: Container(width: 1, color: borderColor),
                  ),
                ),
              ),
            ),
            // Error/warning panel
            if (_errors.isNotEmpty || _warnings.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_errors.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Autocomplete may be limited until errors are fixed.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      for (final err in _errors)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error, size: 14, color: Colors.red),
                              const SizedBox(width: 4),
                              if (err.line > 0)
                                Text('Line ${err.line}: ',
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              Expanded(
                                child: Text(err.message,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      for (final warn in _warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning, size: 14,
                                  color: Colors.orange),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(warn.message,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            // Imports section
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingSm),
                child: Text(
                  _kImports,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
              child: Row(
                children: [
                  ElevatedButton(
                    onPressed: _checking ? null : _compileCheck,
                    child: _checking
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Check'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _cancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppTheme.spacingSm),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Autocomplete popup (adapted from re_editor example)
// ---------------------------------------------------------------------------

class _AutocompletePopup extends StatefulWidget implements PreferredSizeWidget {
  static const double kItemHeight = 26;

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  const _AutocompletePopup({
    required this.notifier,
    required this.onSelected,
  });

  @override
  Size get preferredSize => Size(
    300,
    min(kItemHeight * notifier.value.prompts.length, 150) + 2,
  );

  @override
  State<_AutocompletePopup> createState() => _AutocompletePopupState();
}

class _AutocompletePopupState extends State<_AutocompletePopup> {
  @override
  void initState() {
    widget.notifier.addListener(_onChanged);
    super.initState();
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final value = widget.notifier.value;
    return Container(
      constraints: BoxConstraints.loose(widget.preferredSize),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.panelBorder.color),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: value.prompts.length,
        itemExtent: _AutocompletePopup.kItemHeight,
        itemBuilder: (context, index) {
          final prompt = value.prompts[index];
          final selected = index == value.index;
          return InkWell(
            onTap: () {
              widget.onSelected(value.copyWith(index: index).autocomplete);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.centerLeft,
              color: selected ? Colors.blue.shade50 : null,
              child: _buildPromptText(prompt, value.input),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPromptText(CodePrompt prompt, String input) {
    final word = prompt.word;
    final matchIdx = word.toLowerCase().indexOf(input.toLowerCase());
    final style = const TextStyle(fontFamily: 'monospace', fontSize: 12);

    Widget wordWidget;
    if (matchIdx >= 0 && input.isNotEmpty) {
      wordWidget = RichText(
        overflow: TextOverflow.ellipsis,
        text: TextSpan(children: [
          TextSpan(text: word.substring(0, matchIdx), style: style),
          TextSpan(
            text: word.substring(matchIdx, matchIdx + input.length),
            style: style.copyWith(
                color: Colors.blue, fontWeight: FontWeight.bold),
          ),
          TextSpan(text: word.substring(matchIdx + input.length), style: style),
        ]),
      );
    } else {
      wordWidget = Text(word, style: style, overflow: TextOverflow.ellipsis);
    }

    String? typeText;
    if (prompt is CodeFieldPrompt) typeText = prompt.type;
    if (prompt is CodeFunctionPrompt) typeText = '(...) → ${prompt.type}';

    return Row(
      children: [
        Expanded(child: wordWidget),
        if (typeText != null)
          Text(typeText,
              style: style.copyWith(color: Colors.grey.shade500, fontSize: 11)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error gutter indicator (red circles on error lines)
// ---------------------------------------------------------------------------

class _ErrorGutter extends LeafRenderObjectWidget {
  final CodeIndicatorValueNotifier notifier;
  final Set<int> errorLines; // 0-based line indices

  const _ErrorGutter({
    required this.notifier,
    required this.errorLines,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _ErrorGutterRenderObject(
      notifier: notifier,
      errorLines: errorLines,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _ErrorGutterRenderObject renderObject) {
    renderObject
      ..notifier = notifier
      ..errorLines = errorLines;
  }
}

class _ErrorGutterRenderObject extends RenderBox {
  CodeIndicatorValueNotifier _notifier;
  Set<int> _errorLines;

  static const double _width = 16;
  static const double _iconRadius = 4;

  _ErrorGutterRenderObject({
    required CodeIndicatorValueNotifier notifier,
    required Set<int> errorLines,
  })  : _notifier = notifier,
        _errorLines = errorLines;

  set notifier(CodeIndicatorValueNotifier value) {
    if (_notifier == value) return;
    if (attached) _notifier.removeListener(markNeedsPaint);
    _notifier = value;
    if (attached) _notifier.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  set errorLines(Set<int> value) {
    if (_errorLines == value) return;
    _errorLines = value;
    markNeedsPaint();
  }

  @override
  void attach(covariant PipelineOwner owner) {
    _notifier.addListener(markNeedsPaint);
    super.attach(owner);
  }

  @override
  void detach() {
    _notifier.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = Size(_errorLines.isEmpty ? 0 : _width, constraints.maxHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_errorLines.isEmpty) return;
    final value = _notifier.value;
    if (value == null || value.paragraphs.isEmpty) return;

    final canvas = context.canvas;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height));

    final paint = Paint()..color = Colors.red;

    for (final paragraph in value.paragraphs) {
      if (_errorLines.contains(paragraph.index)) {
        final cy = offset.dy + paragraph.offset.dy +
            (paragraph.height / 2);
        final cx = offset.dx + _width / 2;
        canvas.drawCircle(Offset(cx, cy), _iconRadius, paint);
      }
    }

    canvas.restore();
  }
}

// ---------------------------------------------------------------------------
// Custom prompts builder with server-backed type resolution
// ---------------------------------------------------------------------------

class _InjectablePromptsBuilder implements CodeAutocompletePromptsBuilder {
  final CodeLineEditingController controller;
  final String baseClass;
  TypeContext? typeContext;

  /// Static prompts (always available, no server needed).
  late final List<CodePrompt> _staticPrompts;
  late final Map<String, List<CodePrompt>> _staticRelated;

  _InjectablePromptsBuilder({
    required this.controller,
    required this.baseClass,
  }) {
    _staticPrompts = [
      ..._kDirectPrompts,
      if (baseClass == 'FILTER') ..._kFilterPrompts,
    ];
    _staticRelated = _kRelatedPrompts;
  }

  @override
  CodeAutocompleteEditingValue? build(
      BuildContext context, CodeLine codeLine, CodeLineSelection selection) {
    final String text = codeLine.text;
    final String before = text.substring(0, selection.extentOffset);
    if (before.isEmpty) return null;

    // Check if we're after a dot → resolve the chain
    if (before.endsWith('.')) {
      final prompts = _resolveChain(before.substring(0, before.length - 1));
      if (prompts != null && prompts.isNotEmpty) {
        return CodeAutocompleteEditingValue(
            input: '', prompts: prompts, index: 0);
      }
      return null;
    }

    // Check if we're typing after a dot (e.g., "p.get")
    final dotIdx = before.lastIndexOf('.');
    if (dotIdx > 0) {
      final target = before.substring(0, dotIdx);
      final input = before.substring(dotIdx + 1);
      if (input.isEmpty) return null;
      final prompts = _resolveChain(target);
      if (prompts != null) {
        final filtered = prompts.where((p) => p.match(input)).toList();
        if (filtered.isNotEmpty) {
          return CodeAutocompleteEditingValue(
              input: input, prompts: filtered, index: 0);
        }
      }
      return null;
    }

    // No dot — offer static keyword/direct prompts
    final input = _extractWord(before);
    if (input.isEmpty) return null;

    final prompts = _staticPrompts.where((p) => p.match(input)).toList();
    if (prompts.isEmpty) return null;
    return CodeAutocompleteEditingValue(
        input: input, prompts: prompts, index: 0);
  }

  /// Resolves a chain like "p" or "p.getProducer()" to a list of method prompts.
  List<CodePrompt>? _resolveChain(String expression) {
    // Extract the chain segments: "p.getProducer().getName" → ["p", "getProducer()", "getName"]
    final segments = _parseChain(expression.trim());
    if (segments.isEmpty) return null;

    // First, check static related prompts (e.g., "FilterOperator", "getInjectionContext()")
    if (segments.length == 1) {
      final staticResult = _staticRelated[segments.first];
      if (staticResult != null) return staticResult;
    }

    // Resolve the first segment to a type
    String? currentType = _resolveFirstSegment(segments.first);
    if (currentType == null) return null;

    // Walk the chain, resolving each method's return type
    for (int i = 1; i < segments.length; i++) {
      final methodName = segments[i].replaceAll(RegExp(r'\(.*\)$'), '');
      final methods = typeContext?.methods[currentType];
      if (methods == null) return null;

      final method = methods.where((m) =>
          m.name.startsWith('$methodName(')).firstOrNull;
      if (method == null) return null;
      currentType = method.returnType;
    }

    // Return prompts for the resolved type
    return _buildPromptsForType(currentType);
  }

  /// Resolves the first segment of a chain to a type name.
  String? _resolveFirstSegment(String segment) {
    // Check if it's a variable name → look up in typeContext
    final tc = typeContext;
    if (tc != null) {
      // Direct variable lookup (e.g., "p" → "CameraProducer")
      final varType = tc.variables[segment];
      if (varType != null) return varType;

      // Method call lookup (e.g., "getHelper()" → return type)
      final asCall = segment.contains('(') ? segment : '$segment()';
      final callType = tc.variables[asCall];
      if (callType != null) return callType;
    }

    // Check if it's a class name directly (e.g., "CameraProducer")
    if (tc != null && tc.methods.containsKey(segment)) {
      return segment;
    }

    return null;
  }

  /// Builds CodePrompt list from the method map for a given type.
  List<CodePrompt>? _buildPromptsForType(String? typeName) {
    if (typeName == null) return null;
    final methods = typeContext?.methods[typeName];
    if (methods == null || methods.isEmpty) return null;

    return methods.map((m) {
      if (m.name.contains('(') && !m.name.endsWith('()')) {
        // Method with parameters
        final parenIdx = m.name.indexOf('(');
        final word = m.name.substring(0, parenIdx);
        return CodeFunctionPrompt(
          word: word,
          type: m.returnType,
          parameters: {},
        ) as CodePrompt;
      }
      // No-arg method or field
      final word = m.name.replaceAll('()', '');
      return CodeFieldPrompt(word: word, type: m.returnType) as CodePrompt;
    }).toList();
  }

  /// Parses "p.getProducer().getName" into ["p", "getProducer()", "getName"]
  List<String> _parseChain(String expr) {
    final segments = <String>[];
    final buffer = StringBuffer();
    int parenDepth = 0;

    for (int i = 0; i < expr.length; i++) {
      final ch = expr[i];
      if (ch == '(') {
        parenDepth++;
        buffer.write(ch);
      } else if (ch == ')') {
        parenDepth--;
        buffer.write(ch);
      } else if (ch == '.' && parenDepth == 0) {
        if (buffer.isNotEmpty) {
          segments.add(buffer.toString());
          buffer.clear();
        }
      } else if (_isIdentChar(ch)) {
        buffer.write(ch);
      } else if (ch == ' ' || ch == '\t') {
        // skip whitespace
      } else {
        // Non-identifier char (cast, operator, etc.) — reset
        segments.clear();
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) segments.add(buffer.toString());
    return segments;
  }

  /// Extracts the word being typed (walking backwards from end).
  String _extractWord(String text) {
    int i = text.length - 1;
    while (i >= 0 && _isIdentChar(text[i])) {
      i--;
    }
    return text.substring(i + 1);
  }

  bool _isIdentChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
  }
}
