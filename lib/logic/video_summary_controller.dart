import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../services/library_access_service.dart';
import '../services/media_service.dart';
import '../services/natural_language_service.dart';
import 'settings_provider.dart';
import 'video_summary_models.dart';

const _vttTranscriptIdentityPrefix = 'vtt:';

final videoSummaryRecordProvider = StreamProvider.autoDispose
    .family<VideoSummary?, int>((ref, videoId) {
      return ref.watch(videoSummariesDaoProvider).watchSummaryForVideo(videoId);
    });

enum VideoSummaryTaskPhase {
  queued,
  validating,
  accessingMedia,
  extractingAudio,
  transcribing,
  summarizing,
  saving,
  completed,
  failed,
}

class VideoSummaryTaskState {
  const VideoSummaryTaskState({
    required this.videoId,
    required this.title,
    required this.phase,
    this.error,
  });

  final int videoId;
  final String title;
  final VideoSummaryTaskPhase phase;
  final Object? error;

  bool get isRunning =>
      phase != VideoSummaryTaskPhase.completed &&
      phase != VideoSummaryTaskPhase.failed;

  String get statusText {
    return switch (phase) {
      VideoSummaryTaskPhase.queued => 'Queued',
      VideoSummaryTaskPhase.validating => 'Checking model',
      VideoSummaryTaskPhase.accessingMedia => 'Accessing media',
      VideoSummaryTaskPhase.extractingAudio => 'Extracting audio',
      VideoSummaryTaskPhase.transcribing => 'Transcribing audio',
      VideoSummaryTaskPhase.summarizing => 'Summarizing transcript',
      VideoSummaryTaskPhase.saving => 'Saving summary',
      VideoSummaryTaskPhase.completed => 'Summary ready',
      VideoSummaryTaskPhase.failed => 'Summary failed',
    };
  }

  String get footerText => 'Generating summary: $title - $statusText';

