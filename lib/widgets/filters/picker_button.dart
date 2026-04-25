import 'package:flutter/material.dart';

/// Compact button-like field used by date / year-month / datetime range
/// filters. Shows [text] in normal style, or [placeholder] in muted style,
/// and an inline clear icon when [onClear] is non-null.
class PickerButton extends StatelessWidget {
  const PickerButton({
    super.key,
    required this.width,
    required this.text,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  final double width;
  final String? text;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = text != null && text!.isNotEmpty;
    return SizedBox(
      width: width,
      height: 28,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue ? text! : placeholder,
                    style: TextStyle(
                      fontSize: 12,
                      color: hasValue ? Colors.black87 : Colors.grey.shade500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasValue && onClear != null)
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.clear, size: 12, color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
