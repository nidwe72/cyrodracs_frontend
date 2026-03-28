import 'package:flutter/material.dart';
import '../models/test_node.dart';

class DetailPanel extends StatelessWidget {
  final TestNode? node;
  final bool stale;

  const DetailPanel({super.key, this.node, this.stale = false});

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
