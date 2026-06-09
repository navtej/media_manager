import 'package:flutter/widgets.dart';
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
            child: const Text('Select Loaded'),
          ),
          const SizedBox(width: 12),
          Text(
            '$selectedCount Selected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.typography.body,
          ),
          const SizedBox(width: 12),
          PushButton(
            controlSize: ControlSize.regular,
            onPressed: canUseSelection ? onMove : null,
            child: const Text('Move'),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onDelete : null,
            child: const Text('Delete'),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onFavorite : null,
            child: const Text('Favorite'),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onUnfavorite : null,
            child: const Text('Unfavorite'),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onClearTags : null,
            child: const Text('Clear Tags'),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? onClearSelection : null,
            child: const Text('Clear Selection'),
          ),
        ],
      ),
    );
  }
}
