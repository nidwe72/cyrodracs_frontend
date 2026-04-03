import 'package:flutter/material.dart';
import '../models/app_config_node.dart';

/// Tree row for the AppConfigEditorView.
///
/// Collection nodes are rendered in italic with a folder icon to distinguish
/// them from instance nodes (which show bold text when selected).
class AppConfigTreeRow extends StatelessWidget {
  final AppConfigNode node;
  final int depth;
  final bool isSelected;
  final bool isExpanded;
  final bool hasChildren;
  final bool isMatch;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggle;

  const AppConfigTreeRow({
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

    final bool isCol = node.isCollection;

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
            if (isCol)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.folder_outlined,
                    size: 14, color: Colors.grey.shade600),
              ),
            Expanded(
              child: Text(
                node.label,
                style: TextStyle(
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  fontStyle:
                      isCol ? FontStyle.italic : FontStyle.normal,
                  color: isCol ? Colors.grey.shade700 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
