import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

abstract final class MovieManagerSpacing {
  static const compact = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const extraLarge = 24.0;

  static const values = <double>[compact, small, medium, large, extraLarge];
}

abstract final class MovieManagerRadii {
  static const control = 6.0;
  static const panel = 8.0;
  static const dialog = 12.0;
}

abstract final class MovieManagerIconSizes {
  static const inline = 14.0;
  static const action = 16.0;
  static const emphasis = 20.0;
}

abstract final class MovieManagerControlMetrics {
  static const minimumTarget = 28.0;
}

abstract final class MovieManagerWindowMetrics {
  static const minimumContentSize = Size(800, 600);
  static const referenceContentSize = Size(1200, 800);
}

abstract final class MovieManagerVisuals {
  static Color surfaceColorFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? MacosColors.controlBackgroundColor.darkColor
      : MacosColors.controlBackgroundColor.color;

  static Color surfaceColor(BuildContext context) =>
      surfaceColorFor(MacosTheme.of(context).brightness);

  static Color secondaryLabelColor(BuildContext context) {
    final brightness = MacosTheme.of(context).brightness;
    return brightness == Brightness.dark
        ? MacosColors.secondaryLabelColor.darkColor
        : MacosColors.secondaryLabelColor.color;
  }

  static Color tertiaryLabelColor(BuildContext context) {
    final brightness = MacosTheme.of(context).brightness;
    return brightness == Brightness.dark
        ? MacosColors.tertiaryLabelColor.darkColor
        : MacosColors.tertiaryLabelColor.color;
  }

  static Color errorColor(BuildContext context) =>
      MacosDynamicColor.resolve(MacosColors.systemRedColor, context);

  static Color successColor(BuildContext context) =>
      MacosDynamicColor.resolve(MacosColors.systemGreenColor, context);

  static Color warningColor(BuildContext context) =>
      MacosDynamicColor.resolve(MacosColors.systemOrangeColor, context);

  static BoxDecoration panelDecoration(
    BuildContext context, {
    Color? color,
    bool selected = false,
    bool focused = false,
  }) {
    final theme = MacosTheme.of(context);
    return BoxDecoration(
      color:
          color ??
          (selected
              ? theme.primaryColor.withValues(alpha: 0.12)
              : surfaceColor(context)),
      borderRadius: BorderRadius.circular(MovieManagerRadii.panel),
      border: Border.all(
        color: selected || focused ? theme.primaryColor : theme.dividerColor,
        width: focused ? 2 : 1,
      ),
      boxShadow: focused
          ? [
              BoxShadow(
                color: theme.primaryColor.withValues(alpha: 0.16),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ]
          : null,
    );
  }
}

class MovieManagerIconButton extends StatefulWidget {
  const MovieManagerIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool selected;

  @override
  State<MovieManagerIconButton> createState() => _MovieManagerIconButtonState();
}

class _MovieManagerIconButtonState extends State<MovieManagerIconButton> {
  late final FocusNode _focusNode;
  bool _showFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.label);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      label: widget.label,
      button: true,
      enabled: enabled,
      selected: widget.selected ? true : null,
      focusable: enabled,
      focused: _focusNode.hasFocus,
      onFocus: enabled ? _focusNode.requestFocus : null,
      child: MacosTooltip(
        message: widget.label,
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
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: SizedBox.square(
            dimension: MovieManagerControlMetrics.minimumTarget,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _showFocus
                    ? Border.all(
                        color: MacosTheme.of(context).primaryColor,
                        width: 2,
                      )
                    : null,
                borderRadius: BorderRadius.circular(MovieManagerRadii.control),
              ),
              child: MacosIconButton(
                semanticLabel: widget.label,
                boxConstraints: const BoxConstraints.tightFor(
                  width: MovieManagerControlMetrics.minimumTarget,
                  height: MovieManagerControlMetrics.minimumTarget,
                ),
                padding: const EdgeInsets.all(MovieManagerSpacing.compact),
                borderRadius: BorderRadius.circular(MovieManagerRadii.control),
                icon: Icon(
                  widget.icon,
                  size: MovieManagerIconSizes.action,
                  color: widget.color,
                ),
                onPressed: widget.onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MovieManagerStateMessage extends StatelessWidget {
  const MovieManagerStateMessage({
    super.key,
    this.icon,
    this.indicator,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.iconColor,
  }) : assert(icon != null || indicator != null);

  final IconData? icon;
  final Widget? indicator;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      container: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: EdgeInsets.all(
              compact
                  ? MovieManagerSpacing.medium
                  : MovieManagerSpacing.extraLarge,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                indicator ??
                    MacosIcon(
                      icon!,
                      size: MovieManagerIconSizes.emphasis,
                      color:
                          iconColor ??
                          MovieManagerVisuals.secondaryLabelColor(context),
                    ),
                const SizedBox(height: MovieManagerSpacing.small),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.typography.headline,
                ),
                if (message != null) ...[
                  const SizedBox(height: MovieManagerSpacing.compact),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: theme.typography.body.copyWith(
                      color: MovieManagerVisuals.secondaryLabelColor(context),
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: MovieManagerSpacing.medium),
                  PushButton(
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
