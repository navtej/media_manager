import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../services/library_access_service.dart';
import '../services/media_service.dart';
import '../services/video_transcoder.dart';
import '../services/video_version_service.dart';
import 'private_library_controller.dart';
import 'settings_provider.dart';
import 'status_message_provider.dart';
import 'video_version_models.dart';

const videoConversionPresetKey = 'videoConversionPreset';
const videoConversionKeepOriginalKey = 'videoConversionKeepOriginal';

/// Finished jobs kept for the queue window.
const _finishedJobHistoryLimit = 50;

enum VideoConversionStatus {
  queued,
  preparing,
  converting,
  finalizing,
  completed,
  failed,
  cancelled,
}

class VideoConversionJob {
  const VideoConversionJob({
    required this.id,
    required this.videoId,
    required this.title,
    required this.preset,
    required this.keepSource,
    this.isPrivate = false,
    this.status = VideoConversionStatus.queued,
    this.progress,
    this.message,
    this.outputPath,
  });

  final int id;
  final int videoId;
  final String title;
  final VideoResolutionPreset preset;
  final bool keepSource;

  /// The video is in a private library: its title and file names are hidden
  /// while private libraries are locked.
  final bool isPrivate;
  final VideoConversionStatus status;

  /// Fraction of the source processed, when known.
  final double? progress;

  /// Detail for the current status: a step, an error or the result.
  final String? message;
  final String? outputPath;

  bool get isActive =>
      status == VideoConversionStatus.queued ||
      status == VideoConversionStatus.preparing ||
      status == VideoConversionStatus.converting ||
      status == VideoConversionStatus.finalizing;

  bool get isRunning => isActive && status != VideoConversionStatus.queued;

  bool hidesDetails({required bool revealPrivate}) =>
      isPrivate && !revealPrivate;

  /// The title in quotes, or a neutral name while it must stay hidden.
  String quotedTitle({required bool revealPrivate}) =>
      hidesDetails(revealPrivate: revealPrivate)
      ? 'a private video'
      : '“$title”';

  /// Finalizing swaps files in the catalog and must run to completion.
  bool get canCancel => isActive && status != VideoConversionStatus.finalizing;

  int? get percent {
    final value = progress;
    return value == null ? null : (value.clamp(0.0, 1.0) * 100).floor();
  }

  String get statusText {
    return switch (status) {
      VideoConversionStatus.queued => 'Queued',
      VideoConversionStatus.preparing => 'Preparing',
      VideoConversionStatus.converting =>
        percent == null ? 'Converting' : 'Converting $percent%',
      VideoConversionStatus.finalizing => 'Finishing',
      VideoConversionStatus.completed => 'Done',
      VideoConversionStatus.failed => 'Failed',
      VideoConversionStatus.cancelled => 'Cancelled',
    };
  }

  VideoConversionJob copyWith({
    VideoConversionStatus? status,
    double? progress,
    bool clearProgress = false,
    String? message,
    bool clearMessage = false,
    String? outputPath,
  }) {
    return VideoConversionJob(
      id: id,
      videoId: videoId,
      title: title,
      preset: preset,
      keepSource: keepSource,
      isPrivate: isPrivate,
      status: status ?? this.status,
      progress: clearProgress ? null : progress ?? this.progress,
      message: clearMessage ? null : message ?? this.message,
      outputPath: outputPath ?? this.outputPath,
    );
  }
}

class VideoConversionState {
  const VideoConversionState({this.jobs = const <VideoConversionJob>[]});

  /// Every known job in the order it was queued.
  final List<VideoConversionJob> jobs;

  VideoConversionJob? get runningJob {
    for (final job in jobs) {
      if (job.isRunning) return job;
    }
    return null;
  }

  int get queuedCount =>
      jobs.where((job) => job.status == VideoConversionStatus.queued).length;

  int get activeCount => jobs.where((job) => job.isActive).length;

  bool get hasFinishedJobs => jobs.any((job) => !job.isActive);

  bool isConverting(int videoId) =>
      jobs.any((job) => job.videoId == videoId && job.isActive);

  /// The active job for [videoId], else its most recent finished one.
  VideoConversionJob? latestJobFor(int videoId) {
    VideoConversionJob? latest;
    for (final job in jobs) {
      if (job.videoId != videoId) continue;
      if (job.isActive) return job;
      latest = job;
    }
    return latest;
  }

