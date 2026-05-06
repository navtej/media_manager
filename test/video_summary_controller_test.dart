import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/video_summary_controller.dart';
import 'package:movie_manager/logic/video_summary_models.dart';
import 'package:movie_manager/services/folder_access_service.dart';
import 'package:movie_manager/services/media_service.dart';
import 'package:movie_manager/services/natural_language_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'fails with repair message before audio extraction when folder access fails',
    () async {
      final fixture = await _SummaryControllerFixture.create(
        canAccessFolder: false,
      );
      addTearDown(fixture.dispose);

      await fixture.generate();

      final state = fixture.container.read(
        videoSummaryControllerProvider(fixture.video.id),
      );
      expect(state.hasError, isTrue);
      expect(
        state.error.toString(),
        contains(
          'Folder access needs repair. Reselect this folder in Settings.',
        ),
      );
      expect(fixture.mediaService.extractedPaths, isEmpty);
      expect(fixture.events, ['start:${fixture.root.path}']);
    },
  );

  test(
    'starts folder access before extraction and stops it afterward',
    () async {
      final fixture = await _SummaryControllerFixture.create();
      addTearDown(fixture.dispose);

      await fixture.generate();

      final state = fixture.container.read(
        videoSummaryControllerProvider(fixture.video.id),
      );
      expect(state.hasError, isFalse);
      expect(fixture.events, [
        'start:${fixture.root.path}',
        'extract:${fixture.video.absolutePath}',
        'stop:${fixture.root.path}',
      ]);

      final summary = await fixture.db.videoSummariesDao.getSummaryForVideo(
        fixture.video.id,
      );
      expect(summary, isNotNull);
      expect(summary!.transcriptText, 'transcript');
    },
  );
}

class _SummaryControllerFixture {
  _SummaryControllerFixture({
    required this.db,
    required this.container,
    required this.root,
    required this.video,
    required this.folderAccessService,
    required this.mediaService,
    required this.audioFile,
    required this.events,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final Directory root;
  final Video video;
  final _FakeFolderAccessService folderAccessService;
  final _FakeMediaService mediaService;
  final File audioFile;
  final List<String> events;

  static Future<_SummaryControllerFixture> create({
    bool canAccessFolder = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final root = await Directory.systemTemp.createTemp(
      'video-summary-controller-test',
    );
    final videoFile = File(p.join(root.path, 'video.mp4'));
    await videoFile.writeAsBytes(const <int>[1, 2, 3]);

    final audioFile = File(p.join(root.path, 'audio.wav'));
    await audioFile.writeAsBytes(const <int>[4, 5, 6]);

    final modelFile = File(p.join(root.path, 'ggml-test.bin'));
    await modelFile.writeAsBytes(const <int>[7, 8, 9]);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: videoFile.path,
        title: 'video',
        size: drift.Value(await videoFile.length()),
        fileCreatedAt: drift.Value(await videoFile.lastModified()),
      ),
    );
    final video = (await db.videosDao.getVideoByPath(videoFile.path))!;
    final events = <String>[];
    final folderAccessService = _FakeFolderAccessService(
      canAccess: canAccessFolder,
      events: events,
    );
    final mediaService = _FakeMediaService(
      audioPath: audioFile.path,
      events: events,
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsProvider.overrideWith(
          () => _FakeSettings(modelPath: modelFile.path),
        ),
        summaryModelValidationProvider.overrideWith(
          (_) async => const SummaryModelValidationResult.valid('Ready'),
        ),
        folderAccessServiceProvider.overrideWithValue(folderAccessService),
        mediaServiceProvider.overrideWithValue(mediaService),
        naturalLanguageServiceProvider.overrideWithValue(
          _FakeNaturalLanguageService(),
        ),
      ],
    );

    return _SummaryControllerFixture(
      db: db,
      container: container,
      root: root,
      video: video,
      folderAccessService: folderAccessService,
      mediaService: mediaService,
      audioFile: audioFile,
      events: events,
    );
  }

  Future<void> generate() {
    return container
        .read(videoSummaryControllerProvider(video.id).notifier)
        .generate(video);
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

class _FakeSettings extends Settings {
  _FakeSettings({required this.modelPath});

  final String modelPath;

  @override
  Future<Map<String, dynamic>> build() async {
    return <String, dynamic>{'summaryModelPath': modelPath};
  }
}

class _FakeFolderAccessService extends FolderAccessService {
  _FakeFolderAccessService({required this.canAccess, required this.events});

  final bool canAccess;
  final List<String> events;

  @override
  Future<FolderAccessSession> startAccessing({
    required String path,
    required String? bookmark,
  }) async {
    this.events.add('start:$path');
    return FolderAccessSession(
      path: path,
      canAccess: canAccess,
      needsRepair: !canAccess,
      message: canAccess
          ? null
          : 'Folder access needs repair. Reselect this folder in Settings.',
    );
  }

  @override
  Future<void> stopAccessing({
    required String path,
    required String? bookmark,
  }) async {
    events.add('stop:$path');
  }
}

class _FakeMediaService extends MediaService {
  _FakeMediaService({required this.audioPath, required this.events});

  final String audioPath;
  final List<String> events;
  final extractedPaths = <String>[];

  @override
  Future<String?> extractTranscriptionAudio(String path) async {
    events.add('extract:$path');
    extractedPaths.add(path);
    return audioPath;
  }
}

class _FakeNaturalLanguageService extends NaturalLanguageService {
  @override
  Future<String> transcribeAudio({
    required String audioPath,
    required String modelPath,
  }) async {
    return 'transcript';
  }

  @override
  Future<StructuredVideoSummary> summarizeTranscript({
    required String title,
    required String metadataJson,
    required String transcript,
  }) async {
    return StructuredVideoSummary(
      synopsis: 'synopsis',
      highlights: const ['highlight'],
      keywords: const ['keyword'],
    );
  }
}
