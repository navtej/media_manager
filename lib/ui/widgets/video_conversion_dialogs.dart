import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../logic/catalog_controller.dart' show LibraryStats;
import '../../logic/private_library_controller.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_conversion_controller.dart';
import '../../logic/video_version_models.dart';
import '../../services/video_transcoder.dart' show targetVideoBitrateKbps;
import '../../services/video_version_service.dart';
import '../movie_manager_visual_system.dart';
import 'macos_preference_checkbox.dart';
import 'video_move_dialog.dart' show WideDialogFrame;

const videoConversionIcon = CupertinoIcons.arrow_down_right_arrow_up_left;

/// Audio allowance used when estimating a converted file's size.
const _estimatedAudioKbps = 160;

String formatVideoDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final secs = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }
  return '$minutes:${secs.toString().padLeft(2, '0')}';
}

Size _dialogSize(BuildContext context, Size preferred) {
  final window = MediaQuery.sizeOf(context);
  return Size(
    math.min(preferred.width, math.max(0.0, window.width - 48)),
    math.min(preferred.height, math.max(0.0, window.height - 96)),
  );
}

/// Asks for a target resolution and whether to keep the original, then
/// queues [videoIds] for background conversion.
Future<void> showVideoConversionDialog(
  BuildContext context, {
  required List<int> videoIds,
}) {
  return showMacosAlertDialog<void>(
    context: context,
    builder: (_) => VideoConversionDialog(videoIds: videoIds),
  );
}

class VideoConversionDialog extends ConsumerStatefulWidget {
  const VideoConversionDialog({super.key, required this.videoIds});

  final List<int> videoIds;

  @override
  ConsumerState<VideoConversionDialog> createState() =>
      _VideoConversionDialogState();
}

class _ConversionDialogData {
  const _ConversionDialogData({
    required this.videos,
    required this.source,
    required this.presets,
  });

  final List<Video> videos;

  /// The version a single-video conversion starts from.
  final VideoVersionInfo? source;
  final List<VideoResolutionPreset> presets;
}

class _VideoConversionDialogState extends ConsumerState<VideoConversionDialog> {
  late final Future<_ConversionDialogData> _data = _load();
  VideoResolutionPreset? _preset;
  bool? _keepOriginal;
  bool _submitting = false;

  Future<_ConversionDialogData> _load() async {
    final preferences = await ref.read(
      videoConversionPreferencesProvider.future,
    );
    final videosById = {
      for (final video
          in await ref.read(videosDaoProvider).getVideosByIds(widget.videoIds))
        video.id: video,
    };
    final videos = [for (final id in widget.videoIds) ?videosById[id]];

    VideoVersionInfo? source;
    VideoDimensions? largest;
    if (videos.length == 1) {
      final versions = await ref
          .read(videoVersionServiceProvider)
          .listVersions(videos.single.id);
      source = _bestSource(versions);
      largest = source?.dimensions;
    } else {
      for (final video in videos) {
        final dimensions = videoDimensionsFromMetadataJson(video.metadataJson);
        if (dimensions == null) {
          // Unknown dimensions: offer everything and let enqueue skip.
          largest = null;
          break;
        }
        if (largest == null || dimensions.qualityClass > largest.qualityClass) {
          largest = dimensions;
        }
      }
    }
    final presets = VideoResolutionPreset.below(largest);
    if (mounted) {
      setState(() {
        _preset ??= preferences.presetFor(presets);
        _keepOriginal ??= preferences.keepOriginal;
      });
    }
    return _ConversionDialogData(
      videos: videos,
      source: source,
      presets: presets,
    );
  }