  VideoSummaryTaskState copyWith({
    VideoSummaryTaskPhase? phase,
    Object? error,
    bool clearError = false,
  }) {
    return VideoSummaryTaskState(
      videoId: videoId,
      title: title,
      phase: phase ?? this.phase,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final videoSummaryTasksProvider =
    NotifierProvider<
      VideoSummaryTasksController,
      Map<int, VideoSummaryTaskState>
    >(VideoSummaryTasksController.new);

final videoSummaryTaskProvider = Provider.family<VideoSummaryTaskState?, int>((
  ref,
  videoId,
) {
  return ref.watch(videoSummaryTasksProvider.select((tasks) => tasks[videoId]));
});

final videoSummaryStatusProvider = Provider<String>((ref) {
  final tasks = ref.watch(videoSummaryTasksProvider);
  for (final task in tasks.values) {
    if (task.isRunning) {
      return task.footerText;
    }
  }
  return '';
});

enum VideoSummaryStatus {
  missing,
  fresh,
  stale,
  malformed,
  generating,
  completed,
  failed,
}

class VideoSummaryState {
  const VideoSummaryState._({
    required this.status,
    required this.storedStatus,
    required this.configuredTranscriptModel,
    required this.preferVttSubtitles,
    this.summary,
    this.task,
    this.error,
  });

  factory VideoSummaryState.fresh({
    required StructuredVideoSummary summary,
    required String configuredTranscriptModel,
    required bool preferVttSubtitles,
  }) {
    return VideoSummaryState._(
      status: VideoSummaryStatus.fresh,
      storedStatus: VideoSummaryStatus.fresh,
      configuredTranscriptModel: configuredTranscriptModel,
      preferVttSubtitles: preferVttSubtitles,
      summary: summary,
    );
  }

  factory VideoSummaryState._from({
    required _StoredVideoSummaryState stored,
    required VideoSummaryTaskState? task,
    required String configuredTranscriptModel,
    required bool preferVttSubtitles,
  }) {
    final VideoSummaryStatus status;
    if (task?.phase == VideoSummaryTaskPhase.failed) {
      status = VideoSummaryStatus.failed;
    } else if (task?.isRunning == true) {
      status = VideoSummaryStatus.generating;
    } else if (task?.phase == VideoSummaryTaskPhase.completed &&
        stored.status == VideoSummaryStatus.fresh) {
      status = VideoSummaryStatus.completed;
    } else {
      status = stored.status;
    }

    return VideoSummaryState._(
      status: status,
      storedStatus: stored.status,
      configuredTranscriptModel: configuredTranscriptModel,
      preferVttSubtitles: preferVttSubtitles,
      summary: stored.summary,
      task: task,
      error: task?.phase == VideoSummaryTaskPhase.failed
          ? task?.error
          : stored.error,
    );
  }

  final VideoSummaryStatus status;
  final VideoSummaryStatus storedStatus;
  final String configuredTranscriptModel;
  final bool preferVttSubtitles;
  final StructuredVideoSummary? summary;
  final VideoSummaryTaskState? task;
  final Object? error;

  bool get hasStoredSummary => storedStatus != VideoSummaryStatus.missing;

  bool get hasFreshSummary => storedStatus == VideoSummaryStatus.fresh;

  bool get isGenerating => status == VideoSummaryStatus.generating;
}

final videoSummaryStateProvider = FutureProvider.autoDispose
    .family<VideoSummaryState, Video>((ref, video) async {
      final record = await ref.watch(
        videoSummaryRecordProvider(video.id).future,
      );
      final task = ref.watch(videoSummaryTaskProvider(video.id));
      final configuration = (await ref.watch(
        settingsProvider.future,
      )).videoSummary;
      final configuredTranscriptModel = transcriptModelNameFromPath(
        configuration.modelPath,
      );
      final parsed = _parseStoredVideoSummary(record);
      if (parsed.status == VideoSummaryStatus.missing ||
          parsed.status == VideoSummaryStatus.malformed) {
        return VideoSummaryState._from(
          stored: parsed,
          task: task,
          configuredTranscriptModel: configuredTranscriptModel,
          preferVttSubtitles: configuration.preferVttSubtitles,
        );
      }

      final folder = await ref
          .watch(foldersDaoProvider)
          .getFolderById(video.folderId);
      if (folder == null) {
        return VideoSummaryState._from(
          stored: parsed.asStale(StateError('Library folder is missing.')),
          task: task,
          configuredTranscriptModel: configuredTranscriptModel,
          preferVttSubtitles: configuration.preferVttSubtitles,
        );
      }

      try {
        final stored = await ref
            .watch(libraryAccessServiceProvider)
            .withAccess(
              library: LibraryAccessRequest(
                path: folder.path,
                bookmark: folder.securityScopedBookmark,
              ),
              action: () async {
                final file = File(video.absolutePath);
                if (!await file.exists()) {
                  return parsed.asStale(StateError('Video file is missing.'));
                }

                final stat = await file.stat();
                final transcriptIdentities =
                    await _acceptedTranscriptIdentities(
                      videoPath: video.absolutePath,
                      storedTranscriptIdentity: record!.transcriptModel,
                      configuredTranscriptIdentity: configuredTranscriptModel,
                    );
                return _applyFreshness(
                  parsed,
                  record: record,
                  videoStat: stat,
                  transcriptIdentities: transcriptIdentities,
                  summaryModel: summaryModelNameFromApiUrl(
                    configuration.apiUrl,
                  ),
                );
              },
            );
        return VideoSummaryState._from(
          stored: stored,
          task: task,
          configuredTranscriptModel: configuredTranscriptModel,
          preferVttSubtitles: configuration.preferVttSubtitles,
        );
      } catch (error) {
        return VideoSummaryState._from(
          stored: parsed.asStale(error),
          task: task,
          configuredTranscriptModel: configuredTranscriptModel,
          preferVttSubtitles: configuration.preferVttSubtitles,
        );
      }
    });

final videoSummarySubtitleAvailabilityProvider = FutureProvider.autoDispose
    .family<VideoSummarySubtitleAvailability, Video>((ref, video) async {
      final foldersDao = ref.watch(foldersDaoProvider);
      final libraryAccessService = ref.watch(libraryAccessServiceProvider);
      final folder = await foldersDao.getFolderById(video.folderId);
      if (folder == null) {
        return const VideoSummarySubtitleAvailability.notFound();
      }

      return libraryAccessService.withAccess(
        library: LibraryAccessRequest(
          path: folder.path,
          bookmark: folder.securityScopedBookmark,
        ),
        action: () async {
          final subtitleFile = await findSiblingVttFile(video.absolutePath);
          if (subtitleFile == null) {
            return const VideoSummarySubtitleAvailability.notFound();
          }

          return VideoSummarySubtitleAvailability.found(
            path: subtitleFile.path,
          );
        },
      );
    });

class VideoSummarySubtitleAvailability {
  const VideoSummarySubtitleAvailability._({required this.path});

  const VideoSummarySubtitleAvailability.notFound() : this._(path: null);

  const VideoSummarySubtitleAvailability.found({required String path})
    : this._(path: path);

  final String? path;

  bool get isFound => path != null;

  String get fileName {
    final value = path;
    if (value == null) {
      return '';
    }
    return value.split(Platform.pathSeparator).last;
  }
}

class VideoSummaryTasksController
    extends Notifier<Map<int, VideoSummaryTaskState>> {
  bool _isGenerating = false;
  _VideoSummaryCancellation? _activeCancellation;

  @override
  Map<int, VideoSummaryTaskState> build() => const {};

  Future<void> generate(
    Video video, {
    bool forceRefresh = false,
    bool? preferVttSubtitlesOverride,
  }) async {
    if (_isGenerating) {
      _setTask(
        VideoSummaryTaskState(
          videoId: video.id,
          title: video.title,
          phase: VideoSummaryTaskPhase.failed,
          error: StateError('Another summary is already being generated.'),
        ),
      );
      return;
    }

    String? audioPath;
    final cancellation = _VideoSummaryCancellation(video.id);
    _isGenerating = true;
    _activeCancellation = cancellation;

    _setTask(
      VideoSummaryTaskState(
        videoId: video.id,
        title: video.title,
        phase: VideoSummaryTaskPhase.queued,
      ),
    );

    try {
      final libraryAccessService = ref.read(libraryAccessServiceProvider);
      final mediaService = ref.read(mediaServiceProvider);
      final naturalLanguageService = ref.read(naturalLanguageServiceProvider);
      final foldersDao = ref.read(foldersDaoProvider);
      final dao = ref.read(videoSummariesDaoProvider);
      _setPhase(video.id, VideoSummaryTaskPhase.validating);
      final configuration = (await ref.read(
        settingsProvider.future,
      )).videoSummary;
      cancellation.throwIfCancelled();
      final modelPath = configuration.modelPath.trim();
      final summaryApiUrl = configuration.apiUrl.trim();
      if (summaryApiUrl.isEmpty) {
        throw StateError('Summarization API URL is not configured.');
      }
      final summaryApiKey = configuration.apiKey.trim();
      final summaryModel = summaryModelNameFromApiUrl(summaryApiUrl);
      final preferVttSubtitles =
          preferVttSubtitlesOverride ?? configuration.preferVttSubtitles;
      final configuredTranscriptModel = transcriptModelNameFromPath(modelPath);
      final folder = await foldersDao.getFolderById(video.folderId);
      cancellation.throwIfCancelled();
      if (folder == null) {
        throw StateError('Library folder is missing.');
      }

      _setPhase(video.id, VideoSummaryTaskPhase.accessingMedia);
      await libraryAccessService.withAccess(
        library: LibraryAccessRequest(
          path: folder.path,
          bookmark: folder.securityScopedBookmark,
        ),
        action: () async {
          final file = File(video.absolutePath);
          if (!await file.exists()) {
            throw StateError('Video file is missing.');
          }

          final stat = await file.stat();
          cancellation.throwIfCancelled();
          final existing = await dao.getSummaryForVideo(video.id);
          cancellation.throwIfCancelled();
          _VttTranscriptSource? currentVttSource;

          if (!forceRefresh && existing != null) {
            final parsed = _parseStoredVideoSummary(existing);
            final transcriptIdentities = await _acceptedTranscriptIdentities(
              videoPath: video.absolutePath,
              storedTranscriptIdentity: existing.transcriptModel,
              configuredTranscriptIdentity: configuredTranscriptModel,
              onVttSource: (source) => currentVttSource = source,
            );
            cancellation.throwIfCancelled();
            final stored = _applyFreshness(
              parsed,
              record: existing,
              videoStat: stat,
              transcriptIdentities: transcriptIdentities,
              summaryModel: summaryModel,
            );
            if (stored.status == VideoSummaryStatus.fresh) {
              cancellation.throwIfCancelled();
              _setPhase(video.id, VideoSummaryTaskPhase.completed);
              return;
            }
          }

          final subtitleTranscript = preferVttSubtitles
              ? await _readSiblingVttTranscript(
                  video.absolutePath,
                  source: currentVttSource,
                )
              : null;
          cancellation.throwIfCancelled();
          final transcriptModel =
              subtitleTranscript?.freshnessModel ?? configuredTranscriptModel;
          final String transcript;
          if (subtitleTranscript != null) {
            transcript = subtitleTranscript.transcript;
          } else {
            final validation = await ref.read(
              summaryModelValidationProvider.future,
            );
            cancellation.throwIfCancelled();
            if (!validation.isValid) {
              throw StateError(
                'Summary model is not ready: ${validation.status}.',
              );
            }

            _setPhase(video.id, VideoSummaryTaskPhase.extractingAudio);
            audioPath = await mediaService.extractTranscriptionAudio(
              video.absolutePath,
            );
            cancellation.throwIfCancelled();
            if (audioPath == null) {
              throw StateError('Audio extraction failed.');
            }

            _setPhase(video.id, VideoSummaryTaskPhase.transcribing);
            transcript = await naturalLanguageService.transcribeAudio(
              audioPath: audioPath!,
              modelPath: modelPath,
            );
            cancellation.throwIfCancelled();
          }

          _setPhase(video.id, VideoSummaryTaskPhase.summarizing);
          final summary = await naturalLanguageService.summarizeTranscript(
            title: video.title,
            metadataJson: video.metadataJson,
            transcript: transcript,
            apiUrl: summaryApiUrl,
            apiKey: summaryApiKey,
          );
          cancellation.throwIfCancelled();

          _setPhase(video.id, VideoSummaryTaskPhase.saving);
          final now = DateTime.now();
          await dao.upsertSummary(
            VideoSummariesCompanion(
              videoId: drift.Value(video.id),
              transcriptText: drift.Value(transcript),
              summaryJson: drift.Value(jsonEncode(summary.toJson())),
              transcriptModel: drift.Value(transcriptModel),
              summaryModel: drift.Value(summaryModel),
              sourceVideoSize: drift.Value(stat.size),
              sourceVideoModifiedAt: drift.Value(stat.modified),
              generatedAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );
          cancellation.throwIfCancelled();

          _setPhase(video.id, VideoSummaryTaskPhase.completed);
        },
      );
    } on _VideoSummaryCancelled {
      _removeTask(video.id);
    } catch (error) {
      _setTask(
        VideoSummaryTaskState(
          videoId: video.id,
          title: video.title,
          phase: VideoSummaryTaskPhase.failed,
          error: error,
        ),
      );
    } finally {
      _isGenerating = false;
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      if (audioPath != null) {
        final audioFile = File(audioPath!);
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      }
    }
  }

  void cancel(int videoId) {
    final cancellation = _activeCancellation;
    if (cancellation == null || cancellation.videoId != videoId) {
      return;
    }
    cancellation.cancel();
    _removeTask(videoId);
  }

  void _setPhase(int videoId, VideoSummaryTaskPhase phase) {
    final existing = state[videoId];
    if (existing == null) {
      return;
    }
    _setTask(existing.copyWith(phase: phase, clearError: true));
  }

  void _setTask(VideoSummaryTaskState task) {
    state = {...state, task.videoId: task};
  }

  void _removeTask(int videoId) {
    state = Map<int, VideoSummaryTaskState>.of(state)..remove(videoId);
  }
}

class _VideoSummaryCancellation {
  _VideoSummaryCancellation(this.videoId);

  final int videoId;
  bool _isCancelled = false;

  void cancel() => _isCancelled = true;

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const _VideoSummaryCancelled();
    }
  }
}

class _VideoSummaryCancelled implements Exception {
  const _VideoSummaryCancelled();
}

class _StoredVideoSummaryState {
  const _StoredVideoSummaryState({
    required this.status,
    this.summary,
    this.error,
  });

  final VideoSummaryStatus status;
  final StructuredVideoSummary? summary;
  final Object? error;

  _StoredVideoSummaryState asStale([Object? error]) {
    return _StoredVideoSummaryState(
      status: VideoSummaryStatus.stale,
      summary: summary,
      error: error,
    );
  }
}

_StoredVideoSummaryState _parseStoredVideoSummary(VideoSummary? record) {
  if (record == null) {
    return const _StoredVideoSummaryState(status: VideoSummaryStatus.missing);
  }

  try {
    final decoded = jsonDecode(record.summaryJson);
    if (decoded is! Map) {
      throw const FormatException('Stored summary must be a JSON object.');
    }
    final summary = StructuredVideoSummary.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    return _StoredVideoSummaryState(
      status: VideoSummaryStatus.stale,
      summary: summary,
    );
  } catch (error) {
    return _StoredVideoSummaryState(
      status: VideoSummaryStatus.malformed,
      error: error is FormatException
          ? error
          : const FormatException('Stored summary is malformed.'),
    );
  }
}

_StoredVideoSummaryState _applyFreshness(
  _StoredVideoSummaryState parsed, {
  required VideoSummary record,
  required FileStat videoStat,
  required Set<String> transcriptIdentities,
  required String summaryModel,
}) {
  if (parsed.status == VideoSummaryStatus.malformed ||
      parsed.status == VideoSummaryStatus.missing) {
    return parsed;
  }

  final isFresh =
      videoStat.type == FileSystemEntityType.file &&
      record.sourceVideoSize == videoStat.size &&
      _samePersistedTimestamp(
        record.sourceVideoModifiedAt,
        videoStat.modified,
      ) &&
      transcriptIdentities.contains(record.transcriptModel) &&
      record.summaryModel == summaryModel;
  return _StoredVideoSummaryState(
    status: isFresh ? VideoSummaryStatus.fresh : VideoSummaryStatus.stale,
    summary: parsed.summary,
  );
}

bool _samePersistedTimestamp(DateTime stored, DateTime current) {
  return stored.millisecondsSinceEpoch ~/ 1000 ==
      current.millisecondsSinceEpoch ~/ 1000;
}

Future<Set<String>> _acceptedTranscriptIdentities({
  required String videoPath,
  required String storedTranscriptIdentity,
  required String configuredTranscriptIdentity,
  void Function(_VttTranscriptSource source)? onVttSource,
}) async {
  if (!storedTranscriptIdentity.startsWith(_vttTranscriptIdentityPrefix)) {
    return {configuredTranscriptIdentity};
  }

  final source = await _findSiblingVttSource(videoPath);
  if (source == null) {
    return const {};
  }
  onVttSource?.call(source);
  return {source.identity};
}

class _VttTranscriptSource {
  const _VttTranscriptSource({required this.file, required this.stat});

  final File file;
  final FileStat stat;

  String get identity =>
      '$_vttTranscriptIdentityPrefix${Uri.encodeComponent(file.absolute.path)}:'
      '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
}

Future<_VttTranscriptSource?> _findSiblingVttSource(String videoPath) async {
  final file = await findSiblingVttFile(videoPath);
  if (file == null) {
    return null;
  }
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
    return null;
  }
  return _VttTranscriptSource(file: file, stat: stat);
}

class _SubtitleTranscript {
  const _SubtitleTranscript({
    required this.transcript,
    required this.freshnessModel,
  });

