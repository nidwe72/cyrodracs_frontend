import '../models/data_form.dart';

/// A pending child entity collected while the parent has no ID.
class PendingChild {
  final String dataFormCode;
  final String contextBindingTarget;
  final Map<String, dynamic> values;
  final String? sourceElementCode;
  /// Display-friendly values for rendering in the GRID table (labels instead of IDs).
  final Map<String, dynamic> displayValues;

  PendingChild({
    required this.dataFormCode,
    required this.contextBindingTarget,
    required this.values,
    this.sourceElementCode,
    this.displayValues = const {},
  });

  Map<String, dynamic> toJson() => {
    'dataFormCode': dataFormCode,
    'contextBindingTarget': contextBindingTarget,
    'values': values,
    'pendingChildren': [],
  };
}

/// A single editor frame in the EditorStack.
class EditorFrame {
  final String dataFormCode;
  final int? entityId;
  final Map<String, dynamic> contextBindings;
  final String? breadcrumbLabel;
  final String? sourceElementCode;

  DataForm? form;
  Map<String, dynamic>? formState;
  Map<String, dynamic>? initialValues;
  double scrollOffset = 0;
  final List<PendingChild> pendingChildren = [];

  EditorFrame({
    required this.dataFormCode,
    this.entityId,
    this.contextBindings = const {},
    this.breadcrumbLabel,
    this.sourceElementCode,
    this.form,
    this.initialValues,
  });

  /// Whether this frame is editing an existing entity (has ID) vs creating new.
  bool get isNew => entityId == null;

  /// Label for the stack path tree.
  String get label {
    if (breadcrumbLabel != null) return breadcrumbLabel!;
    if (isNew) return 'New $dataFormCode';
    return '$dataFormCode #$entityId';
  }
}

/// Manages a stack of editor frames for nested entity editing.
class EditorStack {
  final List<EditorFrame> _frames = [];

  /// The current stack depth (0 = no editor open).
  int get depth => _frames.length;

  /// Whether there are any frames on the stack.
  bool get isEmpty => _frames.isEmpty;

  /// Whether there are frames on the stack.
  bool get isNotEmpty => _frames.isNotEmpty;

  /// The topmost (active) frame, or null if stack is empty.
  EditorFrame? get current => _frames.isEmpty ? null : _frames.last;

  /// All frames (for stack path tree rendering).
  List<EditorFrame> get frames => List.unmodifiable(_frames);

  /// Push a new frame onto the stack.
  void push(EditorFrame frame) {
    _frames.add(frame);
  }

  /// Pop the topmost frame. Returns the popped frame.
  EditorFrame? pop() {
    if (_frames.isEmpty) return null;
    return _frames.removeLast();
  }

  /// Pop all frames above the given index (inclusive of index+1 and above).
  /// Returns the list of popped frames.
  List<EditorFrame> popTo(int index) {
    final popped = <EditorFrame>[];
    while (_frames.length > index + 1) {
      popped.add(_frames.removeLast());
    }
    return popped;
  }

  /// Clear the entire stack.
  void clear() {
    _frames.clear();
  }

  /// Whether any frame in the stack has unsaved changes.
  /// For now this checks if formState differs from initialValues.
  bool get hasUnsavedChanges {
    for (final frame in _frames) {
      if (frame.formState != null && frame.initialValues != null) {
        if (frame.formState.toString() != frame.initialValues.toString()) {
          return true;
        }
      }
      if (frame.isNew && frame.formState != null && frame.formState!.isNotEmpty) {
        return true;
      }
    }
    return false;
  }
}