  Future<void> _submit(_ConversionDialogData data) async {
    final preset = _preset;
    if (preset == null || _submitting) return;
    setState(() => _submitting = true);
    final videoIds = data.videos.map((video) => video.id).toList();
    final keepOriginal = _keepOriginal ?? true;
    final conversions = ref.read(videoConversionControllerProvider.notifier);
    String message;
    try {
      final result = await ref
          .read(privateLibraryAccessControllerProvider.notifier)
          .runVideoAction<VideoConversionEnqueueResult>(
            videoIds: videoIds,
            action: () => conversions.enqueue(
              videoIds: videoIds,
              preset: preset,
              keepSource: keepOriginal,
            ),
          );
      message = result?.userMessage ?? 'Authentication cancelled.';
    } catch (error) {
      message = 'Couldn’t queue the conversion: $error';
    }
    if (!mounted) return;
    ref
        .read(statusMessageProvider.notifier)
        .set(message, duration: const Duration(seconds: 5));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return FutureBuilder<_ConversionDialogData>(
      future: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final canConvert =
            data != null &&
            data.videos.isNotEmpty &&
            _preset != null &&
            !_submitting;
        return WideDialogFrame(
          frameKey: const ValueKey('video-conversion-dialog'),
          size: _dialogSize(context, const Size(520, 400)),
          appIcon: const MacosIcon(videoConversionIcon),
          title: const Text('Convert to Lower Resolution'),
          content: switch (snapshot) {
            AsyncSnapshot(hasError: true) => Text(
              'Couldn’t read the video: ${snapshot.error}',
            ),
            AsyncSnapshot(data: final data?) => SingleChildScrollView(
              child: _buildForm(context, theme, data),
            ),
            _ => const Center(child: ProgressCircle()),
          },
          secondaryButton: PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          primaryButton: PushButton(
            key: const ValueKey('video-conversion-convert-button'),
            controlSize: ControlSize.large,
            onPressed: canConvert ? () => _submit(data) : null,
            child: Text(_submitting ? 'Queuing…' : 'Convert'),
          ),
        );
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    MacosThemeData theme,
    _ConversionDialogData data,
  ) {
    final secondary = MovieManagerVisuals.secondaryLabelColor(context);
    if (data.videos.isEmpty) {
      return const Text('The selected videos are no longer in the Library.');
    }
    final single = data.videos.length == 1 ? data.videos.single : null;
    final source = data.source;
    final keepOriginal = _keepOriginal ?? true;
    final preset = _preset;
    final keepLabel = single == null
        ? 'Keep the original files'
        : source == null || source.isOriginal
        ? 'Keep the original file'
        : 'Keep the source file (${source.qualityLabel})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          single == null ? '${data.videos.length} videos' : single.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.typography.headline,
        ),
        const SizedBox(height: MovieManagerSpacing.compact),
        Text(
          single == null
              ? 'Videos already at or below the chosen resolution are skipped.'
              : source == null
              ? 'Source details unavailable.'
              : 'Source: ${source.kindLabel} · ${source.resolutionLabel} '
                    '(${source.qualityLabel}) · '
                    '${formatVideoDuration(source.durationSeconds)} · '
                    '${LibraryStats.formatSize(source.sizeBytes)}',
          style: theme.typography.caption1.copyWith(color: secondary),
        ),
        const SizedBox(height: MovieManagerSpacing.large),
        if (data.presets.isEmpty || preset == null)
          Text(
            'This video is already at the lowest offered resolution '
            '(${VideoResolutionPreset.values.last.label}).',
          )
        else ...[
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text('Resolution', style: theme.typography.body),
              ),
              MacosPopupButton<VideoResolutionPreset>(
                key: const ValueKey('video-conversion-preset'),
                value: preset,
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _preset = value);
                      },
                items: [
                  for (final option in data.presets)
                    MacosPopupMenuItem(
                      value: option,
                      child: Text(option.label),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: MovieManagerSpacing.small),
          Text(
            'Fits within ${preset.longSide}×${preset.shortSide} '
            '(${preset.shortSide}×${preset.longSide} for portrait video), '
            'keeping the aspect ratio. Saved as H.264 MP4.',
            style: theme.typography.caption1.copyWith(color: secondary),
          ),
          if (source != null && source.durationSeconds > 0) ...[
            const SizedBox(height: MovieManagerSpacing.small),
            Text(
              'Estimated size: about '
              '${LibraryStats.formatSize(_estimatedBytes(source, preset))}',
              style: theme.typography.caption1.copyWith(color: secondary),
            ),
          ],
        ],
        const SizedBox(height: MovieManagerSpacing.large),
        Row(
          children: [
            MacosPreferenceCheckbox(
              key: const ValueKey('video-conversion-keep-original'),
              value: keepOriginal,
              semanticLabel: keepLabel,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _keepOriginal = value),
            ),
            const SizedBox(width: MovieManagerSpacing.small),
            Expanded(
              child: ExcludeSemantics(
                child: Text(keepLabel, style: theme.typography.body),
              ),
            ),
          ],
        ),
        const SizedBox(height: MovieManagerSpacing.compact),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Text(
            keepOriginal
                ? 'The converted copy is saved next to the original as a '
                      'separate version you can play or delete later.'
                : 'After the converted file is verified, the original is '
                      'deleted and the Library uses the converted file. '
                      'This can’t be undone.',
            style: theme.typography.caption1.copyWith(
              color: keepOriginal
                  ? secondary
                  : MovieManagerVisuals.warningColor(context),
            ),
          ),
        ),
        const SizedBox(height: MovieManagerSpacing.large),
        Text(
          'Conversion runs in the background, one video at a time. Progress '
          'appears in the status bar.',
          style: theme.typography.caption1.copyWith(color: secondary),
        ),
      ],
    );
  }
}

VideoVersionInfo? _bestSource(List<VideoVersionInfo> versions) {
  VideoVersionInfo? best;
  for (final version in versions) {
    if (best == null) {
      best = version;
      continue;
    }
    final quality = version.dimensions?.qualityClass ?? -1;
    final bestQuality = best.dimensions?.qualityClass ?? -1;
    if (quality > bestQuality ||
        (quality == bestQuality && version.isOriginal && !best.isOriginal)) {
      best = version;
    }
  }
  return best;
}