  String footerText({bool revealPrivate = true}) {
    final running = runningJob;
    final queued = queuedCount;
    if (running == null) {
      return queued == 0 ? '' : 'Video conversions queued: $queued';
    }
    final title = running.quotedTitle(revealPrivate: revealPrivate);
    final label = running.preset.label;
    final percent = running.percent;
    final text = switch (running.status) {
      VideoConversionStatus.preparing => 'Preparing $title for $label',
      VideoConversionStatus.finalizing => 'Saving $label version of $title',
      _ when percent != null => 'Converting $title to $label: $percent%',
      _ => 'Converting $title to $label',
    };
    return queued == 0 ? text : '$text (+$queued queued)';
  }
}

class VideoConversionEnqueueResult {
  const VideoConversionEnqueueResult({
    required this.queued,
    this.skipped = const <String>[],
  });

  final int queued;

  /// User-facing reasons for videos that were not queued.
  final List<String> skipped;

  String get userMessage {
    final queuedText = queued == 1 ? '1 video' : '$queued videos';
    if (skipped.isEmpty) {
      return 'Queued $queuedText for conversion.';
    }
    if (queued == 0) {
      return skipped.length == 1
          ? skipped.single
          : 'No videos queued. ${skipped.first} (+${skipped.length - 1} more)';
    }
    return 'Queued $queuedText for conversion; ${skipped.length} skipped. '
        '${skipped.first}';
  }
}

class VideoConversionPreferences {
  const VideoConversionPreferences({
    required this.preset,
    required this.keepOriginal,
  });

  static const defaults = VideoConversionPreferences(
    preset: VideoResolutionPreset.hd720,
    keepOriginal: true,
  );

  final VideoResolutionPreset preset;
  final bool keepOriginal;

  /// [preset] when it is offered, else the highest offered preset.
  VideoResolutionPreset? presetFor(List<VideoResolutionPreset> offered) {
    if (offered.isEmpty) return null;
    return offered.contains(preset) ? preset : offered.first;
  }
}

final videoConversionPreferencesProvider =
    FutureProvider<VideoConversionPreferences>((ref) async {
      final persistence = await ref.watch(settingsPersistenceProvider.future);
      return VideoConversionPreferences(
        preset:
            VideoResolutionPreset.fromName(
              persistence.getString(videoConversionPresetKey),
            ) ??
            VideoConversionPreferences.defaults.preset,
        keepOriginal:
            persistence.getBool(videoConversionKeepOriginalKey) ??
            VideoConversionPreferences.defaults.keepOriginal,
      );
    });

/// Converts videos to lower resolutions one at a time in the background.
///
/// FFmpeg runs natively off the UI thread; this controller only sequences
/// jobs, reports progress and hands finished files to [VideoVersionService].
class VideoConversionController extends Notifier<VideoConversionState> {
  int _nextJobId = 1;
  bool _workerRunning = false;
  Completer<void>? _workerDone;
  VideoTranscodeTask? _activeTask;
  Completer<void>? _runningJobDone;
  final Set<int> _cancelRequested = <int>{};
  bool _shuttingDown = false;

  @override
  VideoConversionState build() {
    ref.onDispose(() {
      _shuttingDown = true;
      unawaited(_activeTask?.cancel());
    });
    return const VideoConversionState();
  }

