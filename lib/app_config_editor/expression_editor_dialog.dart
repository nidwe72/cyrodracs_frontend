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

  @override
  void initState() {
    super.initState();
    _codeController = CodeLineEditingController.fromText(widget.initialSource);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
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

  List<CodePrompt> get _directPrompts {
    final prompts = <CodePrompt>[..._kDirectPrompts];
    if (widget.baseClass == 'FILTER') {
      prompts.addAll(_kFilterPrompts);
    }
    return prompts;
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
                  promptsBuilder: DefaultCodeAutocompletePromptsBuilder(
                    language: langJava,
                    directPrompts: _directPrompts,
                    relatedPrompts: _kRelatedPrompts,
                  ),
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
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: borderColor)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingSm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
