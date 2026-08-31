import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../movie_manager_visual_system.dart';

class MacosPreferenceCheckbox extends StatefulWidget {
  const MacosPreferenceCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.emphasized = false,
    this.lightBackground = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;
  final bool emphasized;
  final bool lightBackground;

  @override
  State<MacosPreferenceCheckbox> createState() =>
      _MacosPreferenceCheckboxState();
}

class _MacosPreferenceCheckboxState extends State<MacosPreferenceCheckbox> {
  late final FocusNode _focusNode;
  bool _showFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.semanticLabel);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final enabled = widget.onChanged != null;
    final borderColor = widget.value || widget.emphasized
        ? theme.primaryColor
        : MacosDynamicColor.resolve(
            MacosColors.systemGrayColor,
            context,
          ).withValues(alpha: 0.55);
    return Semantics(
      checked: widget.value,
      enabled: enabled,
      focusable: enabled,
      focused: _focusNode.hasFocus,
      onFocus: enabled ? _focusNode.requestFocus : null,
      onTap: enabled ? _toggle : null,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: _focusNode,
        onShowFocusHighlight: (value) {
          if (_showFocus != value) setState(() => _showFocus = value);
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _toggle : null,
          child: SizedBox.square(
            dimension: MovieManagerControlMetrics.minimumTarget,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MovieManagerRadii.control),
                border: _showFocus
                    ? Border.all(color: theme.primaryColor, width: 2)
                    : null,
              ),
              child: Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: widget.value
                        ? theme.primaryColor
                        : widget.lightBackground
                        ? MacosColors.white
                        : widget.emphasized
                        ? theme.canvasColor.withValues(alpha: 0.92)
                        : MacosColors.transparent,
                    border: Border.all(
                      color: borderColor,
                      width: widget.emphasized ? 2 : 1.5,
                    ),
                  ),
                  child: widget.value
                      ? const Icon(
                          CupertinoIcons.checkmark,
                          size: 12,
                          color: MacosColors.white,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
