import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../logic/catalog_controller.dart' show LibraryStats;
import '../../logic/playback_controller.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_conversion_controller.dart';
import '../../logic/video_version_models.dart';
import '../../services/library_access_service.dart';
import '../../services/video_version_service.dart';
import '../movie_manager_visual_system.dart';
import 'macos_preference_checkbox.dart';
import 'video_conversion_dialogs.dart';
import 'video_move_dialog.dart' show WideDialogFrame;

String videoDriveName(String path) {
  if (path.startsWith('/Volumes/')) {
    final parts = path.split('/');
    if (parts.length > 2) return parts[2];
  }
  return 'System Drive';
}

String _codecLabel(String codec) {
  return switch (codec) {
    'h264' => 'H.264',
    'hevc' => 'HEVC',
    'mpeg4' => 'MPEG-4',
    'mpeg2video' => 'MPEG-2',
    _ => codec.toUpperCase(),
  };
}

/// Video details plus every version of the video, with actions to play,
/// reveal, convert, choose the version used for playback, and delete
/// versions.
Future<void> showVideoInfoDialog(BuildContext context, {required Video video}) {
  return showMacosAlertDialog<void>(
    context: context,
    builder: (_) => VideoInfoDialog(video: video),
  );
}

class VideoInfoDialog extends ConsumerStatefulWidget {
  const VideoInfoDialog({super.key, required this.video});

  final Video video;

  @override
  ConsumerState<VideoInfoDialog> createState() => _VideoInfoDialogState();
}

class _VideoInfoDialogState extends ConsumerState<VideoInfoDialog> {
  final Set<String> _selectedPaths = <String>{};
  bool _busy = false;
  String? _error;

  int get _videoId => widget.video.id;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final versionsAsync = ref.watch(videoVersionsProvider(_videoId));
    final job = ref.watch(videoConversionJobProvider(_videoId));
    final versions = versionsAsync.asData?.value ?? const <VideoVersionInfo>[];
    // Versions can disappear while the dialog is open (e.g. a scan pruned a
    // missing file); stale selections are ignored rather than shown.
    final selectedPaths = {
      for (final version in versions)
        if (_selectedPaths.contains(version.path)) version.path,
    };

