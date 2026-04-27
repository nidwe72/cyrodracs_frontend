import 'package:flutter/material.dart';
import 'filter_field_style.dart';

/// Compact button-like field used by date / year-month / datetime range
/// filters. Shows [text] in normal style, or [placeholder] in muted style,
/// and an inline clear icon when [onClear] is non-null. When [width] is
/// null, the button takes its parent's bounded horizontal constraint
/// (e.g. an `Expanded` parent in a Row).
class PickerButton extends StatelessWidget {
  const PickerButton({
    super.key,
    this.width,
    required this.text,
    required this.placeholder,
    required this.onTap,
    this.onClear,
  });

  final double? width;
  final String? text;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = text != null && text!.isNotEmpty;
    final inner = SizedBox(
      width: width,
      height: kFilterFieldHeight,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Colors.grey.shade400),
          borderRadius: BorderRadius.zero,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hasValue ? text! : placeholder,
                    style: hasValue
                        ? kFilterFieldTextStyle.copyWith(color: Colors.black87)
                        : kFilterFieldHintStyle,
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
    if (width != null) return inner;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100),
      child: inner,
    );
  }
}
