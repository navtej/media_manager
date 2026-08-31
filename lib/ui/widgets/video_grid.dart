import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
// import 'package:url_launcher/url_launcher.dart'; // Unused
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:path/path.dart' as p;
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../logic/catalog_controller.dart';
import '../../logic/library_name.dart';
import '../../logic/maintenance_controller.dart';
import '../../logic/playback_controller.dart';
import '../../logic/settings_provider.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_summary_controller.dart';
import '../../logic/video_summary_models.dart';
import '../../logic/video_selection_controller.dart';
import '../../services/library_access_service.dart';
import '../movie_manager_visual_system.dart';
import 'catalog_presentation.dart';
import 'macos_preference_checkbox.dart';

class CatalogScrollView extends ConsumerWidget {
  const CatalogScrollView({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0 ||
            notification is! ScrollUpdateNotification ||
            (notification.scrollDelta ?? 0) <= 0) {
          return false;
        }
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 500) {
          ref.read(catalogPaginationProvider.notifier).loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        controller: scrollController,
        slivers: const [
          SliverVideoGrid(),
          CatalogPaginationTail(),
          SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }
}

class CatalogPaginationTail extends ConsumerWidget {
  const CatalogPaginationTail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presentationAsync = ref.watch(catalogPaginationProvider);
    if (presentationAsync is! AsyncData<CatalogPaginationState>) {
      return const SliverToBoxAdapter();
    }
    final presentation = presentationAsync.value;

    if (presentation.isAppending) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 48,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 16, height: 16, child: ProgressCircle()),
                SizedBox(width: 8),
                Text('Loading more Videos…'),
              ],
            ),
          ),
        ),
      );
    }

    if (presentation.appendError != null) {
      return SliverToBoxAdapter(
        child: SizedBox(
          height: 48,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Couldn’t load more Videos.'),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: () =>
                      ref.read(catalogPaginationProvider.notifier).loadMore(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SliverToBoxAdapter();
  }
}

class SliverVideoGrid extends ConsumerWidget {
  const SliverVideoGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(filteredVideosProvider);
    final presentation = ref.watch(catalogViewPresentationProvider);

    return videosAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: SizedBox(
          height: 180,
          child: MovieManagerStateMessage(
            indicator: ProgressCircle(),
            title: 'Loading Videos',
            compact: true,
          ),
        ),
      ),
      error: (err, stack) => SliverToBoxAdapter(
        child: SizedBox(
          height: 220,
          child: MovieManagerStateMessage(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: 'Couldn’t Load Videos',
            message: err.toString(),
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(filteredVideosProvider),
          ),
        ),
      ),
      data: (videos) {
        if (videos.isEmpty) {
          return const SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: MovieManagerStateMessage(
                icon: CupertinoIcons.film,
                title: 'No Videos Found',
                message: 'Try another search or add a library folder.',
              ),
            ),
          );
        }

        final visibleVideoIds = videos
            .map((video) => video.id)
            .toList(growable: false);
        if (presentation == CatalogPresentation.list) {
          return SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: CatalogLayoutMetrics.listPadding,
              vertical: CatalogLayoutMetrics.listPadding,
            ),
            sliver: SliverFixedExtentList(
              itemExtent: CatalogLayoutMetrics.listItemExtent,
              delegate: SliverChildBuilderDelegate(
                (context, index) => VideoGridItem(
                  key: ValueKey(videos[index].id),
                  video: videos[index],
                  visibleVideoIds: visibleVideoIds,
                  presentation: CatalogPresentation.list,
                ),
                childCount: videos.length,
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.all(CatalogLayoutMetrics.gridPadding),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: CatalogLayoutMetrics.gridMaxCrossAxisExtent,
              mainAxisSpacing: CatalogLayoutMetrics.gridMainAxisSpacing,
              crossAxisSpacing: CatalogLayoutMetrics.gridCrossAxisSpacing,
              mainAxisExtent: CatalogLayoutMetrics.gridMainAxisExtent,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => VideoGridItem(
                key: ValueKey(videos[index].id),
                video: videos[index],
                visibleVideoIds: visibleVideoIds,
              ),
              childCount: videos.length,
            ),
          ),
        );
      },
    );
  }
}

