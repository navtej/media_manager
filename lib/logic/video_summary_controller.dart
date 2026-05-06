import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../services/folder_access_service.dart';
import '../services/media_service.dart';
import '../services/natural_language_service.dart';
import 'settings_provider.dart';
import 'video_summary_models.dart';

const _summaryModelName = 'foundation_models';

final videoSummaryRecordProvider = StreamProvider.autoDispose
    .family<VideoSummary?, int>((ref, videoId) {
      return ref.watch(videoSummariesDaoProvider).watchSummaryForVideo(videoId);
    });

final videoSummaryControllerProvider = NotifierProvider.autoDispose
    .family<VideoSummaryController, AsyncValue<void>, int>(
      VideoSummaryController.new,
    );

class VideoSummaryController extends Notifier<AsyncValue<void>> {
  VideoSummaryController(this.videoId);

  final int videoId;

  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> generate(Video video, {bool forceRefresh = false}) async {
    state = const AsyncLoading();

    String? audioPath;
    Folder? accessedFolder;
    FolderAccessService? folderAccessService;
    final keepAlive = ref.keepAlive();

    try {
      final activeFolderAccessService = ref.read(folderAccessServiceProvider);
      folderAccessService = activeFolderAccessService;
      final mediaService = ref.read(mediaServiceProvider);
      final naturalLanguageService = ref.read(naturalLanguageServiceProvider);
      final foldersDao = ref.read(foldersDaoProvider);
      final dao = ref.read(videoSummariesDaoProvider);
      final settings = await ref.read(settingsProvider.future);
      final validation = await ref.read(summaryModelValidationProvider.future);
      if (!validation.isValid) {
        throw StateError('Summary model is not ready: ${validation.status}.');
      }

      final modelPath = (settings['summaryModelPath'] as String? ?? '').trim();
      final transcriptModel = transcriptModelNameFromPath(modelPath);
      final folder = await foldersDao.getFolderById(video.folderId);
      if (folder == null) {
        throw StateError('Library folder is missing.');
      }

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
          state = const AsyncData(null);
          return;
        }
      }

      audioPath = await mediaService.extractTranscriptionAudio(
        video.absolutePath,
      );
      if (audioPath == null) {
        throw StateError('Audio extraction failed.');
      }

      final transcript = await naturalLanguageService.transcribeAudio(
        audioPath: audioPath,
        modelPath: modelPath,
      );
      final summary = await naturalLanguageService.summarizeTranscript(
        title: video.title,
        metadataJson: video.metadataJson,
        transcript: transcript,
      );

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

      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    } finally {
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
      keepAlive.close();
    }
  }
}
