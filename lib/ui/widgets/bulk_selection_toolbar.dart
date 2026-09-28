import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:icon_craft/icon_craft.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../logic/catalog_controller.dart';
import '../movie_manager_visual_system.dart';

class BulkSelectionToolbar extends StatefulWidget {
  const BulkSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.isBusy,
    required this.onSelectLoaded,
    this.maxLoadedVideoCount = 0,
    this.maxVideoCount,
    this.onSelectRandom,
    this.onSelectMode,
    this.onCopyYoutubeUrls,
    this.showSelectedOnly = false,
    this.onToggleShowSelectedOnly,
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
  final int? maxVideoCount;
  final ValueChanged<int>? onSelectRandom;
  final void Function(CatalogSelectionMode mode, int count)? onSelectMode;
  final VoidCallback? onCopyYoutubeUrls;
  final bool showSelectedOnly;
  final VoidCallback? onToggleShowSelectedOnly;
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
  late final TextEditingController _selectionCountController;

  @override
  void initState() {
    super.initState();
    _selectionCountController = TextEditingController(text: '1');
  }

  @override
  void didUpdateWidget(covariant BulkSelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.maxVideoCount != null &&
        (oldWidget.maxLoadedVideoCount != widget.maxLoadedVideoCount ||
            oldWidget.maxVideoCount != widget.maxVideoCount)) {
      _clampSelectionCount();
    }
  }

  @override
  void dispose() {
    _selectionCountController.dispose();
    super.dispose();
  }

  int get _maxSelectionCount {
    final value = widget.maxVideoCount ?? widget.maxLoadedVideoCount;
    return value < 0 ? 0 : value;
  }

  int? get _selectionCount {
    final count = int.tryParse(_selectionCountController.text.trim());
    if (count == null || count < 0 || count > _maxSelectionCount) {
      return null;
    }
    return count;
  }

  void _handleSelectionCountChanged(String value) {
    final count = int.tryParse(value.trim());
    if (count != null && count > _maxSelectionCount) {
      final capped = _maxSelectionCount.toString();
      _selectionCountController.value = TextEditingValue(
        text: capped,
        selection: TextSelection.collapsed(offset: capped.length),
      );
    }
    setState(() {});
  }

  void _clampSelectionCount() {
    final count = int.tryParse(_selectionCountController.text.trim());
    if (count == null || count <= _maxSelectionCount) return;
    final capped = _maxSelectionCount.toString();
    _selectionCountController.value = TextEditingValue(
      text: capped,
      selection: TextSelection.collapsed(offset: capped.length),
    );
  }

  void _selectRandom() {
    final count = _selectionCount;
    if (count == null || widget.isBusy) return;
    final callback = widget.onSelectRandom;
    if (callback != null) {
      callback(count);
    } else {
      widget.onSelectMode?.call(CatalogSelectionMode.random, count);
    }
  }

  void _selectMode(CatalogSelectionMode mode) {
    final count = _selectionCount;
    if (count == null || widget.isBusy) return;
    if (mode == CatalogSelectionMode.random) {
      final random = widget.onSelectRandom;
      if (random != null) {
        random(count);
        return;
      }
    }
    widget.onSelectMode?.call(mode, count);
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final hasSelection = widget.selectedCount > 0;
    final canUseSelection = hasSelection && !widget.isBusy;
    final count = _selectionCount;
    final countFieldEnabled =
        !widget.isBusy && (_maxSelectionCount > 0 || hasSelection);
    final hasCountAction =
        widget.onSelectRandom != null || widget.onSelectMode != null;
    final canSelectCount =
        !widget.isBusy &&
        hasCountAction &&
        count != null &&
        (count == 0 ? hasSelection : _maxSelectionCount > 0);
    final canToggleShowSelectedOnly =
        !widget.isBusy &&
        (hasSelection || widget.showSelectedOnly) &&
        widget.onToggleShowSelectedOnly != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToolbarGroupBox(
                key: const ValueKey('bulk-selection-group'),
                label: 'Selection',
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
                        label: 'Selection count',
                        controller: _selectionCountController,
                        enabled: countFieldEnabled,
                        builder: (focusNode) => MacosTextField(
                          key: const ValueKey('bulk-random-count-field'),
                          controller: _selectionCountController,
                          focusNode: focusNode,
                          enabled: countFieldEnabled,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          placeholder: '1',
                          onChanged: _handleSelectionCountChanged,
                          onSubmitted: (_) => _selectRandom(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PushButton(
                      key: const ValueKey('bulk-random-button'),
                      controlSize: ControlSize.regular,
                      secondary: true,
                      onPressed: canSelectCount ? _selectRandom : null,
                      child: const Text('Random'),
                    ),
                    const SizedBox(width: 6),
                    _selectionButton(
                      key: const ValueKey('bulk-size-largest-button'),
                      label: 'Size Largest',
                      mode: CatalogSelectionMode.sizeLargest,
                      enabled: canSelectCount && widget.onSelectMode != null,
                    ),
                    const SizedBox(width: 6),
                    _selectionButton(
                      key: const ValueKey('bulk-size-smallest-button'),
                      label: 'Size Smallest',
                      mode: CatalogSelectionMode.sizeSmallest,
                      enabled: canSelectCount && widget.onSelectMode != null,
                    ),
                    const SizedBox(width: 6),
                    _selectionButton(
                      key: const ValueKey('bulk-duration-shortest-button'),
                      label: 'Duration Shortest',
                      mode: CatalogSelectionMode.durationShortest,
                      enabled: canSelectCount && widget.onSelectMode != null,
                    ),
                    const SizedBox(width: 6),
                    _selectionButton(
                      key: const ValueKey('bulk-duration-longest-button'),
                      label: 'Duration Longest',
                      mode: CatalogSelectionMode.durationLongest,
                      enabled: canSelectCount && widget.onSelectMode != null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${widget.selectedCount} Selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildSelectedGroup(
                  canUseSelection: canUseSelection,
                  canToggleShowSelectedOnly: canToggleShowSelectedOnly,
                  hasSelection: hasSelection,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _selectionButton({
    required Key key,
    required String label,
    required CatalogSelectionMode mode,
    required bool enabled,
  }) {
    return PushButton(
      key: key,
      controlSize: ControlSize.regular,
      secondary: true,
      onPressed: enabled ? () => _selectMode(mode) : null,
      child: Text(label),
    );
  }

  Widget _buildSelectedGroup({
    required bool canUseSelection,
    required bool canToggleShowSelectedOnly,
    required bool hasSelection,
  }) {
    return _ToolbarGroupBox(
      key: const ValueKey('bulk-selected-group'),
      label: 'Selected',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PushButton(
            key: const ValueKey('bulk-show-selected-button'),
            controlSize: ControlSize.regular,
            secondary: !widget.showSelectedOnly,
            onPressed: canToggleShowSelectedOnly
                ? widget.onToggleShowSelectedOnly
                : null,
            child: _ToolbarButtonLabel(
              icon: Icon(
                widget.showSelectedOnly
                    ? CupertinoIcons.eye
                    : CupertinoIcons.eye_slash,
                size: 16,
              ),
              label: widget.showSelectedOnly ? 'Show All' : 'Show Selected',
            ),
          ),
          const SizedBox(width: 8),
          PushButton(
            controlSize: ControlSize.regular,
            secondary: true,
            onPressed: canUseSelection ? widget.onClearSelection : null,
            child: const _ToolbarButtonLabel(
              icon: Icon(CupertinoIcons.clear_circled, size: 16),
              label: 'Clear',
            ),
          ),
          const SizedBox(width: 8),
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
          if (widget.onCopyYoutubeUrls != null) ...[
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
        ],
      ),
    );
  }
}

class _ToolbarGroupBox extends StatelessWidget {
  const _ToolbarGroupBox({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      container: true,
      label: label,
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
                    child: Text(label, style: theme.typography.caption2),
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
