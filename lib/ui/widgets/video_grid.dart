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
import '../../logic/maintenance_controller.dart';
import '../../logic/playback_controller.dart';
import '../../logic/settings_provider.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_summary_controller.dart';
import '../../logic/video_summary_models.dart';
import '../../logic/video_selection_controller.dart';
import '../../services/library_access_service.dart';
import 'package:icon_craft/icon_craft.dart';

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
          ref.read(catalogPresentationProvider.notifier).loadMore();
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
    final presentationAsync = ref.watch(catalogPresentationProvider);
    if (presentationAsync is! AsyncData<CatalogPresentationState>) {
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
                      ref.read(catalogPresentationProvider.notifier).loadMore(),
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

    return videosAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: ProgressCircle()),
        ),
      ),
      error: (err, stack) =>
          SliverToBoxAdapter(child: Center(child: Text('Error: $err'))),
      data: (videos) {
        if (videos.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(child: Text("No videos found.")),
            ),
          );
        }

        final visibleVideoIds = videos
            .map((video) => video.id)
            .toList(growable: false);
        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 350,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              mainAxisExtent: 280,
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
  const VideoGridItem({
    super.key,
    required this.video,
    this.visibleVideoIds = const <int>[],
  });

  @override
  State<VideoGridItem> createState() => _VideoGridItemState();
}

class _VideoGridItemState extends State<VideoGridItem> {
  bool _isHovering = false;
  bool _isThumbnailHovering = false;
  final TextEditingController _tagController = TextEditingController();

  @override
  void dispose() {
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

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: () {
              final keyboard = HardwareKeyboard.instance;
              selectionController.selectWithIntent(
                videoId: video.id,
                orderedVisibleVideoIds: widget.visibleVideoIds,
                isRangeSelection: keyboard.isShiftPressed,
                isToggleSelection:
                    keyboard.isMetaPressed || keyboard.isControlPressed,
              );
            },
            child: Opacity(
              opacity: video.isOffline ? 0.5 : 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.canvasColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected || _isHovering
                        ? theme.primaryColor
                        : theme.dividerColor,
                    width: isSelected || _isHovering ? 2 : 1,
                  ),
                  boxShadow: isSelected || _isHovering
                      ? [
                          BoxShadow(
                            color: theme.primaryColor.withValues(alpha: 0.2),
                            blurRadius: 10,
                            spreadRadius: 2,
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
                                top: Radius.circular(9),
                              ),
                              child: video.thumbnailPath != null
                                  ? Image.file(
                                      File(video.thumbnailPath!),
                                      fit: BoxFit.cover,
                                    )
                                  : (video.thumbnailBlob != null
                                        ? Image.memory(
                                            video.thumbnailBlob!,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            color: MacosColors.black,
                                            child: const Icon(
                                              CupertinoIcons.play_circle,
                                              color: MacosColors.white,
                                              size: 40,
                                            ),
                                          )),
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
                                      top: Radius.circular(9),
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
                            MacosTooltip(
                              message: video.title,
                              child: Text(
                                video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.typography.body.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                _buildActions(ref),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDuration(video.duration),
                                  style: theme.typography.caption1.copyWith(
                                    color: theme.typography.caption1.color
                                        ?.withValues(alpha: 0.5),
                                    fontSize: 10,
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
        );
      },
    );
  }

  Widget _buildActions(WidgetRef ref) {
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
        // Info
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(CupertinoIcons.info, size: 16),
          onPressed: () => _showInfo(context, widget.video),
        ),
        // Favorite
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: Icon(
            widget.video.isFavorite
                ? CupertinoIcons.heart_fill
                : CupertinoIcons.heart,
            color: widget.video.isFavorite ? MacosColors.appleRed : null,
            size: 16,
          ),
          onPressed: () => ref
              .read(videosDaoProvider)
              .toggleFavorite(widget.video.id, widget.video.isFavorite),
        ),
        // Play
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(CupertinoIcons.play_fill, size: 16),
          onPressed: () => _playVideo(ref, widget.video),
        ),
        // Finder
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(CupertinoIcons.folder, size: 16),
          onPressed: () => _revealVideo(ref, widget.video),
        ),
        MacosTooltip(
          message: 'Video summary',
          child: MacosIconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              CupertinoIcons.doc_text,
              color: hasFreshSummary ? MacosColors.systemGreenColor : null,
              size: 16,
            ),
            onPressed: () => _showSummaryDialog(context, ref, widget.video),
          ),
        ),
        // Delete
        MacosIconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(CupertinoIcons.trash, size: 16),
          onPressed: () => _confirmDelete(ref),
        ),
        // Clear all tags
        MacosTooltip(
          message: 'Clear all tags',
          child: MacosIconButton(
            padding: EdgeInsets.zero,
            icon: const IconCraft(
              Icon(CupertinoIcons.tag, size: 16),
              Icon(CupertinoIcons.clear_thick, size: 10),
              alignment: Alignment(1.2, -1.1),
              secondaryIconSizeFactor: 0.5,

              // decoration: const IconDecoration(
              //   border: IconBorder(
              //     width: 10.0,
              //   ),
              // ),
            ),
            onPressed: () => ref
                .read(tagsDaoProvider)
                .deleteAllTagsForVideo(widget.video.id),
          ),
        ),
      ],
    );
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
        title: const Text('Video Information'),
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

class _VideoSelectionCheckbox extends StatelessWidget {
  const _VideoSelectionCheckbox({
    super.key,
    required this.selected,
    required this.onPressed,
  });

  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      button: true,
      checked: selected,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: selected
                ? theme.primaryColor
                : MacosColors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: selected
                  ? theme.primaryColor
                  : MacosColors.white.withValues(alpha: 0.75),
              width: 1.5,
            ),
          ),
          child: selected
              ? const Icon(
                  CupertinoIcons.checkmark,
                  size: 15,
                  color: MacosColors.white,
                )
              : null,
        ),
      ),
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
        _InlineMacosCheckbox(value: useVtt, onChanged: onChanged),
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

class _InlineMacosCheckbox extends StatelessWidget {
  const _InlineMacosCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      checked: value,
      button: true,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
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

class _FolderPathWidget extends ConsumerWidget {
  final Video video;
  const _FolderPathWidget({required this.video});

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
        if (relativePath.isEmpty) return const SizedBox();

        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: GestureDetector(
            onTap: () => ref
                .read(catalogControllerProvider.notifier)
                .setSearchQuery(relativePath),
            child: MacosTooltip(
              message: 'Click to filter by folder: $relativePath',
              child: Text(
                relativePath,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
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
          child: MacosTextField(
            controller: _controller,
            focusNode: _focusNode,
            placeholder: 'Add tags...',
            placeholderStyle: const TextStyle(
              color: MacosColors.systemGrayColor,
            ),
            style: const TextStyle(fontSize: 11),
            onSubmitted: (_) => _submitTags(),
          ),
        ),
      ),
    );
  }
}
