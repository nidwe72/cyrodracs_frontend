import 'package:flutter/material.dart';
import '../models/test_node.dart';

class TreeRow extends StatelessWidget {
  final TestNode node;
  final int depth;
  final bool isSelected;
  final bool isExpanded;
  final bool hasChildren;
  final bool isMatch;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggle;

  const TreeRow({
    super.key,
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
