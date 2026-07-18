import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

class MacosPreferenceCheckbox extends StatelessWidget {
  const MacosPreferenceCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      checked: value,
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: value ? theme.primaryColor : MacosColors.transparent,
            border: Border.all(
              color: value
                  ? theme.primaryColor
                  : MacosColors.systemGrayColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: value
              ? const MacosIcon(
                  CupertinoIcons.checkmark,
                  size: 12,
                  color: MacosColors.white,
                )
              : null,
        ),
      ),
    );
  }
}
