import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../logic/settings_provider.dart';

abstract final class CatalogLayoutMetrics {
  static const gridPadding = 16.0;
  static const gridMainAxisExtent = 280.0;
  static const gridMainAxisSpacing = 20.0;
  static const gridMaxCrossAxisExtent = 350.0;
  static const gridCrossAxisSpacing = 20.0;
  static const listPadding = 8.0;
  static const listItemExtent = 80.0;
  static const thumbnailWidth = 112.0;
  static const thumbnailHeight = 63.0;
}

final class CatalogScrollAnchor {
  const CatalogScrollAnchor._({
    required this.videoId,
    required this.index,
    required this.localOffset,
  });

  factory CatalogScrollAnchor.capture({
    required CatalogPresentation presentation,
    required List<int> orderedVideoIds,
    required double scrollOffset,
    required double viewportWidth,
  }) {
    assert(orderedVideoIds.isNotEmpty);
    final index = _indexAtOffset(
      presentation: presentation,
      itemCount: orderedVideoIds.length,
      scrollOffset: scrollOffset,
      viewportWidth: viewportWidth,
    );
    final leadingOffset = _leadingOffset(
      presentation: presentation,
      index: index,
      viewportWidth: viewportWidth,
    );
    return CatalogScrollAnchor._(
      videoId: orderedVideoIds[index],
      index: index,
      localOffset: scrollOffset - leadingOffset,
    );
  }

  final int videoId;
  final int index;
  final double localOffset;

  double offsetFor({
    required CatalogPresentation presentation,
    required List<int> orderedVideoIds,
    required double viewportWidth,
  }) {
    if (orderedVideoIds.isEmpty) return 0;
    final currentIndex = orderedVideoIds.indexOf(videoId);
    final targetIndex = currentIndex >= 0
        ? currentIndex
        : index.clamp(0, orderedVideoIds.length - 1);
    final maxVisibleLocalOffset = presentation == CatalogPresentation.list
        ? CatalogLayoutMetrics.listItemExtent - 1
        : CatalogLayoutMetrics.gridMainAxisExtent - 1;
    final visibleLocalOffset = math.min(localOffset, maxVisibleLocalOffset);
    return math.max(
      0,
      _leadingOffset(
            presentation: presentation,
            index: targetIndex,
            viewportWidth: viewportWidth,
          ) +
          visibleLocalOffset,
    );
  }

  static int _indexAtOffset({
    required CatalogPresentation presentation,
    required int itemCount,
    required double scrollOffset,
    required double viewportWidth,
  }) {
    if (presentation == CatalogPresentation.list) {
      return ((scrollOffset - CatalogLayoutMetrics.listPadding) /
              CatalogLayoutMetrics.listItemExtent)
          .floor()
          .clamp(0, itemCount - 1);
    }

    final stride =
        CatalogLayoutMetrics.gridMainAxisExtent +
        CatalogLayoutMetrics.gridMainAxisSpacing;
    var row = ((scrollOffset - CatalogLayoutMetrics.gridPadding) / stride)
        .floor()
        .clamp(0, itemCount);
    final rowOffset =
        scrollOffset - (CatalogLayoutMetrics.gridPadding + row * stride);
    if (rowOffset >= CatalogLayoutMetrics.gridMainAxisExtent) row++;
    return (row * _gridColumnCount(viewportWidth)).clamp(0, itemCount - 1);
  }

  static double _leadingOffset({
    required CatalogPresentation presentation,
    required int index,
    required double viewportWidth,
  }) {
    if (presentation == CatalogPresentation.list) {
      return CatalogLayoutMetrics.listPadding +
          index * CatalogLayoutMetrics.listItemExtent;
    }
    final row = index ~/ _gridColumnCount(viewportWidth);
    return CatalogLayoutMetrics.gridPadding +
        row *
            (CatalogLayoutMetrics.gridMainAxisExtent +
                CatalogLayoutMetrics.gridMainAxisSpacing);
  }

  static int _gridColumnCount(double viewportWidth) {
    final crossAxisExtent = math.max(
      0,
      viewportWidth - CatalogLayoutMetrics.gridPadding * 2,
    );
    return math.max(
      1,
      (crossAxisExtent /
              (CatalogLayoutMetrics.gridMaxCrossAxisExtent +
                  CatalogLayoutMetrics.gridCrossAxisSpacing))
          .ceil(),
    );
  }
}

class CatalogPresentationControl extends StatelessWidget {
  const CatalogPresentationControl({
    super.key,
    required this.presentation,
    required this.onChanged,
  });

  final CatalogPresentation presentation;
  final ValueChanged<CatalogPresentation> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PresentationButton(
            key: const ValueKey('catalog-presentation-grid'),
            label: 'Grid view',
            icon: CupertinoIcons.square_grid_2x2,
            selected: presentation == CatalogPresentation.grid,
            onPressed: () => onChanged(CatalogPresentation.grid),
          ),
          _PresentationButton(
            key: const ValueKey('catalog-presentation-list'),
            label: 'List view',
            icon: CupertinoIcons.list_bullet,
            selected: presentation == CatalogPresentation.list,
            onPressed: () => onChanged(CatalogPresentation.list),
          ),
        ],
      ),
    );
  }
}

class _PresentationButton extends StatefulWidget {
  const _PresentationButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_PresentationButton> createState() => _PresentationButtonState();
}

class _PresentationButtonState extends State<_PresentationButton> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.selected,
      enabled: true,
      focusable: true,
      focused: _focusNode.hasFocus,
      onFocus: _focusNode.requestFocus,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: MacosTooltip(
        message: widget.label,
        child: FocusableActionDetector(
          focusNode: _focusNode,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.selected
                  ? theme.primaryColor.withValues(alpha: 0.18)
                  : null,
              border: _focused
                  ? Border.all(color: theme.primaryColor, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: MacosIconButton(
              padding: const EdgeInsets.all(6),
              icon: MacosIcon(widget.icon, size: 15),
              onPressed: widget.onPressed,
              shape: BoxShape.rectangle,
            ),
          ),
        ),
      ),
    );
  }
}
