import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyrodracs',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _helloMessage;

  Future<void> _onHelloPressed() async {
    final response = await http.get(Uri.parse('http://localhost:8080/api/hello'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _helloMessage = 'Hello World (${data['number']})';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF424242),
          title: const Text('Cyrodracs', style: TextStyle(color: Colors.white)),
        ),
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Admin'),
                Tab(text: 'Basic'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const _AdminTab(),
                  _BasicTab(
                    helloMessage: _helloMessage,
                    onHelloPressed: _onHelloPressed,
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

class TestNode {
  final String code;
  final List<TestNode> children;

  TestNode({required this.code, required this.children});

  factory TestNode.fromJson(Map<String, dynamic> json) {
    return TestNode(
      code: json['code'] as String,
      children: (json['children'] as List<dynamic>)
          .map((c) => TestNode.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}


class _AdminTab extends StatelessWidget {
  const _AdminTab();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Config'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ConfigView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigView extends StatefulWidget {
  const _ConfigView();

  @override
  State<_ConfigView> createState() => _ConfigViewState();
}

class _VisibleNode {
  final TestNode node;
  final String key;
  final int depth;
  final String? parentKey;

  const _VisibleNode({required this.node, required this.key, required this.depth, this.parentKey});
}

class _ConfigViewState extends State<_ConfigView> {
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

  // Expand all ancestors of a node so it becomes visible
  void _expandToKey(String key) {
    final parts = key.split('-');
    var path = parts[0];
    for (var i = 1; i < parts.length; i++) {
      _expandedKeys.add(path);
      path = '$path-${parts[i]}';
    }
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

    // Printable character → append to search pattern
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

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Row(
        children: [
          SizedBox(
            width: 320,
            child: Column(
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
                      return _TreeRow(
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
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _DetailPanel(node: _detailNode, stale: _detailKey != _selectedKey)),
        ],
      ),
    );
  }
}

class _TreeRow extends StatelessWidget {
  final TestNode node;
  final int depth;
  final bool isSelected;
  final bool isExpanded;
  final bool hasChildren;
  final bool isMatch;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggle;

  const _TreeRow({
    required this.node,
    required this.depth,
    required this.isSelected,
    required this.isExpanded,
    required this.hasChildren,
    required this.isMatch,
    required this.onTap,
    required this.onDoubleTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final Color? bgColor;
    if (isSelected) {
      bgColor = Colors.lightBlue.shade100;
    } else if (isMatch) {
      bgColor = Colors.grey.shade200;
    } else {
      bgColor = null;
    }

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        height: 32,
        color: bgColor,
        padding: EdgeInsets.only(left: depth * 16.0),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: hasChildren
                  ? GestureDetector(
                      onTap: onToggle,
                      child: Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Text(
                node.code,
                style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final TestNode? node;
  final bool stale;

  const _DetailPanel({this.node, this.stale = false});

  @override
  Widget build(BuildContext context) {
    if (node == null) {
      return const Center(
        child: Text(
          'Select a node and press Enter\nor double-click to view details',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(node!.code, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Children: ${node!.children.length}'),
          if (node!.children.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            Expanded(
              child: ListView(
                children: node!.children
                    .map((c) => ListTile(dense: true, title: Text(c.code)))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
    if (!stale) return content;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0.33, 0.33, 0.33, 0, 0,
        0,    0,    0,    0.4, 0,
      ]),
      child: content,
    );
  }
}

class _BasicTab extends StatelessWidget {
  final String? helloMessage;
  final VoidCallback onHelloPressed;

  const _BasicTab({required this.helloMessage, required this.onHelloPressed});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Hello World'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: onHelloPressed,
                        child: const Text('Hello World'),
                      ),
                      if (helloMessage != null) ...[
                        const SizedBox(height: 24),
                        SelectableText(
                          helloMessage!,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
