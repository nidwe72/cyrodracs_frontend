import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_config_node.dart';
import 'app_config_service.dart';
import 'app_config_tree_row.dart';
import 'app_config_detail_panel.dart';

class _VisibleNode {
  final AppConfigNode node;
  final String key;
  final int depth;
  final String? parentKey;

  const _VisibleNode({
    required this.node,
    required this.key,
    required this.depth,
    this.parentKey,
  });
}

class AppConfigEditorView extends StatefulWidget {
  const AppConfigEditorView({super.key});

  @override
  State<AppConfigEditorView> createState() => _AppConfigEditorViewState();
}

class _AppConfigEditorViewState extends State<AppConfigEditorView> {
  final _service = AppConfigService();

  AppConfigNode? _root;
  String? _error;

  final Set<String> _expandedKeys = {};
  String? _selectedKey;
  String _searchPattern = '';
  List<String> _matchKeys = [];
  int _matchIndex = -1;

  AppConfigNode? _detailNode;
  String? _detailKey;

  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _fetchTree();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _fetchTree() async {
    setState(() {
      _error = null;
      _root = null;
    });
    try {
      final root = await _service.fetchTree();
      setState(() => _root = root);
      _focusNode.requestFocus();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _onTreeChanged(AppConfigNode updatedTree) {
    setState(() {
      _root = updatedTree;
      _detailNode = null;
      _detailKey = null;
      _selectedKey = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Visible-node list
  // ---------------------------------------------------------------------------

  List<_VisibleNode> _buildVisible() {
    final result = <_VisibleNode>[];
    if (_root != null) _collect(_root!, 'root', 0, null, result);
    return result;
  }

  void _collect(AppConfigNode node, String key, int depth, String? parentKey,
      List<_VisibleNode> out) {
    out.add(_VisibleNode(node: node, key: key, depth: depth, parentKey: parentKey));
    if (_expandedKeys.contains(key)) {
      for (var i = 0; i < node.children.length; i++) {
        _collect(node.children[i], '$key-$i', depth + 1, key, out);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  void _updateSearch(String pattern) {
    final matches = pattern.isEmpty
        ? <String>[]
        : _buildVisible()
            .where((vn) =>
                vn.node.label.toLowerCase().contains(pattern.toLowerCase()))
            .map((vn) => vn.key)
            .toList();
    setState(() {
      _searchPattern = pattern;
      _matchKeys = matches;
      _matchIndex = matches.isNotEmpty ? 0 : -1;
      if (matches.isNotEmpty) _selectedKey = matches[0];
    });
    if (matches.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _clearSearch() {
    setState(() {
      _searchPattern = '';
      _matchKeys = [];
      _matchIndex = -1;
    });
    _focusNode.requestFocus();
  }

  void _navigateMatch(int delta) {
    if (_matchKeys.isEmpty) return;
    final newIndex =
        (_matchIndex + delta + _matchKeys.length) % _matchKeys.length;
    setState(() {
      _matchIndex = newIndex;
      _selectedKey = _matchKeys[newIndex];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  // ---------------------------------------------------------------------------
  // Selection & scroll
  // ---------------------------------------------------------------------------

  void _showDetail(String key, AppConfigNode node) =>
      setState(() {
        _detailKey = key;
        _detailNode = node;
      });

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;
    final visible = _buildVisible();
    final idx = visible.indexWhere((n) => n.key == _selectedKey);
    if (idx < 0) return;
    const rowHeight = 32.0;
    final offset = (idx * rowHeight).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(offset,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  // ---------------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchPattern.isNotEmpty) {
        _clearSearch();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_searchPattern.isNotEmpty) {
        _updateSearch(_searchPattern.substring(0, _searchPattern.length - 1));
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_searchPattern.isNotEmpty) {
        _navigateMatch(1);
      } else {
        final visible = _buildVisible();
        final idx = visible.indexWhere((n) => n.key == _selectedKey);
        if (idx == -1 && visible.isNotEmpty) {
          setState(() => _selectedKey = visible[0].key);
        } else if (idx + 1 < visible.length) {
          setState(() => _selectedKey = visible[idx + 1].key);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToSelected());
        }
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_searchPattern.isNotEmpty) {
        _navigateMatch(-1);
      } else {
        final visible = _buildVisible();
        final idx = visible.indexWhere((n) => n.key == _selectedKey);
        if (idx > 0) {
          setState(() => _selectedKey = visible[idx - 1].key);
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _scrollToSelected());
        }
      }
      return KeyEventResult.handled;
    }

    if (_searchPattern.isEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        final visible = _buildVisible();
        final idx = visible.indexWhere((n) => n.key == _selectedKey);
        if (idx >= 0 &&
            visible[idx].node.children.isNotEmpty &&
            !_expandedKeys.contains(visible[idx].key)) {
          setState(() => _expandedKeys.add(visible[idx].key));
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        final visible = _buildVisible();
        final idx = visible.indexWhere((n) => n.key == _selectedKey);
        if (idx >= 0) {
          final cur = visible[idx];
          if (_expandedKeys.contains(cur.key)) {
            setState(() => _expandedKeys.remove(cur.key));
          } else if (cur.parentKey != null) {
            setState(() => _selectedKey = cur.parentKey);
          }
        }
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final visible = _buildVisible();
      if (visible.isEmpty) return KeyEventResult.ignored;
      final vn = visible.firstWhere((n) => n.key == _selectedKey,
          orElse: () => visible.first);
      _showDetail(vn.key, vn.node);
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty && char.codeUnitAt(0) >= 32) {
      _updateSearch(_searchPattern + char);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error: $_error',
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _fetchTree, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_root == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final visible = _buildVisible();
    final matchKeySet = _matchKeys.toSet();

    final treePanel = Column(
      children: [
        _buildTreeHeader(),
        if (_searchPattern.isNotEmpty) _buildSearchBar(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: visible.length,
            itemExtent: 32,
            itemBuilder: (context, i) {
              final vn = visible[i];
              return AppConfigTreeRow(
                node: vn.node,
                depth: vn.depth,
                isSelected: vn.key == _selectedKey,
                isExpanded: _expandedKeys.contains(vn.key),
                hasChildren: vn.node.children.isNotEmpty,
                isMatch: matchKeySet.contains(vn.key),
                onTap: () {
                  setState(() => _selectedKey = vn.key);
                  _focusNode.requestFocus();
                },
                onDoubleTap: () {
                  setState(() => _selectedKey = vn.key);
                  _showDetail(vn.key, vn.node);
                  // Do not re-focus the tree – the detail panel needs focus next.
                },
                onToggle: () => setState(() {
                  if (_expandedKeys.contains(vn.key)) {
                    _expandedKeys.remove(vn.key);
                  } else {
                    _expandedKeys.add(vn.key);
                  }
                }),
              );
            },
          ),
        ),
      ],
    );

    final detailPanel = AppConfigDetailPanel(
      key: ValueKey(_detailKey),
      node: _detailNode,
      root: _root,
      stale: _detailKey != _selectedKey,
      service: _service,
      onTreeChanged: _onTreeChanged,
    );

    // Focus scoped to the tree panel only – so _onKey is never in the ancestor
    // chain when a TextField inside the detail panel has focus.
    final focusedTree = Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: treePanel,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              Expanded(child: focusedTree),
              const Divider(height: 1, thickness: 1),
              Expanded(child: detailPanel),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 320, child: focusedTree),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(child: detailPanel),
          ],
          );
        },
    );
  }

  Widget _buildTreeHeader() {
    return Container(
      height: 36,
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Text('Config Tree',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            tooltip: 'Reload',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: _fetchTree,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_searchPattern,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
          if (_matchKeys.isNotEmpty)
            Text('${_matchIndex + 1} / ${_matchKeys.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey))
          else
            const Text('no matches',
                style: TextStyle(fontSize: 12, color: Colors.red)),
          const SizedBox(width: 8),
          InkWell(
              onTap: _clearSearch, child: const Icon(Icons.close, size: 16)),
        ],
      ),
    );
  }
}
