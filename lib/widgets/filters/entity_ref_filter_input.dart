import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphql/client.dart';
import '../../graphql_client.dart';
import 'filter_field_style.dart';

/// Per-column entity-ref filter widget. Shows a compact text field; on focus
/// opens a floating overlay listing typeahead candidates from the backend
/// `entityRefPickerCandidates` query. Selection commits an EQUALS-on-id
/// filter; clearing the field clears the filter.
class EntityRefFilterInput extends StatefulWidget {
  const EntityRefFilterInput({
    super.key,
    required this.columnKey,
    required this.value,
    required this.onChanged,
    this.viewNodeCode,
    this.dataFormCode,
    this.elementCode,
    this.userFilter,
    this.editorEntityId,
    this.dismissTrigger,
  });

  /// `{ id: int, label: String }` when a candidate is selected, else null.
  final Map<String, dynamic>? value;
  final String columnKey;
  final String? viewNodeCode;
  final String? dataFormCode;
  final String? elementCode;

  /// Full active CF1 user-filter tree from the host. Backend strips the
  /// picker's own column (CF3.4.3 step 1).
  final Map<String, dynamic>? userFilter;

  /// Parent editor entity id for GRID surfaces inside an editor. Drives the
  /// Janino injectable's `getInjectionContext().getEditorEntity()`. Null on
  /// ENTITY_LIST surfaces.
  final int? editorEntityId;

  /// Fires whenever any column filter on the host changes. The picker
  /// overlay closes on each tick — `otherUserFilters` would otherwise have
  /// shifted under it (CF3.4.3 *Recomputation and invalidation*).
  final Listenable? dismissTrigger;

  final void Function(Map<String, dynamic>? value) onChanged;

  @override
  State<EntityRefFilterInput> createState() => _EntityRefFilterInputState();
}

