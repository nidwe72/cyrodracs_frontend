import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphql/client.dart';
import '../../graphql_client.dart';
import 'filter_field_style.dart';

/// Per-column ENUM filter widget. Custom-overlay design (mirrors
/// `EntityRefFilterInput`) — opens an overlay-backed dropdown on click,
/// fetches the column's option set via the `enumValuesForColumn` GraphQL
/// query each time the dropdown opens. Backend handles
/// `restrictByVisibleRows` per columnFilters.md CF3.4.5; frontend
/// always fetches uniformly. Empty result → distinct
/// *"No values match the current filters."* message; request failure →
/// silent fallback to the static [staticEnumValues] list.
class EnumFilterInput extends StatefulWidget {
  const EnumFilterInput({
    super.key,
    required this.columnKey,
    required this.staticEnumValues,
    required this.value,
    required this.onChanged,
    this.viewNodeCode,
    this.dataFormCode,
    this.elementCode,
    this.userFilter,
    this.editorEntityId,
    this.dismissTrigger,
    this.pendingRowEnumValues,
  });

  /// Selected enum constant name, or null when the filter is cleared.
  final String? value;
  final String columnKey;

  /// Upper-bound list of all declared enum constants — fallback when the
  /// dynamic fetch fails (e.g. network error). Comes from
  /// `columnFilterMetadata.enumValues`.
  final List<String> staticEnumValues;

  final String? viewNodeCode;
  final String? dataFormCode;
  final String? elementCode;

  /// Full active CF1 user-filter tree from the host. Backend strips the
  /// dropdown's own column (CF3.4.5 *Stripping rule*).
  final Map<String, dynamic>? userFilter;

  /// Parent editor entity id for GRID surfaces inside an editor.
  final int? editorEntityId;

  /// Fires whenever any column filter on the host changes — OR whenever
  /// the host's pending-row list mutates (CF3.4.6 *Open-dropdown
  /// invalidation*). The overlay closes on each tick.
  final Listenable? dismissTrigger;

  /// CF3.4.6 — pending rows' enum values to OR-union with the
  /// committed-row DISTINCT result. Each entry: `{ fieldName: String,
  /// values: [String] }`. Null/empty → no augmentation.
  final List<Map<String, dynamic>>? pendingRowEnumValues;

  final void Function(String? value) onChanged;

  @override
  State<EnumFilterInput> createState() => _EnumFilterInputState();
}