int _estimatedBytes(VideoVersionInfo source, VideoResolutionPreset preset) {
  final sourceBitsPerSecond = source.durationSeconds > 0
      ? source.sizeBytes * 8 ~/ source.durationSeconds
      : 0;
  final videoKbps = targetVideoBitrateKbps(
    sourceMetadata: {
      if (sourceBitsPerSecond > 0) 'bitrate': sourceBitsPerSecond,
    },
    preset: preset,
  );
  return (videoKbps + _estimatedAudioKbps) * 1000 ~/ 8 * source.durationSeconds;
}

/// Lists queued, running and recently finished conversions.
Future<void> showVideoConversionQueueDialog(BuildContext context) {
  return showMacosAlertDialog<void>(
    context: context,
    builder: (_) => const VideoConversionQueueDialog(),
  );
}

class VideoConversionQueueDialog extends ConsumerWidget {
  const VideoConversionQueueDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(videoConversionControllerProvider);
    final controller = ref.read(videoConversionControllerProvider.notifier);
    final revealPrivate = ref.watch(
      privateLibraryAccessControllerProvider.select(
        (state) => state.isUnlocked,
      ),
    );
    final jobs = state.jobs.reversed.toList(growable: false);
    return WideDialogFrame(
      frameKey: const ValueKey('video-conversion-queue-dialog'),
      size: _dialogSize(context, const Size(640, 440)),
      appIcon: const MacosIcon(videoConversionIcon),
      title: const Text('Video Conversions'),
      content: jobs.isEmpty
          ? const MovieManagerStateMessage(
              icon: videoConversionIcon,
              title: 'No Conversions',
              message: 'Converted videos appear here while they run.',
              compact: true,
            )
          : ListView.separated(
              itemCount: jobs.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: MovieManagerSpacing.small),
              itemBuilder: (context, index) => VideoConversionJobTile(
                job: jobs[index],
                revealPrivate: revealPrivate,
                onCancel: jobs[index].canCancel
                    ? () => controller.cancel(jobs[index].id)
                    : null,
              ),
            ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: state.hasFinishedJobs ? controller.clearFinished : null,
        child: const Text('Clear Finished'),
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Done'),
      ),
    );
  }
}

/// One conversion job: status, progress and a cancel action.
class VideoConversionJobTile extends StatelessWidget {
  const VideoConversionJobTile({
    super.key,
    required this.job,
    this.onCancel,
    this.showTitle = true,
    this.revealPrivate = true,
  });

  final VideoConversionJob job;
  final VoidCallback? onCancel;
  final bool showTitle;

  /// False while private libraries are locked: a private job then shows no
  /// title or file names.
  final bool revealPrivate;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final secondary = MovieManagerVisuals.secondaryLabelColor(context);
    final statusColor = switch (job.status) {
      VideoConversionStatus.failed => MovieManagerVisuals.errorColor(context),
      VideoConversionStatus.completed => MovieManagerVisuals.successColor(
        context,
      ),
      _ => secondary,
    };
    final hidden = job.hidesDetails(revealPrivate: revealPrivate);
    final title = hidden ? 'Private video' : job.title;
    final detail = hidden ? null : job.message;
    return Semantics(
      container: true,
      label:
          '${showTitle ? '$title, ' : ''}'
          'convert to ${job.preset.label}, ${job.statusText}',
      child: DecoratedBox(
        decoration: MovieManagerVisuals.panelDecoration(context),
        child: Padding(
          padding: const EdgeInsets.all(MovieManagerSpacing.small),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showTitle)
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.headline,
                      ),
                    Text(
                      '${job.preset.label} · '
                      '${job.keepSource ? 'Keep original' : 'Replace original'}'
                      ' · ${job.statusText}',
                      style: theme.typography.caption1.copyWith(
                        color: statusColor,
                      ),
                    ),
                    if (job.status == VideoConversionStatus.converting) ...[
                      const SizedBox(height: MovieManagerSpacing.compact),
                      ProgressBar(
                        value: (job.progress ?? 0).clamp(0.0, 1.0) * 100,
                        semanticLabel: 'Conversion progress',
                      ),
                    ],
                    if (detail != null && detail.isNotEmpty) ...[
                      const SizedBox(height: MovieManagerSpacing.compact),
                      SelectableText(
                        detail,
                        maxLines: 3,
                        style: theme.typography.caption1.copyWith(
                          color: job.status == VideoConversionStatus.failed
                              ? MovieManagerVisuals.errorColor(context)
                              : secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (job.canCancel) ...[
                const SizedBox(width: MovieManagerSpacing.small),
                PushButton(
                  controlSize: ControlSize.regular,
                  secondary: true,
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