  /// Queues [videoIds] for conversion to [preset]. Videos that are missing,
  /// offline, already converting or already at or below [preset] are skipped.
  Future<VideoConversionEnqueueResult> enqueue({
    required List<int> videoIds,
    required VideoResolutionPreset preset,
    required bool keepSource,
  }) async {
    final uniqueIds = videoIds.toSet().toList(growable: false);
    final videosById = {
      for (final video
          in await ref.read(videosDaoProvider).getVideosByIds(uniqueIds))
        video.id: video,
    };
    final privateFolderIds = {
      for (final folder in await ref.read(foldersDaoProvider).getAllFolders())
        if (folder.isPrivate) folder.id,
    };
    final versionService = ref.read(videoVersionServiceProvider);
    final newJobs = <VideoConversionJob>[];
    final skipped = <String>[];

    for (final videoId in uniqueIds) {
      final video = videosById[videoId];
      if (video == null) {
        skipped.add('Video $videoId is no longer in the Library.');
        continue;
      }
      if (video.isOffline) {
        skipped.add('“${video.title}” is offline.');
        continue;
      }
      if (state.isConverting(videoId) ||
          newJobs.any((job) => job.videoId == videoId)) {
        skipped.add('“${video.title}” is already being converted.');
        continue;
      }
      final bestQuality = _bestQualityClass(
        await versionService.listVersions(videoId),
      );
      if (bestQuality != null && bestQuality <= preset.shortSide) {
        skipped.add('“${video.title}” is already ${preset.label} or lower.');
        continue;
      }
      newJobs.add(
        VideoConversionJob(
          id: _nextJobId++,
          videoId: videoId,
          title: video.title,
          preset: preset,
          keepSource: keepSource,
          isPrivate: privateFolderIds.contains(video.folderId),
        ),
      );
    }

    await _rememberPreferences(preset: preset, keepOriginal: keepSource);
    if (!ref.mounted) {
      return VideoConversionEnqueueResult(queued: 0, skipped: skipped);
    }
    if (newJobs.isNotEmpty) {
      state = VideoConversionState(jobs: [...state.jobs, ...newJobs]);
      _ensureWorker();
    }
    return VideoConversionEnqueueResult(
      queued: newJobs.length,
      skipped: skipped,
    );
  }

  void cancel(int jobId) {
    final job = _job(jobId);
    if (job == null || !job.canCancel) return;
    if (job.status == VideoConversionStatus.queued) {
      _update(
        jobId,
        (job) => job.copyWith(
          status: VideoConversionStatus.cancelled,
          clearProgress: true,
          message: 'Cancelled before it started.',
        ),
      );
      return;
    }
    _cancelRequested.add(jobId);
    unawaited(_activeTask?.cancel());
  }

  /// Cancels every queued or running job for [videoIds], e.g. before the
  /// videos are deleted, and waits for a running one to clean up.
  Future<void> cancelForVideos(Iterable<int> videoIds) async {
    final ids = videoIds.toSet();
    for (final job in state.jobs) {
      if (ids.contains(job.videoId) && job.canCancel) {
        cancel(job.id);
      }
    }
    final running = state.runningJob;
    if (running != null && ids.contains(running.videoId)) {
      await _runningJobDone?.future;
    }
  }

  void clearFinished() {
    state = VideoConversionState(
      jobs: state.jobs.where((job) => job.isActive).toList(growable: false),
    );
  }

