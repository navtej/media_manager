import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:icon_craft/icon_craft.dart';
import 'package:macos_ui/macos_ui.dart';

class BulkSelectionToolbar extends StatelessWidget {
  const BulkSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.isBusy,
    required this.onSelectLoaded,
    required this.onMove,
    required this.onDelete,
    required this.onFavorite,
    required this.onUnfavorite,
    required this.onClearTags,
    required this.onClearSelection,
  });

  final int selectedCount;
  final bool isBusy;
  final VoidCallback? onSelectLoaded;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback? onFavorite;
  final VoidCallback? onUnfavorite;
  final VoidCallback? onClearTags;
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final hasSelection = selectedCount > 0;
    final canUseSelection = hasSelection && !isBusy;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: isBusy ? null : onSelectLoaded,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.check_mark_circled, size: 16),
              label: 'Select Loaded',
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              '$selectedCount Selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body,
            ),
          ),
          const SizedBox(width: 12),
          PushButton(
            controlSize: ControlSize.regular,
            onPressed: canUseSelection ? onMove : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.arrow_right_arrow_left, size: 16),
              label: 'Move',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onDelete : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.trash, size: 16),
              label: 'Delete',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onFavorite : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(
                CupertinoIcons.heart_fill,
                color: MacosColors.appleRed,
                size: 16,
              ),
              label: 'Favorite',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onUnfavorite : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.heart, size: 16),
              label: 'Unfavorite',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onClearTags : null,
            child: const _ToolbarButtonLabel(
              icon: IconCraft(
                Icon(CupertinoIcons.tag, size: 16),
                Icon(CupertinoIcons.clear_thick, size: 10),
                alignment: Alignment(1.2, -1.1),
                secondaryIconSizeFactor: 0.5,
              ),
              label: 'Clear Tags',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onClearSelection : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.clear_circled, size: 16),
              label: 'Clear Selection',
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButtonLabel extends StatelessWidget {
  const _ToolbarButtonLabel({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [icon, const SizedBox(width: 6), Text(label)],
    );
  }
}