class VideoGridItem extends StatefulWidget {
  final Video video;
  final List<int> visibleVideoIds;
  final CatalogPresentation presentation;
  const VideoGridItem({
    super.key,
    required this.video,
    this.visibleVideoIds = const <int>[],
    this.presentation = CatalogPresentation.grid,
  });

  @override
  State<VideoGridItem> createState() => _VideoGridItemState();
}

class _VideoGridItemState extends State<VideoGridItem> {
  bool _isHovering = false;
  bool _isThumbnailHovering = false;
  bool _isFocused = false;
  bool _isPressed = false;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Video card');
  final TextEditingController _tagController = TextEditingController();

  @override
  void dispose() {
    _focusNode.dispose();
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final video = widget.video;
        final theme = MacosTheme.of(context);
        final selection = ref.watch(videoSelectionControllerProvider);
        final isSelected = selection.isSelected(video.id);
        final selectionController = ref.read(
          videoSelectionControllerProvider.notifier,
        );

        if (widget.presentation == CatalogPresentation.list) {
          return _buildCompactRow(
            context,
            ref,
            video,
            theme,
            isSelected,
            selectionController,
          );
        }

        final highlighted = isSelected || _isHovering || _isFocused;
        return Semantics(
          container: true,
          explicitChildNodes: true,
          button: true,
          selected: isSelected,
          focusable: true,
          focused: _focusNode.hasFocus,
          label: video.title,
          value: _videoSemanticValue(video),
          onFocus: _focusNode.requestFocus,
          onTap: () => _selectWithKeyboardIntent(selectionController),
          child: FocusableActionDetector(
            focusNode: _focusNode,
            onShowHoverHighlight: (value) =>
                setState(() => _isHovering = value),
            onShowFocusHighlight: (value) => setState(() => _isFocused = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _selectWithKeyboardIntent(selectionController);
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: () => _selectWithKeyboardIntent(selectionController),
              child: Opacity(
                opacity: video.isOffline ? 0.5 : 1.0,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.canvasColor,
                    borderRadius: BorderRadius.circular(
                      MovieManagerRadii.panel,
                    ),
                    border: Border.all(
                      color: isSelected || _isFocused
                          ? theme.primaryColor
                          : theme.dividerColor,
                      width: _isFocused ? 2 : 1,
                    ),
                    boxShadow: highlighted
                        ? [
                            BoxShadow(
                              color: theme.primaryColor.withValues(alpha: 0.14),
                              blurRadius: 4,
                              spreadRadius: _isFocused ? 1 : 0,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Thumbnail area
                      Expanded(
                        flex: 4,
                        child: MouseRegion(
                          onEnter: (_) =>
                              setState(() => _isThumbnailHovering = true),
                          onExit: (_) =>
                              setState(() => _isThumbnailHovering = false),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(MovieManagerRadii.panel),
                                ),
                                child: ExcludeSemantics(
                                  child: _VideoThumbnailContent(
                                    video: video,
                                    placeholderIconSize: 40,
                                  ),
                                ),
                              ),
                              // Hover Details Overlay
                              if (_isThumbnailHovering)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: MacosColors.black.withValues(
                                        alpha: 0.85,
                                      ),
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(
                                          MovieManagerRadii.panel,
                                        ),
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(8),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        _getMetaDescription(video.metadataJson),
                                        style: const TextStyle(
                                          color: MacosColors.white,
                                          fontSize: 11,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: _VideoSelectionCheckbox(
                                  key: ValueKey('video-selection-${video.id}'),
                                  selected: isSelected,
                                  lightBackground: _isThumbnailHovering,
                                  onPressed: () =>
                                      selectionController.toggle(video.id),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Content area
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(
                                child: _VideoTitle(video: video),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: _buildCompactActions(
                                        ref,
                                        includeTagAction: false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ExcludeSemantics(
                                    child: Text(
                                      _formatDuration(video.duration),
                                      style: theme.typography.caption1.copyWith(
                                        color: theme.typography.caption1.color
                                            ?.withValues(alpha: 0.5),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Folder Path (above tags)
                              _FolderPathWidget(video: video),
                              // Tags Section
                              Expanded(child: _VideoTagList(videoId: video.id)),
                              const SizedBox(height: 4),
                              // Add Tag Input
                              _TagAutocompleteInput(video: video),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactRow(
    BuildContext context,
    WidgetRef ref,
    Video video,
    MacosThemeData theme,
    bool isSelected,
    VideoSelectionController selectionController,
  ) {
    final highlighted = isSelected || _isHovering || _isFocused || _isPressed;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      selected: isSelected,
      focusable: true,
      focused: _focusNode.hasFocus,
      label: video.title,
      value: _videoSemanticValue(video),
      onFocus: _focusNode.requestFocus,
      onTap: () => _selectWithKeyboardIntent(selectionController),
      child: FocusableActionDetector(
        focusNode: _focusNode,
        onShowHoverHighlight: (value) => setState(() => _isHovering = value),
        onShowFocusHighlight: (value) => setState(() => _isFocused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _selectWithKeyboardIntent(selectionController);
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapCancel: () => setState(() => _isPressed = false),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTap: () => _selectWithKeyboardIntent(selectionController),
          child: Opacity(
            opacity: video.isOffline ? 0.62 : 1,
            child: Container(
              height: CatalogLayoutMetrics.listItemExtent,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: highlighted
                    ? theme.primaryColor.withValues(
                        alpha: isSelected ? 0.16 : 0.08,
                      )
                    : theme.canvasColor,
                border: Border.all(
                  color: _isFocused || isSelected
                      ? theme.primaryColor
                      : theme.dividerColor,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(7),
                boxShadow: _isFocused
                    ? [BoxShadow(color: theme.primaryColor, spreadRadius: 1)]
                    : null,
              ),
              child: Row(
                children: [
                  _VideoSelectionCheckbox(
                    key: ValueKey('video-selection-${video.id}'),
                    selected: isSelected,
                    onPressed: () => selectionController.toggle(video.id),
                  ),
                  const SizedBox(width: 8),
                  ClipRRect(
                    key: ValueKey('video-thumbnail-${video.id}'),
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      width: CatalogLayoutMetrics.thumbnailWidth,
                      height: CatalogLayoutMetrics.thumbnailHeight,
                      child: ExcludeSemantics(
                        child: _VideoThumbnailContent(
                          video: video,
                          placeholderIconSize: 28,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(child: _VideoTitle(video: video)),
                        _FolderPathWidget(video: video, compact: true),
                        Expanded(
                          child: _CompactVideoTagLine(videoId: video.id),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 68,
                    child: ExcludeSemantics(
                      child: MacosTooltip(
                        message:
                            '${_formatDuration(video.duration)} · ${LibraryStats.formatSize(video.size)}',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatDuration(video.duration),
                              maxLines: 1,
                              style: theme.typography.caption1,
                            ),
                            Text(
                              LibraryStats.formatSize(video.size),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.typography.caption1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 54,
                    child: video.isOffline
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.exclamationmark_circle,
                                size: 15,
                              ),
                              Text('Offline', style: TextStyle(fontSize: 10)),
                            ],
                          )
                        : null,
                  ),
                  _buildCompactActions(ref),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _selectWithKeyboardIntent(VideoSelectionController selectionController) {
    final keyboard = HardwareKeyboard.instance;
    selectionController.selectWithIntent(
      videoId: widget.video.id,
      orderedVisibleVideoIds: widget.visibleVideoIds,
      isRangeSelection: keyboard.isShiftPressed,
      isToggleSelection: keyboard.isMetaPressed || keyboard.isControlPressed,
    );
  }

  String _videoSemanticValue(Video video) {
    return [
      _formatDuration(video.duration),
      LibraryStats.formatSize(video.size),
      if (video.isOffline) 'Offline',
      if (video.isFavorite) 'Favorite',
    ].join(', ');
  }

  Widget _buildCompactActions(WidgetRef ref, {bool includeTagAction = true}) {
    final hasFreshSummary =
        ref
            .watch(videoSummaryStateProvider(widget.video))
            .asData
            ?.value
            .hasFreshSummary ==
        true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MovieManagerIconButton(
          label: 'Video information',
          icon: CupertinoIcons.info,
          onPressed: () => _showInfo(context, widget.video),
        ),
        MovieManagerIconButton(
          key: ValueKey('video-play-${widget.video.id}'),
          label: 'Play',
          icon: CupertinoIcons.play_fill,
          onPressed: () => _playVideo(ref, widget.video),
        ),
        MovieManagerIconButton(
          key: ValueKey('video-favorite-${widget.video.id}'),
          label: widget.video.isFavorite ? 'Unfavorite' : 'Favorite',
          icon: widget.video.isFavorite
              ? CupertinoIcons.heart_fill
              : CupertinoIcons.heart,
          color: widget.video.isFavorite
              ? MovieManagerVisuals.errorColor(context)
              : null,
          onPressed: () => _toggleFavorite(ref),
        ),
        if (includeTagAction)
          MovieManagerIconButton(
            key: ValueKey('video-edit-tags-${widget.video.id}'),
            label: 'Add or edit tags',
            icon: CupertinoIcons.tag,
            onPressed: () => _showTagEditor(ref),
          ),
        MovieManagerIconButton(
          label: 'Video summary',
          icon: CupertinoIcons.doc_text,
          color: hasFreshSummary ? MacosColors.systemGreenColor : null,
          onPressed: () => _showSummaryDialog(context, ref, widget.video),
        ),
        MovieManagerIconButton(
          key: ValueKey('video-delete-${widget.video.id}'),
          label: 'Delete',
          icon: CupertinoIcons.trash,
          color: MovieManagerVisuals.errorColor(context),
          onPressed: () => _confirmDelete(ref),
        ),
        MergeSemantics(
          child: Semantics(
            label: 'More actions',
            button: true,
            child: MacosTooltip(
              message: 'More actions',
              child: MacosPulldownButton(
                key: ValueKey('video-more-${widget.video.id}'),
                icon: CupertinoIcons.ellipsis_circle,
                menuAlignment: PulldownMenuAlignment.right,
                items: [
                  MacosPulldownMenuItem(
                    title: const Text('Reveal in Finder'),
                    onTap: () => _revealVideo(ref, widget.video),
                  ),
                  MacosPulldownMenuItem(
                    title: const Text('Clear Tags'),
                    onTap: () => _clearTags(ref),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showTagEditor(WidgetRef ref) {
    showMacosAlertDialog<void>(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.tag),
        title: Text('Tags: ${widget.video.title}'),
        message: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 72,
                child: _VideoTagList(videoId: widget.video.id),
              ),
              _TagAutocompleteInput(video: widget.video),
            ],
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(WidgetRef ref) {
    return ref
        .read(videosDaoProvider)
        .toggleFavorite(widget.video.id, widget.video.isFavorite);
  }

  Future<void> _clearTags(WidgetRef ref) {
    return ref.read(tagsDaoProvider).deleteAllTagsForVideo(widget.video.id);
  }

  // Removed _buildTagInput and replaced with _TagAutocompleteInput class below

  Future<void> _playVideo(WidgetRef ref, Video video) async {
    final opened = await _runVideoAccessAction(
      () => ref.read(playbackControllerProvider).play(video),
      errorTitle: 'Cannot Play Video',
    );
    if (mounted && opened == false) {
      _showVideoAccessError(libraryAccessRepairMessage);
    }
  }

  Future<void> _revealVideo(WidgetRef ref, Video video) async {
    await _runVideoAccessAction(
      () => ref.read(playbackControllerProvider).revealInFinder(video),
      errorTitle: 'Cannot Show Video in Finder',
    );
  }

  Future<T?> _runVideoAccessAction<T>(
    Future<T> Function() action, {
    required String errorTitle,
  }) async {
    try {
      return await action();
    } on LibraryAccessNeedsRepairException catch (error) {
      if (mounted) {
        _showVideoAccessError(error.message, title: errorTitle);
      }
    } on StateError catch (error) {
      if (mounted) {
        _showVideoAccessError(error.message, title: errorTitle);
      }
    }
    return null;
  }

  void _showVideoAccessError(
    String message, {
    String title = 'Cannot Play Video',
  }) {
    showMacosAlertDialog(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
        title: Text(title),
        message: Text(message),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('OK'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  void _confirmDelete(WidgetRef ref) {
    final videoId = widget.video.id;
    final videoTitle = widget.video.title;
    final maintenanceController = ref.read(
      maintenanceControllerProvider.notifier,
    );

    showMacosAlertDialog(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.film),
        title: const Text('Delete Video?'),
        message: Text(
          'This will permanently delete $videoTitle from your disk.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('Delete'),
          onPressed: () async {
            final statusMessage = ref.read(statusMessageProvider.notifier);
            Navigator.of(dialogContext).pop();
            final result = await maintenanceController.deleteVideo(videoId);
            statusMessage.set(result.userMessage);
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  String _getMetaDescription(String json) {
    try {
      final data = jsonDecode(json);
      final raw = data['raw'] ?? {};
      final format = raw['format'] ?? {};
      final tags = format['tags'] ?? {};

      final description = tags['description'];
      if (description != null && description.toString().isNotEmpty) {
        return description.toString();
      }

      final streams = raw['streams'] as List?;
      if (streams != null && streams.isNotEmpty) {
        final v = streams.firstWhere(
          (s) => s['codec_type'] == 'video',
          orElse: () => null,
        );
        if (v != null) {
          return "Codec: ${v['codec_name']}\nRes: ${v['width']}x${v['height']}\nFrame: ${v['avg_frame_rate']}\nBitrate: ${data['bitrate']} bps";
        }
      }
    } catch (_) {}
    return "No description available.";
  }

  void _showInfo(BuildContext context, Video video) {
    final drive = _getDriveName(video.absolutePath);
    final sizeStr = LibraryStats.formatSize(video.size);

    showMacosAlertDialog(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.info),
        title: Semantics(
          container: true,
          header: true,
          child: const Text('Video Information'),
        ),
        message: SelectableText(
          'Drive: $drive\nSize: $sizeStr\n\nFull Path: ${video.absolutePath}',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('OK'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  void _showSummaryDialog(BuildContext context, WidgetRef ref, Video video) {
    ref.invalidate(videoSummaryStateProvider(video));
    ref.invalidate(videoSummarySubtitleAvailabilityProvider(video));
    bool? useVttForThisSummary;
    showMacosAlertDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => Consumer(
          builder: (context, ref, _) {
            final summaryState = ref.watch(videoSummaryStateProvider(video));
            final subtitleAvailability = ref.watch(
              videoSummarySubtitleAvailabilityProvider(video),
            );
            final modelValidation = ref.watch(summaryModelValidationProvider);

            final state = summaryState.asData?.value;
            final taskState = state?.task;
            final summary = state?.summary;
            final configuredModel = state?.configuredTranscriptModel ?? '';
            final summaryPreferVttSubtitles = state?.preferVttSubtitles;

            final isStale = state?.storedStatus == VideoSummaryStatus.stale;
            final isMalformed =
                state?.storedStatus == VideoSummaryStatus.malformed;
            final actionLabel = state?.hasStoredSummary == true
                ? 'Regenerate'
                : 'Generate';
            final isGenerating = state?.isGenerating == true;
            final errorText = state?.status == VideoSummaryStatus.failed
                ? state?.error.toString()
                : null;
            final vttAvailable =
                subtitleAvailability.asData?.value.isFound == true;
            useVttForThisSummary ??= summaryPreferVttSubtitles;
            final effectiveUseVtt =
                vttAvailable && (useVttForThisSummary ?? false);

            return MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.doc_text),
              title: Text(
                'Summary: ${video.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              message: SizedBox(
                width: 440,
                height: 300,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    modelValidation.when(
                      data: (result) => Text(
                        'Model: ${result.status}'
                        '${configuredModel.isNotEmpty ? ' ($configuredModel)' : ''}',
                        style: MacosTheme.of(context).typography.caption1,
                      ),
                      loading: () => const Text('Model: Checking...'),
                      error: (error, _) => Text('Model: $error'),
                    ),
                    const SizedBox(height: 8),
                    subtitleAvailability.when(
                      data: (availability) {
                        if (!availability.isFound) {
                          return const SizedBox.shrink();
                        }

                        return _SummarySubtitleSourceOption(
                          fileName: availability.fileName,
                          useVtt: effectiveUseVtt,
                          onChanged: isGenerating
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    useVttForThisSummary = value;
                                  });
                                },
                        );
                      },
                      loading: () =>
                          const Text('Subtitles: checking for .vtt file...'),
                      error: (error, _) {
                        if (error is LibraryAccessNeedsRepairException) {
                          return Text(
                            error.message,
                            style: const TextStyle(
                              color: MacosColors.systemRedColor,
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    if (vttAvailable) const SizedBox(height: 8),
                    if (isGenerating) ...[
                      const ProgressCircle(),
                      const SizedBox(height: 8),
                      Text(taskState?.statusText ?? 'Generating summary...'),
                      const SizedBox(height: 12),
                    ],
                    if (isStale) ...[
                      const Text(
                        'Stored summary is stale and should be regenerated.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (isMalformed) ...[
                      const Text(
                        'Stored summary is malformed and should be regenerated.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (errorText != null) ...[
                      SummaryErrorPanel(errorText: errorText),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        child: summary == null
                            ? const Text(
                                'No summary has been generated for this video.',
                              )
                            : VideoSummaryContent(summary: summary),
                      ),
                    ),
                  ],
                ),
              ),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                onPressed: isGenerating
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        Future<void>.microtask(() {
                          ref
                              .read(videoSummaryTasksProvider.notifier)
                              .generate(
                                video,
                                forceRefresh: state?.hasStoredSummary == true,
                                preferVttSubtitlesOverride: vttAvailable
                                    ? effectiveUseVtt
                                    : null,
                              );
                        });
                      },
                child: Text(isGenerating ? 'Working...' : actionLabel),
              ),
              secondaryButton: PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                child: const Text('Close'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            );
          },
        ),
      ),
    );
  }

  String _getDriveName(String path) {
    if (path.startsWith('/Volumes/')) {
      final parts = path.split('/');
      if (parts.length > 2) return parts[2];
    }
    return 'System Drive';
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _VideoThumbnailContent extends StatelessWidget {
  const _VideoThumbnailContent({
    required this.video,
    required this.placeholderIconSize,
  });

  final Video video;
  final double placeholderIconSize;

  @override
  Widget build(BuildContext context) {
    if (video.thumbnailPath != null) {
      return Image.file(File(video.thumbnailPath!), fit: BoxFit.cover);
    }
    if (video.thumbnailBlob != null) {
      return Image.memory(video.thumbnailBlob!, fit: BoxFit.cover);
    }
    return Container(
      color: MacosColors.black,
      child: Icon(
        CupertinoIcons.play_circle,
        color: MacosColors.white,
        size: placeholderIconSize,
      ),
    );
  }
}

class _VideoTitle extends StatelessWidget {
  const _VideoTitle({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    return MacosTooltip(
      message: video.title,
      child: Text(
        video.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: MacosTheme.of(
          context,
        ).typography.body.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _VideoSelectionCheckbox extends StatelessWidget {
  const _VideoSelectionCheckbox({
    super.key,
    required this.selected,
    this.lightBackground = false,
    required this.onPressed,
  });

  final bool selected;
  final bool lightBackground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MacosPreferenceCheckbox(
      value: selected,
      semanticLabel: selected ? 'Deselect video' : 'Select video',
      emphasized: true,
      lightBackground: lightBackground,
      onChanged: (_) => onPressed(),
    );
  }
}

class VideoSummaryContent extends StatelessWidget {
  const VideoSummaryContent({super.key, required this.summary});

  final StructuredVideoSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary.synopsis, style: MacosTheme.of(context).typography.body),
        const SizedBox(height: 12),
        if (summary.themes.isNotEmpty)
          _ThemedSummarySections(themes: summary.themes)
        else
          _LegacySummaryHighlights(highlights: summary.highlights),
        const SizedBox(height: 12),
        Text('Keywords', style: MacosTheme.of(context).typography.subheadline),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: summary.keywords
              .map(
                (keyword) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: MacosTheme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(keyword),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ThemedSummarySections extends StatelessWidget {
  const _ThemedSummarySections({required this.themes});

  final List<VideoSummaryTheme> themes;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Themes', style: theme.typography.subheadline),
        const SizedBox(height: 6),
        ...themes.map(
          (section) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: theme.typography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...section.bullets.map(
                  (bullet) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $bullet'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegacySummaryHighlights extends StatelessWidget {
  const _LegacySummaryHighlights({required this.highlights});

  final List<String> highlights;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Highlights',
          style: MacosTheme.of(context).typography.subheadline,
        ),
        const SizedBox(height: 4),
        ...highlights.map(
          (highlight) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $highlight'),
          ),
        ),
      ],
    );
  }
}

class _SummarySubtitleSourceOption extends StatelessWidget {
  const _SummarySubtitleSourceOption({
    required this.fileName,
    required this.useVtt,
    required this.onChanged,
  });

  final String fileName;
  final bool useVtt;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final status = useVtt
        ? '$fileName found. VTT transcript will be used.'
        : '$fileName found. Audio transcription will be used.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MacosPreferenceCheckbox(
          value: useVtt,
          semanticLabel: 'Use VTT transcript',
          onChanged: onChanged,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MacosTheme.of(context).typography.caption1,
          ),
        ),
      ],
    );
  }
}

class SummaryErrorPanel extends StatelessWidget {
  const SummaryErrorPanel({super.key, required this.errorText});

  final String errorText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MacosColors.appleRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MacosColors.appleRed.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: MacosColors.appleRed,
              size: 16,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Summary generation failed.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: MacosColors.appleRed),
              ),
            ),
            const SizedBox(width: 8),
            PushButton(
              controlSize: ControlSize.small,
              secondary: true,
              onPressed: () => _showSummaryErrorDetails(context, errorText),
              child: const Text('View Details'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSummaryErrorDetails(BuildContext context, String errorText) {
    showMacosAlertDialog(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
        title: const Text('Summary Error Details'),
        message: SizedBox(
          width: 520,
          height: 260,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MacosTheme.of(dialogContext).canvasColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: MacosTheme.of(dialogContext).dividerColor,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(child: SelectableText(errorText)),
            ),
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: errorText));
          },
          child: const Text('Copy Error'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ),
    );
  }
}

class _VideoTagList extends ConsumerWidget {
  final int videoId;
  const _VideoTagList({required this.videoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsStream = ref.watch(tagsDaoProvider).watchTagsForVideo(videoId);

    return StreamBuilder<List<Tag>>(
      stream: tagsStream,
      builder: (context, snapshot) {
        final tags = snapshot.data ?? [];
        if (tags.isEmpty) return const SizedBox();

        return SingleChildScrollView(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tags.map((t) {
              final isSelected = ref
                  .watch(combinedSelectedTagsProvider)
                  .contains(t.tagText);
              return GestureDetector(
                onTap: () => ref
                    .read(catalogControllerProvider.notifier)
                    .togglePrimaryTag(t.tagText),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? MacosTheme.of(context).primaryColor
                        : MacosTheme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: MacosTheme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          t.tagText,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? MacosColors.white : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6), // Increased width
                      GestureDetector(
                        behavior: HitTestBehavior.opaque, // Better hit testing
                        onTap: () => ref
                            .read(tagsDaoProvider)
                            .deleteTag(videoId, t.tagText),
                        child: Padding(
                          padding: const EdgeInsets.all(
                            2.0,
                          ), // Padding around the icon for better hit area
                          child: Icon(
                            CupertinoIcons.trash,
                            size: 9, // Slightly larger
                            color: isSelected
                                ? MacosColors.white.withOpacity(0.8)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _CompactVideoTagLine extends ConsumerWidget {
  const _CompactVideoTagLine({required this.videoId});

  final int videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<Tag>>(
      stream: ref.watch(tagsDaoProvider).watchTagsForVideo(videoId),
      builder: (context, snapshot) {
        final label = (snapshot.data ?? const <Tag>[])
            .map((tag) => tag.tagText)
            .join(' · ');
        if (label.isEmpty) {
          return Text(
            'No tags',
            maxLines: 1,
            style: MacosTheme.of(context).typography.caption1,
          );
        }
        return MacosTooltip(
          message: label,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MacosTheme.of(context).typography.caption1,
          ),
        );
      },
    );
  }
}

class _FolderPathWidget extends ConsumerWidget {
  final Video video;
  final bool compact;
  const _FolderPathWidget({required this.video, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersDaoProvider).getAllFolders();

    return FutureBuilder<List<Folder>>(
      future: foldersAsync,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        final folders = snapshot.data!;
        final folder = folders.where((f) => f.id == video.folderId).firstOrNull;
        if (folder == null) return const SizedBox();

        final relativePath = _getRelativeFolderPath(
          video.absolutePath,
          folder.path,
        );
        final displayPath = compact
            ? relativePath.isEmpty
                  ? libraryDisplayName(folder)
                  : '${libraryDisplayName(folder)} / $relativePath'
            : relativePath;
        if (displayPath.isEmpty) return const SizedBox();

        return Padding(
          padding: EdgeInsets.only(bottom: compact ? 0 : 4),
          child: GestureDetector(
            onTap: () => ref
                .read(catalogControllerProvider.notifier)
                .setSearchQuery(relativePath),
            child: MacosTooltip(
              message: compact
                  ? video.absolutePath
                  : 'Click to filter by folder: $relativePath',
              child: Text(
                displayPath,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: compact ? FontWeight.normal : FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }

  String _getRelativeFolderPath(String absolutePath, String rootPath) {
    final videoDir = p.dirname(absolutePath);
    if (videoDir == rootPath || !videoDir.startsWith(rootPath)) {
      return ''; // Video is at root level
    }

    final relativePath = videoDir.substring(rootPath.length);
    // Remove leading separator and split
    final parts = relativePath.split(p.separator).where((s) => s.isNotEmpty);

    // Convert each part to Title Case
    final titleCased = parts.map((part) => _toTitleCase(part));

    return titleCased.join(' / ');
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }
}

class _TagAutocompleteInput extends ConsumerStatefulWidget {
  final Video video;
  const _TagAutocompleteInput({required this.video});

  @override
  ConsumerState<_TagAutocompleteInput> createState() =>
      _TagAutocompleteInputState();
}

class _TagAutocompleteInputState extends ConsumerState<_TagAutocompleteInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<String> _suggestions = [];
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _hideOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _hideOverlay();
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text.isEmpty) {
      _hideOverlay();
      return;
    }

    // Get the last part after comma
    final parts = text.split(',');
    final query = parts.last.trim().toLowerCase();

    if (query.isEmpty) {
      _hideOverlay();
      return;
    }

    final allTagsAsync = ref.read(visibleUniqueTagsProvider);
    final allTags = allTagsAsync.value ?? [];

    final filtered = allTags
        .where((tag) => tag.toLowerCase().contains(query))
        .take(5)
        .toList();

    if (filtered.isNotEmpty) {
      setState(() {
        _suggestions = filtered;
        _selectedIndex = -1;
      });
      _showOverlay();
    } else {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final theme = MacosTheme.of(context);
        return Positioned(
          width: 200,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 4), // Show BELOW input
            followerAnchor: Alignment.topLeft,
            targetAnchor: Alignment.bottomLeft,
            child: TapRegion(
              onTapOutside: (_) => _hideOverlay(),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.canvasColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: MacosColors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tag = entry.value;
                    final isHighlighted = index == _selectedIndex;

                    return MouseRegion(
                      onEnter: (_) => setState(() => _selectedIndex = index),
                      child: GestureDetector(
                        onTap: () => _selectTag(tag),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? theme.primaryColor.withValues(alpha: 0.1)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              color: isHighlighted ? theme.primaryColor : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectTag(String tag) {
    final text = _controller.text;
    final parts = text.split(',');
    parts.removeLast();
    parts.add(tag);

    final newText = '${parts.join(', ')}, ';
    _controller.text = newText;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newText.length),
    );

    _hideOverlay();
    _focusNode.requestFocus();
  }

  Future<void> _submitTags() async {
    final val = _controller.text;
    if (val.trim().isNotEmpty) {
      final tags = val
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet();

      for (final tag in tags) {
        await ref
            .read(tagsDaoProvider)
            .insertTag(
              TagsCompanion.insert(
                videoId: widget.video.id,
                tagText: tag,
                source: const Value('user'),
              ),
            );
      }
      _controller.clear();
      _hideOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch to keep the provider alive and ensure data is ready
    ref.watch(visibleUniqueTagsProvider);

    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        height: 24,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                if (_overlayEntry != null && _suggestions.isNotEmpty) {
                  setState(() {
                    _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
                  });
                  _overlayEntry!.markNeedsBuild();
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                if (_overlayEntry != null && _suggestions.isNotEmpty) {
                  setState(() {
                    _selectedIndex =
                        (_selectedIndex - 1 + _suggestions.length) %
                        _suggestions.length;
                  });
                  _overlayEntry!.markNeedsBuild();
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                if (_overlayEntry != null && _selectedIndex != -1) {
                  _selectTag(_suggestions[_selectedIndex]);
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (_overlayEntry != null) {
                  _hideOverlay();
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: MovieManagerLabeledField(
            label: 'Add tags for ${widget.video.title}',
            controller: _controller,
            focusNode: _focusNode,
            builder: (focusNode) => MacosTextField(
              controller: _controller,
              focusNode: focusNode,
              placeholder: 'Add tags...',
              placeholderStyle: const TextStyle(
                color: MacosColors.systemGrayColor,
              ),
              style: const TextStyle(fontSize: 11),
              onSubmitted: (_) => _submitTags(),
            ),
          ),
        ),
      ),
    );
  }
}