class _EnumFilterInputState extends State<EnumFilterInput> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  static const double _itemHeight = 32.0;

  OverlayEntry? _overlay;
  int _seq = 0;
  List<String> _options = const [];
  bool _loading = false;
  bool _hasFetched = false;     // true once the first fetch returned
  bool _fellBackToStatic = false;
  int _highlightedIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.dismissTrigger?.addListener(_onHostFilterChanged);
  }

  @override
  void didUpdateWidget(covariant EnumFilterInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dismissTrigger != widget.dismissTrigger) {
      oldWidget.dismissTrigger?.removeListener(_onHostFilterChanged);
      widget.dismissTrigger?.addListener(_onHostFilterChanged);
    }
  }

  @override
  void dispose() {
    widget.dismissTrigger?.removeListener(_onHostFilterChanged);
    _hideOverlay();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onHostFilterChanged() {
    if (!mounted) return;
    if (_overlay == null) return;
    _seq++;     // invalidate any in-flight fetch
    _hideOverlay();
  }

  void _toggle() {
    if (_overlay != null) {
      _hideOverlay();
    } else {
      _showOverlay();
      // Always re-fetch on open — keeps options fresh against the current
      // userFilter / editorEntityId / pendingRowEnumValues snapshot.
      _doFetch();
    }
  }

  Future<void> _doFetch() async {
    final mySeq = ++_seq;
    setState(() {
      _loading = true;
      _fellBackToStatic = false;
    });
    _overlay?.markNeedsBuild();
    try {
      final values = await _fetchValues();
      if (mySeq != _seq || !mounted) return;
      setState(() {
        _options = values;
        _hasFetched = true;
        _loading = false;
        // Highlight the currently selected value if present, else the first.
        if (widget.value != null) {
          _highlightedIndex = values.indexOf(widget.value!);
          if (_highlightedIndex < 0 && values.isNotEmpty) {
            _highlightedIndex = 0;
          }
        } else {
          _highlightedIndex = values.isEmpty ? -1 : 0;
        }
      });
      _overlay?.markNeedsBuild();
    } catch (_) {
      if (mySeq != _seq || !mounted) return;
      setState(() {
        _options = widget.staticEnumValues;
        _loading = false;
        _fellBackToStatic = true;
        _highlightedIndex = _options.isEmpty ? -1 : 0;
      });
      _overlay?.markNeedsBuild();
    }
  }

  Future<List<String>> _fetchValues() async {
    final scope = <String, dynamic>{};
    if (widget.viewNodeCode != null) scope['viewNodeCode'] = widget.viewNodeCode;
    if (widget.dataFormCode != null) scope['dataFormCode'] = widget.dataFormCode;
    if (widget.elementCode != null) scope['elementCode'] = widget.elementCode;
    final result = await graphqlClient.query(QueryOptions(
      document: gql(r'''
        query EnumValuesForColumn($input: EnumValuesInput!) {
          enumValuesForColumn(input: $input) { values }
        }
      '''),
      variables: {
        'input': {
          'scope': scope,
          'columnKey': widget.columnKey,
          if (widget.userFilter != null) 'userFilter': widget.userFilter,
          if (widget.editorEntityId != null) 'editorEntityId': widget.editorEntityId,
          if (widget.pendingRowEnumValues != null &&
              widget.pendingRowEnumValues!.isNotEmpty)
            'pendingRowEnumValues': widget.pendingRowEnumValues,
        },
      },
      fetchPolicy: FetchPolicy.noCache,
    ));
    if (result.hasException) throw result.exception!;
    final body = result.data!['enumValuesForColumn'] as Map<String, dynamic>;
    return (body['values'] as List<dynamic>).cast<String>();
  }

  void _showOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_overlay!);
    _focusNode.requestFocus();
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
    if (_focusNode.hasFocus) _focusNode.unfocus();
  }

  void _select(String? v) {
    widget.onChanged(v);
    _hideOverlay();
  }

  void _moveHighlight(int delta) {
    if (_options.isEmpty) return;
    final next = (_highlightedIndex + delta).clamp(0, _options.length - 1);
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

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_highlightedIndex >= 0 && _highlightedIndex < _options.length) {
        _select(_options[_highlightedIndex]);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hideOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildOverlay(BuildContext ctx) {
    return Positioned(
      width: 200,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 30),
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _onKeyEvent,
              child: _buildOverlayBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayBody() {
    if (_loading && !_hasFetched) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final showFallbackBanner = _fellBackToStatic;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showFallbackBanner)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.orange.shade50,
            child: Text('Using fallback options (server fetch failed)',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
          ),
        // Always-present "any" / clear-filter row.
        InkWell(
          onTap: () => _select(null),
          child: Container(
            height: _itemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            color: widget.value == null ? Colors.blue.shade50 : null,
            child: const Text('any',
                style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey)),
          ),
        ),
        const Divider(height: 1),
        if (_options.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'No values match the current filters.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              itemExtent: _itemHeight,
              itemCount: _options.length,
              itemBuilder: (ctx, i) {
                final v = _options[i];
                final isSelected = v == widget.value;
                final isHighlighted = i == _highlightedIndex;
                return InkWell(
                  onTap: () => _select(v),
                  child: Container(
                    height: _itemHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    color: isHighlighted
                        ? Colors.blue.shade50
                        : (isSelected ? Colors.grey.shade100 : null),
                    child: Text(v, style: const TextStyle(fontSize: 13)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 160),
        child: FilterFieldShell(
          child: InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.value ?? 'any',
                      style: kFilterFieldTextStyle.copyWith(
                        color: widget.value == null ? Colors.grey : Colors.black87,
                        fontStyle: widget.value == null ? FontStyle.italic : FontStyle.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _overlay != null ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
