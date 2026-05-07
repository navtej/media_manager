import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../services/folder_access_service.dart';
import '../services/media_service.dart';
import '../services/natural_language_service.dart';
import 'settings_provider.dart';
import 'video_summary_models.dart';

const _summaryModelName = 'foundation_models';
const _vttTranscriptModelPrefix = 'vtt:';

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

final videoSummarySubtitleAvailabilityProvider = FutureProvider.autoDispose
    .family<VideoSummarySubtitleAvailability, Video>((ref, video) async {
      final foldersDao = ref.watch(foldersDaoProvider);
      final folderAccessService = ref.watch(folderAccessServiceProvider);
      final folder = await foldersDao.getFolderById(video.folderId);
      if (folder == null) {
        return const VideoSummarySubtitleAvailability.notFound();
      }

      FolderAccessSession? accessSession;
      try {
        accessSession = await folderAccessService.startAccessing(
          path: folder.path,
          bookmark: folder.securityScopedBookmark,
        );
        if (!accessSession.canAccess) {
          return const VideoSummarySubtitleAvailability.notFound();
        }

        final subtitleFile = await findSiblingVttFile(video.absolutePath);
        if (subtitleFile == null) {
          return const VideoSummarySubtitleAvailability.notFound();
        }

        return VideoSummarySubtitleAvailability.found(path: subtitleFile.path);
      } finally {
        if (accessSession?.canAccess == true) {
          await folderAccessService.stopAccessing(
            path: folder.path,
            bookmark: folder.securityScopedBookmark,
          );
        }
      }
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
    Folder? accessedFolder;
    FolderAccessService? folderAccessService;
    _isGenerating = true;

    _setTask(
      VideoSummaryTaskState(
        videoId: video.id,
        title: video.title,
        phase: VideoSummaryTaskPhase.queued,
      ),
    );

    try {
      final activeFolderAccessService = ref.read(folderAccessServiceProvider);
      folderAccessService = activeFolderAccessService;
      final mediaService = ref.read(mediaServiceProvider);
      final naturalLanguageService = ref.read(naturalLanguageServiceProvider);
      final foldersDao = ref.read(foldersDaoProvider);
      final dao = ref.read(videoSummariesDaoProvider);
      _setPhase(video.id, VideoSummaryTaskPhase.validating);
      final settings = await ref.read(settingsProvider.future);
      final modelPath = (settings['summaryModelPath'] as String? ?? '').trim();
      final preferVttSubtitles =
          preferVttSubtitlesOverride ??
          (settings['summaryPreferVttSubtitles'] as bool? ?? true);
      final configuredTranscriptModel = transcriptModelNameFromPath(modelPath);
      final folder = await foldersDao.getFolderById(video.folderId);
      if (folder == null) {
        throw StateError('Library folder is missing.');
      }

      _setPhase(video.id, VideoSummaryTaskPhase.accessingMedia);
      final folderAccess = await activeFolderAccessService.startAccessing(
        path: folder.path,
        bookmark: folder.securityScopedBookmark,
      );
      if (!folderAccess.canAccess) {
        throw StateError(
          folderAccess.message ??
              'Folder access needs repair. Reselect this folder in Settings.',
        );
      }
      accessedFolder = folder;

      final file = File(video.absolutePath);
      if (!await file.exists()) {
        throw StateError('Video file is missing.');
      }

      final stat = await file.stat();
      final subtitleTranscript = preferVttSubtitles
          ? await _readSiblingVttTranscript(video.absolutePath)
          : null;
      final transcriptModel =
          subtitleTranscript?.freshnessModel ?? configuredTranscriptModel;
      final existing = await dao.getSummaryForVideo(video.id);

      if (!forceRefresh && existing != null) {
        final freshnessKey = VideoSummaryFreshnessKey(
          sourceVideoSize: existing.sourceVideoSize,
          sourceVideoModifiedAt: existing.sourceVideoModifiedAt,
          transcriptModel: existing.transcriptModel,
        );

        final cachedSummary = StructuredVideoSummary.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(existing.summaryJson) as Map<String, dynamic>,
          ),
        );

        if (freshnessKey.matches(
              fileSize: stat.size,
              fileModifiedAt: stat.modified,
              transcriptModel: transcriptModel,
            ) &&
            cachedSummary.synopsis.isNotEmpty) {
          _setPhase(video.id, VideoSummaryTaskPhase.completed);
          return;
        }
      }

      final String transcript;
      if (subtitleTranscript != null) {
        transcript = subtitleTranscript.transcript;
      } else {
        final validation = await ref.read(
          summaryModelValidationProvider.future,
        );
        if (!validation.isValid) {
          throw StateError('Summary model is not ready: ${validation.status}.');
        }

        _setPhase(video.id, VideoSummaryTaskPhase.extractingAudio);
        audioPath = await mediaService.extractTranscriptionAudio(
          video.absolutePath,
        );
        if (audioPath == null) {
          throw StateError('Audio extraction failed.');
        }

        _setPhase(video.id, VideoSummaryTaskPhase.transcribing);
        transcript = await naturalLanguageService.transcribeAudio(
          audioPath: audioPath,
          modelPath: modelPath,
        );
      }

      _setPhase(video.id, VideoSummaryTaskPhase.summarizing);
      final summary = await naturalLanguageService.summarizeTranscript(
        title: video.title,
        metadataJson: video.metadataJson,
        transcript: transcript,
      );

      _setPhase(video.id, VideoSummaryTaskPhase.saving);
      final now = DateTime.now();
      await dao.upsertSummary(
        VideoSummariesCompanion(
          videoId: drift.Value(video.id),
          transcriptText: drift.Value(transcript),
          summaryJson: drift.Value(jsonEncode(summary.toJson())),
          transcriptModel: drift.Value(transcriptModel),
          summaryModel: const drift.Value(_summaryModelName),
          sourceVideoSize: drift.Value(stat.size),
          sourceVideoModifiedAt: drift.Value(stat.modified),
          generatedAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      _setPhase(video.id, VideoSummaryTaskPhase.completed);
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
      if (audioPath != null) {
        final audioFile = File(audioPath);
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      }
      if (accessedFolder != null && folderAccessService != null) {
        await folderAccessService.stopAccessing(
          path: accessedFolder.path,
          bookmark: accessedFolder.securityScopedBookmark,
        );
      }
    }
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
}

class _SubtitleTranscript {
  const _SubtitleTranscript({
    required this.transcript,
    required this.freshnessModel,
  });

  final String transcript;
  final String freshnessModel;
}

Future<_SubtitleTranscript?> _readSiblingVttTranscript(String videoPath) async {
  final subtitleFile = await findSiblingVttFile(videoPath);
  if (subtitleFile == null) {
    return null;
  }

  final stat = await subtitleFile.stat();
  if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
    return null;
  }

  final content = await subtitleFile.readAsString();
  final transcript = await compute(parseVttTranscript, content);
  if (transcript.isEmpty) {
    return null;
  }

  return _SubtitleTranscript(
    transcript: transcript,
    freshnessModel:
        '$_vttTranscriptModelPrefix${stat.size}:${stat.modified.microsecondsSinceEpoch}',
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