    VideoVersionInfo? primary;
    for (final version in versions) {
      if (version.isPrimary) primary = version;
    }
    final path = primary?.path ?? widget.video.absolutePath;
    final size = primary?.sizeBytes ?? widget.video.size;
    final converting = job?.isActive ?? false;
    final canEdit = !_busy && !converting;
    final canSelect = canEdit && versions.length > 1;
    final allSelected =
        versions.isNotEmpty && selectedPaths.length >= versions.length;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: WideDialogFrame(
        frameKey: const ValueKey('video-info-dialog'),
        size: _dialogSize(context),
        appIcon: const MacosIcon(CupertinoIcons.info),
        title: Semantics(
          container: true,
          header: true,
          child: const Text('Video Information'),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              'Drive: ${videoDriveName(path)}\n'
              'Size: ${LibraryStats.formatSize(size)}\n\n'
              'Full Path: $path',
            ),
            const SizedBox(height: MovieManagerSpacing.large),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      versionsAsync.hasValue
                          ? 'Versions (${versions.length})'
                          : 'Versions',
                      style: theme.typography.headline,
                    ),
                  ),
                ),
                PushButton(
                  key: const ValueKey('video-info-convert-button'),
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: canEdit
                      ? () => showVideoConversionDialog(
                          context,
                          videoIds: [_videoId],
                        )
                      : null,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(videoConversionIcon, size: 14),
                      SizedBox(width: 6),
                      Text('Convert…'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: MovieManagerSpacing.small),
            Expanded(
              child: versionsAsync.when(
                loading: () => const Center(child: ProgressCircle()),
                error: (error, _) =>
                    Text('Couldn’t load the versions of this video: $error'),
                data: (versions) => ListView.separated(
                  itemCount: versions.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: MovieManagerSpacing.compact),
                  itemBuilder: (context, index) {
                    final version = versions[index];
                    return _VideoVersionRow(
                      key: ValueKey('video-version-${version.path}'),
                      version: version,
                      selectable: versions.length > 1,
                      selected: selectedPaths.contains(version.path),
                      onSelected: canSelect
                          ? (selected) => setState(() {
                              if (selected) {
                                _selectedPaths.add(version.path);
                              } else {
                                _selectedPaths.remove(version.path);
                              }
                            })
                          : null,
                      onPlay: _busy ? null : () => _play(version),
                      onReveal: _busy ? null : () => _reveal(version),
                      onMakePrimary: canEdit && !version.isPrimary
                          ? () => _makePrimary(version)
                          : null,
                    );
                  },
                ),
              ),
            ),
            if (job != null) ...[
              const SizedBox(height: MovieManagerSpacing.small),
              VideoConversionJobTile(
                job: job,
                showTitle: false,
                onCancel: () => ref
                    .read(videoConversionControllerProvider.notifier)
                    .cancel(job.id),
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: MovieManagerSpacing.small),
              Text(
                error,
                style: theme.typography.caption1.copyWith(
                  color: MovieManagerVisuals.errorColor(context),
                ),
              ),
            ],
            if (versions.length > 1) ...[
              const SizedBox(height: MovieManagerSpacing.small),
              Row(
                children: [
                  PushButton(
                    key: const ValueKey('video-info-delete-versions-button'),
                    controlSize: ControlSize.regular,
                    secondary: true,
                    onPressed:
                        canEdit && selectedPaths.isNotEmpty && !allSelected
                        ? () => _confirmDelete(versions)
                        : null,
                    child: Text(
                      selectedPaths.length > 1
                          ? 'Delete ${selectedPaths.length} Versions…'
                          : 'Delete Version…',
                    ),
                  ),
                  const SizedBox(width: MovieManagerSpacing.small),
                  Expanded(
                    child: Text(
                      converting
                          ? 'Version changes are paused while this video '
                                'converts.'
                          : allSelected
                          ? 'Keep at least one version. To remove the video, '
                                'delete it from the Library.'
                          : _busy
                          ? 'Working…'
                          : 'Select versions to delete them from disk.',
                      style: theme.typography.caption1.copyWith(
                        color: MovieManagerVisuals.secondaryLabelColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: _close,
          child: const Text('OK'),
        ),
      ),
    );
  }

  Size _dialogSize(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    return Size(
      math.min(660, math.max(0.0, window.width - 48)),
      math.min(520, math.max(0.0, window.height - 96)),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on VideoVersionException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on LibraryAccessNeedsRepairException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _announce(String message) {
    if (mounted) ref.read(statusMessageProvider.notifier).set(message);
  }

  /// The current catalog row; the dialog's snapshot may be outdated.
  Future<Video> _currentVideo(VideosDao videosDao) async {
    final video = await videosDao.getVideoById(_videoId);
    if (video == null) {
      throw const VideoVersionException(
        'This video is no longer in the Library.',
      );
    }
    return video;
  }

  Future<void> _play(VideoVersionInfo version) {
    final videosDao = ref.read(videosDaoProvider);
    final playback = ref.read(playbackControllerProvider);
    return _run(() async {
      final video = await _currentVideo(videosDao);
      final opened = await playback.playFile(video, version.path);
      if (!opened) throw StateError(libraryAccessRepairMessage);
    });
  }

  Future<void> _reveal(VideoVersionInfo version) {
    final videosDao = ref.read(videosDaoProvider);
    final playback = ref.read(playbackControllerProvider);
    return _run(() async {
      final video = await _currentVideo(videosDao);
      await playback.revealFileInFinder(video, version.path);
    });
  }

  Future<void> _makePrimary(VideoVersionInfo version) {
    final service = ref.read(videoVersionServiceProvider);
    return _run(() async {
      await service.setPrimaryVersion(videoId: _videoId, path: version.path);
      _announce('Now using the ${version.qualityLabel} version for playback.');
    });
  }

  Future<void> _confirmDelete(List<VideoVersionInfo> versions) async {
    final selected = versions
        .where((version) => _selectedPaths.contains(version.path))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final includesPrimary = selected.any((version) => version.isPrimary);
    final names = selected.map((version) => version.fileName).join(', ');
    final confirmed = await showMacosAlertDialog<bool>(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.trash),
        title: Text(
          selected.length == 1
              ? 'Delete Version?'
              : 'Delete ${selected.length} Versions?',
        ),
        message: Text(
          'This permanently deletes $names from disk.'
          '${includesPrimary ? ' Another version will be used for playback.' : ''}',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final service = ref.read(videoVersionServiceProvider);
    await _run(() async {
      final result = await service.deleteVersions(
        videoId: _videoId,
        paths: selected.map((version) => version.path),
      );
      _announce(result.userMessage);
      if (!mounted) return;
      setState(() {
        _selectedPaths.removeAll(result.deletedPaths);
        if (result.failures.isNotEmpty) _error = result.userMessage;
      });
    });
  }
}

class _VideoVersionRow extends StatelessWidget {
  const _VideoVersionRow({
    super.key,
    required this.version,
    required this.selectable,
    required this.selected,
    required this.onSelected,
    required this.onPlay,
    required this.onReveal,
    required this.onMakePrimary,
  });

  final VideoVersionInfo version;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final VoidCallback? onPlay;
  final VoidCallback? onReveal;
  final VoidCallback? onMakePrimary;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final secondary = MovieManagerVisuals.secondaryLabelColor(context);
    final codec = version.videoCodec;
    final details = [
      version.resolutionLabel,
      if (codec != null) _codecLabel(codec),
      formatVideoDuration(version.durationSeconds),
      LibraryStats.formatSize(version.sizeBytes),
    ].join(' · ');
    return Semantics(
      container: true,
      label:
          '${version.qualityLabel} ${version.kindLabel.toLowerCase()} version'
          '${version.isPrimary ? ', used for playback' : ''}',
      value: details,
      child: DecoratedBox(
        decoration: MovieManagerVisuals.panelDecoration(
          context,
          selected: selected,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MovieManagerSpacing.small,
            vertical: MovieManagerSpacing.compact + 2,
          ),
          child: Row(
            children: [
              if (selectable) ...[
                MacosPreferenceCheckbox(
                  value: selected,
                  semanticLabel: 'Select ${version.fileName}',
                  onChanged: onSelected,
                ),
                const SizedBox(width: MovieManagerSpacing.small),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          version.qualityLabel,
                          style: theme.typography.headline,
                        ),
                        const SizedBox(width: MovieManagerSpacing.small),
                        _VersionBadge(label: version.kindLabel),
                        if (version.isPrimary) ...[
                          const SizedBox(width: MovieManagerSpacing.compact),
                          _VersionBadge(
                            label: 'In use',
                            color: theme.primaryColor,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      style: theme.typography.caption1.copyWith(
                        color: secondary,
                      ),
                    ),
                    MacosTooltip(
                      message: version.path,
                      child: Text(
                        version.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.caption1.copyWith(
                          color: secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              MovieManagerIconButton(
                label: 'Play ${version.qualityLabel} version',
                icon: CupertinoIcons.play_fill,
                onPressed: onPlay,
              ),
              MovieManagerIconButton(
                label: 'Show ${version.qualityLabel} version in Finder',
                icon: CupertinoIcons.folder,
                onPressed: onReveal,
              ),
              if (!version.isPrimary) ...[
                const SizedBox(width: MovieManagerSpacing.compact),
                PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: onMakePrimary,
                  child: const Text('Use for Playback'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? MovieManagerVisuals.secondaryLabelColor(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MovieManagerRadii.control),
        border: Border.all(color: resolved.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          style: MacosTheme.of(
            context,
          ).typography.caption2.copyWith(color: resolved),
        ),
      ),
    );
  }
}
