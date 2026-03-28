import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/test_node.dart';
import 'tree_row.dart';
import 'detail_panel.dart';

class _VisibleNode {
  final TestNode node;
  final String key;
  final int depth;
  final String? parentKey;

  const _VisibleNode({required this.node, required this.key, required this.depth, this.parentKey});
}

class ConfigView extends StatefulWidget {
  const ConfigView({super.key});

  @override
  State<ConfigView> createState() => _ConfigViewState();
}

class _ConfigViewState extends State<ConfigView> {
  TestNode? _root;
  String? _error;
  final Set<String> _expandedKeys = {};
  String? _selectedKey;
  String _searchPattern = '';
  List<String> _matchKeys = [];
  int _matchIndex = -1;
  TestNode? _detailNode;
  String? _detailKey;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

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

  Future<void> _fetchTree() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:8080/api/tree'));
      if (response.statusCode == 200) {
        setState(() => _root = TestNode.fromJson(jsonDecode(response.body)));
        _focusNode.requestFocus();
      } else {
        setState(() => _error = 'HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  List<_VisibleNode> _buildVisible() {
    final result = <_VisibleNode>[];
    if (_root != null) _collect(_root!, 'root', 0, null, result);
    return result;
  }

  void _collect(TestNode node, String key, int depth, String? parentKey, List<_VisibleNode> out) {
    out.add(_VisibleNode(node: node, key: key, depth: depth, parentKey: parentKey));
    if (_expandedKeys.contains(key)) {
      for (var i = 0; i < node.children.length; i++) {
        _collect(node.children[i], '$key-$i', depth + 1, key, out);
      }
    }
  }

  List<String> _findMatchesInVisible(String pattern) {
    return _buildVisible()
        .where((vn) => vn.node.code.toLowerCase().contains(pattern.toLowerCase()))
        .map((vn) => vn.key)
        .toList();
  }

  void _updateSearch(String pattern) {
    final matches = pattern.isEmpty ? <String>[] : _findMatchesInVisible(pattern);
    final hasMatches = matches.isNotEmpty;
    setState(() {
      _searchPattern = pattern;
      _matchKeys = matches;
      _matchIndex = hasMatches ? 0 : -1;
      if (hasMatches) _selectedKey = matches[0];
    });
    if (hasMatches) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
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
    final newIndex = (_matchIndex + delta + _matchKeys.length) % _matchKeys.length;
    setState(() {
      _matchIndex = newIndex;
      _selectedKey = _matchKeys[newIndex];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  void _showDetail(String key, TestNode node) => setState(() { _detailKey = key; _detailNode = node; });

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
    _scrollController.animateTo(offset, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchPattern.isNotEmpty) { _clearSearch(); return KeyEventResult.handled; }
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
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
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
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
        }
      }
      return KeyEventResult.handled;
    }

    if (_searchPattern.isEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        final visible = _buildVisible();
        final idx = visible.indexWhere((n) => n.key == _selectedKey);
        if (idx >= 0) {
          final cur = visible[idx];
          if (cur.node.children.isNotEmpty && !_expandedKeys.contains(cur.key)) {
            setState(() => _expandedKeys.add(cur.key));
          }
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
      final vn = visible.firstWhere((n) => n.key == _selectedKey, orElse: () => visible.first);
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text('Error: $_error'));
    if (_root == null) return const Center(child: CircularProgressIndicator());

    final visible = _buildVisible();
    final matchKeySet = _matchKeys.toSet();

    final treePanel = Column(
      children: [
        if (_searchPattern.isNotEmpty)
          Container(
            color: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.search, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_searchPattern, style: const TextStyle(fontFamily: 'monospace')),
                ),
                if (_matchKeys.isNotEmpty)
                  Text('${_matchIndex + 1} / ${_matchKeys.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey))
                else
                  const Text('no matches', style: TextStyle(fontSize: 12, color: Colors.red)),
                const SizedBox(width: 8),
                InkWell(onTap: _clearSearch, child: const Icon(Icons.close, size: 16)),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: visible.length,
            itemExtent: 32,
            itemBuilder: (context, i) {
              final vn = visible[i];
              final isSelected = vn.key == _selectedKey;
              final isExpanded = _expandedKeys.contains(vn.key);
              final hasChildren = vn.node.children.isNotEmpty;
              final isMatch = matchKeySet.contains(vn.key);
              return TreeRow(
                node: vn.node,
                depth: vn.depth,
                isSelected: isSelected,
                isExpanded: isExpanded,
                hasChildren: hasChildren,
                isMatch: isMatch,
                onTap: () {
                  setState(() => _selectedKey = vn.key);
                  _focusNode.requestFocus();
                },
                onDoubleTap: () {
                  setState(() => _selectedKey = vn.key);
                  _showDetail(vn.key, vn.node);
                  _focusNode.requestFocus();
                },
                onToggle: () => setState(() {
                  if (isExpanded) {
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

    final detailPanel = DetailPanel(node: _detailNode, stale: _detailKey != _selectedKey);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              children: [
                Expanded(child: treePanel),
                const Divider(height: 1, thickness: 1),
                Expanded(child: detailPanel),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 320, child: treePanel),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: detailPanel),
            ],
          );
        },
      ),
    );
  }
}