class _EntityRefFilterInputState extends State<EntityRefFilterInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final ScrollController _scrollController = ScrollController();

  static const double _itemHeight = 32.0;

  OverlayEntry? _overlay;
  Timer? _debounceTimer;
  int _seq = 0;
  List<_Candidate> _candidates = const [];
  bool _loading = false;
  String? _error;
  int _highlightedIndex = 0;

  /// Term that produced the current `_candidates`. Empty means "cold open"
  /// (no typeahead applied) — used to choose between two distinct empty-state
  /// messages: a restriction-collapsed empty (CF3.4.3) vs. a typeahead-miss.
  String _lastAppliedTerm = '';

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value?['label']?.toString() ?? '';
    _focusNode.addListener(_onFocusChange);
    widget.dismissTrigger?.addListener(_onHostFilterChanged);
  }

  @override
  void didUpdateWidget(covariant EntityRefFilterInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newLabel = widget.value?['label']?.toString() ?? '';
    if (newLabel != _controller.text && !_focusNode.hasFocus) {
      _controller.text = newLabel;
    }
    if (oldWidget.dismissTrigger != widget.dismissTrigger) {
      oldWidget.dismissTrigger?.removeListener(_onHostFilterChanged);
      widget.dismissTrigger?.addListener(_onHostFilterChanged);
    }
  }

  @override
  void dispose() {
    widget.dismissTrigger?.removeListener(_onHostFilterChanged);
    _hideOverlay();
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Host signalled a filter-state change on some other column. Drop any
  /// in-flight typeahead and dismiss the overlay — `otherUserFilters` has
  /// shifted, so the candidate set on screen is stale (CF3.4.3
  /// *Recomputation and invalidation*).
  void _onHostFilterChanged() {
    if (!mounted) return;
    if (_overlay == null && !_focusNode.hasFocus) return;
    _seq++;                       // invalidate any in-flight fetch
    _debounceTimer?.cancel();
    _hideOverlay();
    if (_focusNode.hasFocus) _focusNode.unfocus();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _showOverlay();
      // Always open with all restricted candidates — never seed the typeahead
      // with the committed label. Excel-autofilter convention: re-opening the
      // picker with a value already selected must let the user *switch* to a
      // different value, not just see the value they already chose.
      _scheduleSearch('', immediate: true);
      // Select-all so the next keystroke replaces the committed label
      // instead of appending to it.
      if (_controller.text.isNotEmpty) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    } else {
      // Delay so a tap inside the overlay registers before we tear it down.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted || _focusNode.hasFocus) return;
        _hideOverlay();
        // If the user typed but didn't select, revert text to the active
        // selection's label (or empty) so the field always reflects the
        // committed filter.
        final committed = widget.value?['label']?.toString() ?? '';
        if (_controller.text != committed) _controller.text = committed;
      });
    }
  }

  void _scheduleSearch(String term, {bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      _doSearch(term);
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 300), () => _doSearch(term));
    }
  }

  Future<void> _doSearch(String term) async {
    final mySeq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    _overlay?.markNeedsBuild();
    try {
      final results = await _fetchCandidates(term);
      if (mySeq != _seq || !mounted) return;
      setState(() {
        _candidates = results;
        _loading = false;
        _highlightedIndex = results.isEmpty ? -1 : 0;
        _lastAppliedTerm = term;
      });
      _overlay?.markNeedsBuild();
    } catch (e) {
      if (mySeq != _seq || !mounted) return;
      setState(() {
        _candidates = const [];
        _error = e.toString();
        _loading = false;
        _highlightedIndex = -1;
      });
      _overlay?.markNeedsBuild();
    }
  }

  Future<List<_Candidate>> _fetchCandidates(String term) async {
    final scope = <String, dynamic>{};
    if (widget.viewNodeCode != null) scope['viewNodeCode'] = widget.viewNodeCode;
    if (widget.dataFormCode != null) scope['dataFormCode'] = widget.dataFormCode;
    if (widget.elementCode != null) scope['elementCode'] = widget.elementCode;
    final result = await graphqlClient.query(QueryOptions(
      document: gql(r'''
        query EntityRefPickerCandidates($input: PickerCandidatesInput!) {
          entityRefPickerCandidates(input: $input) {
            items { id label }
            totalCount
          }
        }
      '''),
      variables: {
        'input': {
          'scope': scope,
          'columnKey': widget.columnKey,
          if (term.isNotEmpty) 'term': term,
          'page': 0,
          'size': 25,
          // CF3.4.3 protocol additions — backend strips the picker's own
          // column from userFilter and uses editorEntityId to resolve any
          // Janino injectable's getEditorEntity() in the Inner DISTINCT.
          if (widget.userFilter != null) 'userFilter': widget.userFilter,
          if (widget.editorEntityId != null) 'editorEntityId': widget.editorEntityId,
        },
      },
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) throw result.exception!;
    final body = result.data!['entityRefPickerCandidates'] as Map<String, dynamic>;
    final items = (body['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items
        .map((m) => _Candidate(
              id: (m['id'] as num).toInt(),
              label: m['label'] as String,
            ))
        .toList();
  }

  void _showOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_overlay!);
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _moveHighlight(int delta) {
    if (_candidates.isEmpty) return;
    final next = (_highlightedIndex + delta).clamp(0, _candidates.length - 1);
    if (next == _highlightedIndex) return;
    setState(() => _highlightedIndex = next);
    _overlay?.markNeedsBuild();
    _ensureHighlightVisible();
  }

  void _moveHighlightTo(int index) {
    if (_candidates.isEmpty) return;
    final next = index.clamp(0, _candidates.length - 1);
    if (next == _highlightedIndex) return;
    setState(() => _highlightedIndex = next);
    _overlay?.markNeedsBuild();
    _ensureHighlightVisible();
  }

  void _ensureHighlightVisible() {
    if (!_scrollController.hasClients || _highlightedIndex < 0) return;
    final viewport = _scrollController.position.viewportDimension;
    final offset = _scrollController.offset;
    final itemTop = _highlightedIndex * _itemHeight;
    final itemBottom = itemTop + _itemHeight;
    if (itemTop < offset) {
      _scrollController.jumpTo(itemTop);
    } else if (itemBottom > offset + viewport) {
      _scrollController.jumpTo(itemBottom - viewport);
    }
  }

  void _selectHighlighted() {
    if (_highlightedIndex < 0 || _highlightedIndex >= _candidates.length) return;
    _select(_candidates[_highlightedIndex]);
  }

  void _dismissOverlay() {
    _hideOverlay();
    final committed = widget.value?['label']?.toString() ?? '';
    if (_controller.text != committed) {
      _controller.text = committed;
    }
  }

  Widget _buildOverlay(BuildContext ctx) {
    return Positioned(
      width: 240,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 30),
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: _buildOverlayBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayBody() {
    if (_loading && _candidates.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
      );
    }
    if (_candidates.isEmpty) {
      // Two distinct empty states (CF3.4.3 *Frontend UX*):
      //   - cold (no typeahead term): the picker's row-restriction yielded
      //     zero candidates — the user's *other* filters are too narrow.
      //   - typeahead miss: the typed term didn't match any candidate in
      //     the (already restricted) set.
      final isRestrictionEmpty = _lastAppliedTerm.isEmpty;
      final message = isRestrictionEmpty
          ? 'No candidates match the current filters.'
          : 'No matches for "$_lastAppliedTerm".';
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(message, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      itemExtent: _itemHeight,
      itemCount: _candidates.length,
      itemBuilder: (_, i) {
        final c = _candidates[i];
        final highlighted = i == _highlightedIndex;
        return InkWell(
          onTap: () => _select(c),
          onHover: (hovering) {
            if (hovering) _moveHighlightTo(i);
          },
          child: Container(
            color: highlighted ? Colors.blue.shade50 : null,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(c.label, style: const TextStyle(fontSize: 13)),
          ),
        );
      },
    );
  }

  void _select(_Candidate c) {
    setState(() {
      _controller.text = c.label;
    });
    _hideOverlay();
    _focusNode.unfocus();
    widget.onChanged({'id': c.id, 'label': c.label});
  }

  void _clear() {
    setState(() => _controller.clear());
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200),
        child: FilterFieldShell(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveHighlight(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveHighlight(-1),
              const SingleActivator(LogicalKeyboardKey.home): () => _moveHighlightTo(0),
              const SingleActivator(LogicalKeyboardKey.end):
                  () => _moveHighlightTo(_candidates.length - 1),
              const SingleActivator(LogicalKeyboardKey.enter): _selectHighlighted,
              const SingleActivator(LogicalKeyboardKey.numpadEnter): _selectHighlighted,
              const SingleActivator(LogicalKeyboardKey.escape): _dismissOverlay,
            },
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlignVertical: kFilterTextAlignVertical,
              decoration: filterFieldInputDecoration().copyWith(
                suffixIcon: _controller.text.isNotEmpty
                    ? GestureDetector(
                        onTap: _clear,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.clear, size: 14, color: Colors.grey.shade600),
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              ),
              style: kFilterFieldTextStyle,
              onChanged: (v) => _scheduleSearch(v),
            ),
          ),
        ),
      ),
    );
  }
}

class _Candidate {
  _Candidate({required this.id, required this.label});
  final int id;
  final String label;
}
