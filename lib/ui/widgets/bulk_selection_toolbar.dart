import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:icon_craft/icon_craft.dart';
import 'package:macos_ui/macos_ui.dart';
import '../movie_manager_visual_system.dart';

class BulkSelectionToolbar extends StatefulWidget {
  const BulkSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.isBusy,
    required this.onSelectLoaded,
    this.maxLoadedVideoCount = 0,
    this.onSelectRandom,
    this.onCopyYoutubeUrls,
    required this.onPlay,
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
  final int maxLoadedVideoCount;
  final ValueChanged<int>? onSelectRandom;
  final VoidCallback? onCopyYoutubeUrls;
  final VoidCallback? onPlay;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;
  final VoidCallback? onFavorite;
  final VoidCallback? onUnfavorite;
  final VoidCallback? onClearTags;
  final VoidCallback? onClearSelection;

  @override
  State<BulkSelectionToolbar> createState() => _BulkSelectionToolbarState();
}

class _BulkSelectionToolbarState extends State<BulkSelectionToolbar> {
  late final TextEditingController _randomCountController;

  @override
  void initState() {
    super.initState();
    _randomCountController = TextEditingController(text: '1');
  }

  @override
  void didUpdateWidget(covariant BulkSelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxLoadedVideoCount != widget.maxLoadedVideoCount) {
      _clampRandomCount();
    }
  }

  @override
  void dispose() {
    _randomCountController.dispose();
    super.dispose();
  }

  int get _maxLoadedVideoCount =>
      widget.maxLoadedVideoCount < 0 ? 0 : widget.maxLoadedVideoCount;

  int? get _randomCount {
    final count = int.tryParse(_randomCountController.text.trim());
    if (count == null || count < 0 || count > _maxLoadedVideoCount) {
      return null;
    }
    return count;
  }

  void _handleRandomCountChanged(String value) {
    final count = int.tryParse(value.trim());
    if (count != null && count > _maxLoadedVideoCount) {
      final capped = _maxLoadedVideoCount.toString();
      _randomCountController.value = TextEditingValue(
        text: capped,
        selection: TextSelection.collapsed(offset: capped.length),
      );
    }
    setState(() {});
  }

  void _clampRandomCount() {
    final count = int.tryParse(_randomCountController.text.trim());
    if (count == null || count <= _maxLoadedVideoCount) {
      return;
    }
    final capped = _maxLoadedVideoCount.toString();
    _randomCountController.value = TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }

  void _selectRandom() {
    final count = _randomCount;
    if (count == null || widget.isBusy) {
      return;
    }
    widget.onSelectRandom?.call(count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final hasSelection = widget.selectedCount > 0;
    final canUseSelection = hasSelection && !widget.isBusy;
    final randomFieldEnabled = !widget.isBusy && _maxLoadedVideoCount > 0;
    final canSelectRandom =
        randomFieldEnabled &&
        _randomCount != null &&
        widget.onSelectRandom != null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SelectionGroupBox(
            key: const ValueKey('bulk-selection-group'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: widget.isBusy ? null : widget.onSelectLoaded,
                  child: const _ToolbarButtonLabel(
                    icon: Icon(CupertinoIcons.check_mark_circled, size: 16),
                    label: 'Loaded',
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 48,
                  child: MovieManagerLabeledField(
                    label: 'Random video count',
                    controller: _randomCountController,
                    enabled: randomFieldEnabled,
                    builder: (focusNode) => MacosTextField(
                      key: const ValueKey('bulk-random-count-field'),
                      controller: _randomCountController,
                      focusNode: focusNode,
                      enabled: randomFieldEnabled,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      placeholder: '1',
                      onChanged: _handleRandomCountChanged,
                      onSubmitted: (_) => _selectRandom(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                PushButton(
                  key: const ValueKey('bulk-random-button'),
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: canSelectRandom ? _selectRandom : null,
                  child: const Text('Random'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              '${widget.selectedCount} Selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body,
            ),
          ),
          const SizedBox(width: 12),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: !hasSelection,
            onPressed: canUseSelection ? widget.onPlay : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.play_fill, size: 16),
              label: 'Play',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? widget.onMove : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.arrow_right_arrow_left, size: 16),
              label: 'Move',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? widget.onDelete : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.trash, size: 16),
              label: 'Delete',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? widget.onFavorite : null,
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
            onPressed: canUseSelection ? widget.onUnfavorite : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.heart, size: 16),
              label: 'Unfavorite',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? widget.onClearTags : null,
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
            onPressed: canUseSelection ? widget.onClearSelection : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.clear_circled, size: 16),
              label: 'Clear Selection',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            key: const ValueKey('bulk-copy-youtube-urls-button'),
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? widget.onCopyYoutubeUrls : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.doc_on_clipboard, size: 16),
              label: 'Copy YouTube URLs',
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionGroupBox extends StatelessWidget {
  const _SelectionGroupBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      container: true,
      label: 'Select',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: MovieManagerVisuals.panelDecoration(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: child,
            ),
          ),
          Positioned(
            left: 10,
            top: -7,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: MovieManagerVisuals.surfaceColor(context),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ExcludeSemantics(
                    child: Text('Select', style: theme.typography.caption2),
                  ),
                ),
              ),
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