  final String transcript;
  final String freshnessModel;
}

Future<_SubtitleTranscript?> _readSiblingVttTranscript(
  String videoPath, {
  _VttTranscriptSource? source,
}) async {
  final subtitleSource = source ?? await _findSiblingVttSource(videoPath);
  if (subtitleSource == null) {
    return null;
  }

  final content = await subtitleSource.file.readAsString();
  final transcript = await compute(parseVttTranscript, content);
  if (transcript.isEmpty) {
    return null;
  }

  return _SubtitleTranscript(
    transcript: transcript,
    freshnessModel: subtitleSource.identity,
  );
}

String siblingVttPath(String videoPath) {
  final dotIndex = videoPath.lastIndexOf('.');
  if (dotIndex <= videoPath.lastIndexOf(Platform.pathSeparator)) {
    return '$videoPath.vtt';
  }
  return '${videoPath.substring(0, dotIndex)}.vtt';
}

Future<File?> findSiblingVttFile(String videoPath) async {
  final defaultSubtitle = File(siblingVttPath(videoPath));
  if (await _isUsableVttFile(defaultSubtitle)) {
    return defaultSubtitle;
  }

  final separatorIndex = videoPath.lastIndexOf(Platform.pathSeparator);
  final directoryPath = separatorIndex < 0
      ? Directory.current.path
      : videoPath.substring(0, separatorIndex);
  final fileName = separatorIndex < 0
      ? videoPath
      : videoPath.substring(separatorIndex + 1);
  final dotIndex = fileName.lastIndexOf('.');
  final stem = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
  final localizedPattern = RegExp(
    '^${RegExp.escape(stem)}\\.[a-z]{2}\\.vtt\$',
    caseSensitive: false,
  );

  final directory = Directory(directoryPath);
  if (!await directory.exists()) {
    return null;
  }

  final candidates = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final candidateName = entity.path.split(Platform.pathSeparator).last;
    if (localizedPattern.hasMatch(candidateName) &&
        await _isUsableVttFile(entity)) {
      candidates.add(entity);
    }
  }

  candidates.sort((a, b) => a.path.compareTo(b.path));
  return candidates.isEmpty ? null : candidates.first;
}

Future<bool> _isUsableVttFile(File file) async {
  if (!await file.exists()) {
    return false;
  }
  final stat = await file.stat();
  return stat.type == FileSystemEntityType.file && stat.size > 0;
}

String parseVttTranscript(String content) {
  final lines = content.split(RegExp(r'\r?\n'));
  final transcriptLines = <String>[];
  String? previousLine;

  for (final rawLine in lines) {
    final line = rawLine.replaceFirst('\ufeff', '').trim();
    if (line.isEmpty ||
        line == 'WEBVTT' ||
        line.startsWith('NOTE') ||
        line.contains('-->') ||
        RegExp(r'^\d+$').hasMatch(line)) {
      continue;
    }

    final cleaned = line
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty || cleaned == previousLine) {
      continue;
    }
    transcriptLines.add(cleaned);
    previousLine = cleaned;
  }

  return transcriptLines.join(' ').trim();
}