  /// Stops all work before the app quits. The running transcode is cancelled
  /// and its partial output removed; queued jobs are dropped.
  Future<void> shutdown({Duration timeout = const Duration(seconds: 5)}) async {
    _shuttingDown = true;
    for (final job in state.jobs) {
      if (job.canCancel) cancel(job.id);
    }
    final done = _workerDone;
    if (done == null) return;
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      debugPrint('Video conversion did not stop within $timeout.');
    }
  }

  void _ensureWorker() {
    if (_workerRunning || _shuttingDown) return;
    _workerRunning = true;
    final done = _workerDone = Completer<void>();
    unawaited(
      _runQueue().whenComplete(() {
        _workerRunning = false;
        done.complete();
      }),
    );
  }

  Future<void> _runQueue() async {
    while (!_shuttingDown && ref.mounted) {
      VideoConversionJob? next;
      for (final job in state.jobs) {
        if (job.status == VideoConversionStatus.queued) {
          next = job;
          break;
        }
      }
      if (next == null) return;
      await _runJob(next);
    }
  }

  Future<void> _runJob(VideoConversionJob job) async {
    final done = _runningJobDone = Completer<void>();
    _update(
      job.id,
      (job) => job.copyWith(
        status: VideoConversionStatus.preparing,
        clearProgress: true,
        clearMessage: true,
      ),
    );
    final versionService = ref.read(videoVersionServiceProvider);
    VideoConversionPlan? plan;
    try {
      plan = await versionService.planConversion(
        videoId: job.videoId,
        preset: job.preset,
        keepSource: job.keepSource,
      );
      _throwIfCancelled(job.id);
      final activePlan = plan;
      final outcome = await ref
          .read(libraryAccessServiceProvider)
          .withAccess(
            library: activePlan.libraryAccess,
            action: () => _convert(job, activePlan, versionService),
          );
      final message = outcome.replacedSource
          ? 'Replaced with ${outcome.version.resolutionLabel} '
                '(${outcome.version.fileName}).'
          : 'Saved ${outcome.version.fileName} '
                '(${outcome.version.resolutionLabel}).';
      _update(
        job.id,
        (job) => job.copyWith(
          status: VideoConversionStatus.completed,
          progress: 1,
          message: [message, ...outcome.warnings].join(' '),
          outputPath: outcome.version.path,
        ),
      );
      _announce(
        (title) => 'Converted $title to ${job.preset.label}.',
        job: job,
      );
    } on _ConversionCancelled {
      await _discard(versionService, plan);
      _update(
        job.id,
        (job) => job.copyWith(
          status: VideoConversionStatus.cancelled,
          clearProgress: true,
          message: 'Cancelled.',
        ),
      );
    } catch (error) {
      await _discard(versionService, plan);
      final message = switch (error) {
        VideoVersionException(:final message) => message,
        LibraryAccessNeedsRepairException(:final message) => message,
        _ => 'Conversion failed: $error',
      };
      debugPrint('Video conversion ${job.id} failed: $error');
      _update(
        job.id,
        (job) => job.copyWith(
          status: VideoConversionStatus.failed,
          clearProgress: true,
          message: message,
        ),
      );
      _announce(
        (title) => 'Couldn’t convert $title. Open Conversions for details.',
        job: job,
      );
    } finally {
      _cancelRequested.remove(job.id);
      _activeTask = null;
      _trimHistory();
      done.complete();
    }
  }

  Future<VideoConversionOutcome> _convert(
    VideoConversionJob job,
    VideoConversionPlan plan,
    VideoVersionService versionService,
  ) async {
    final metadata = await ref
        .read(mediaServiceProvider)
        .getMetadata(plan.source.path);
    _throwIfCancelled(job.id);
    final dimensions = videoDimensionsFromMetadata(metadata);
    if (dimensions == null) {
      throw VideoVersionException(
        'Couldn’t read the video stream of “${job.title}”.',
      );
    }
    if (dimensions.qualityClass <= plan.preset.shortSide) {
      throw VideoVersionException(
        '“${job.title}” is already ${plan.preset.label} or lower.',
      );
    }
    final durationSeconds =
        videoDurationFromMetadata(metadata) ??
        plan.source.durationSeconds.toDouble();

    VideoTranscodeResult? result;
    for (final encoder in VideoConversionEncoder.values) {
      _throwIfCancelled(job.id);
      _update(
        job.id,
        (job) => job.copyWith(
          status: VideoConversionStatus.converting,
          progress: 0,
          message: encoder.label,
        ),
      );
      final task = ref
          .read(videoTranscoderProvider)
          .start(
            buildVideoConversionArguments(
              inputPath: plan.source.path,
              outputPath: plan.temporaryPath,
              sourceMetadata: metadata,
              preset: plan.preset,
              encoder: encoder,
            ),
            onProgress: (processed) =>
                _reportProgress(job.id, processed, durationSeconds),
          );
      _activeTask = task;
      if (_cancelRequested.contains(job.id)) {
        await task.cancel();
      }
      result = await task.result;
      _activeTask = null;
      if (result.status == VideoTranscodeStatus.succeeded) break;
      if (result.status == VideoTranscodeStatus.cancelled) {
        throw const _ConversionCancelled();
      }
      debugPrint(
        'Video conversion ${job.id} with ${encoder.name} failed: '
        '${result.errorMessage}',
      );
    }
    if (result?.status != VideoTranscodeStatus.succeeded) {
      throw VideoVersionException(
        'FFmpeg couldn’t convert “${job.title}”: '
        '${result?.errorMessage ?? 'unknown error'}',
      );
    }
    _throwIfCancelled(job.id);

    _update(
      job.id,
      (job) => job.copyWith(
        status: VideoConversionStatus.finalizing,
        progress: 1,
        message: 'Checking and saving the converted file',
      ),
    );
    return versionService.finalizeConversion(
      plan,
      expectedDurationSeconds: durationSeconds,
    );
  }

  void _reportProgress(int jobId, Duration processed, double durationSeconds) {
    if (durationSeconds <= 0 || !ref.mounted) return;
    final progress = (processed.inMilliseconds / (durationSeconds * 1000))
        .clamp(0.0, 1.0);
    final job = _job(jobId);
    if (job == null || job.status != VideoConversionStatus.converting) return;
    // Statistics arrive twice a second; only whole percents change the UI.
    if (job.percent == (progress * 100).floor()) return;
    _update(jobId, (job) => job.copyWith(progress: progress));
  }

  Future<void> _discard(
    VideoVersionService versionService,
    VideoConversionPlan? plan,
  ) async {
    if (plan == null) return;
    try {
      await ref
          .read(libraryAccessServiceProvider)
          .withAccess(
            library: plan.libraryAccess,
            action: () => versionService.discardTemporaryOutput(plan),
          );
    } catch (error) {
      debugPrint('Could not remove ${plan.temporaryPath}: $error');
    }
  }

  void _throwIfCancelled(int jobId) {
    if (_cancelRequested.contains(jobId) || _shuttingDown) {
      throw const _ConversionCancelled();
    }
  }

  VideoConversionJob? _job(int jobId) {
    for (final job in state.jobs) {
      if (job.id == jobId) return job;
    }
    return null;
  }

  void _update(
    int jobId,
    VideoConversionJob Function(VideoConversionJob job) change,
  ) {
    if (!ref.mounted) return;
    state = VideoConversionState(
      jobs: [for (final job in state.jobs) job.id == jobId ? change(job) : job],
    );
  }

  void _trimHistory() {
    if (!ref.mounted) return;
    final finished = state.jobs.where((job) => !job.isActive).length;
    if (finished <= _finishedJobHistoryLimit) return;
    var toDrop = finished - _finishedJobHistoryLimit;
    state = VideoConversionState(
      jobs: [
        for (final job in state.jobs)
          if (job.isActive || toDrop-- <= 0) job,
      ],
    );
  }

  void _announce(
    String Function(String quotedTitle) message, {
    required VideoConversionJob job,
  }) {
    if (!ref.mounted || _shuttingDown) return;
    final revealPrivate = ref
        .read(privateLibraryAccessControllerProvider)
        .isUnlocked;
    ref
        .read(statusMessageProvider.notifier)
        .set(
          message(job.quotedTitle(revealPrivate: revealPrivate)),
          duration: const Duration(seconds: 5),
        );
  }

  Future<void> _rememberPreferences({
    required VideoResolutionPreset preset,
    required bool keepOriginal,
  }) async {
    try {
      final persistence = await ref.read(settingsPersistenceProvider.future);
      await persistence.setString(videoConversionPresetKey, preset.name);
      await persistence.setBool(videoConversionKeepOriginalKey, keepOriginal);
      if (ref.mounted) ref.invalidate(videoConversionPreferencesProvider);
    } catch (error) {
      debugPrint('Could not save video conversion preferences: $error');
    }
  }
}

int? _bestQualityClass(List<VideoVersionInfo> versions) {
  int? best;
  for (final version in versions) {
    final quality = version.dimensions?.qualityClass;
    if (quality == null) continue;
    if (best == null || quality > best) best = quality;
  }
  return best;
}

class _ConversionCancelled implements Exception {
  const _ConversionCancelled();
}

final videoConversionControllerProvider =
    NotifierProvider<VideoConversionController, VideoConversionState>(
      VideoConversionController.new,
    );

final videoConversionStatusProvider = Provider<String>((ref) {
  final revealPrivate = ref.watch(
    privateLibraryAccessControllerProvider.select((state) => state.isUnlocked),
  );
  return ref
      .watch(videoConversionControllerProvider)
      .footerText(revealPrivate: revealPrivate);
});

/// The active job for a video, else its most recent finished one.
final videoConversionJobProvider = Provider.family<VideoConversionJob?, int>((
  ref,
  videoId,
) {
  return ref.watch(
    videoConversionControllerProvider.select(
      (state) => state.latestJobFor(videoId),
    ),
  );
});
