import 'dart:async';
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
import 'package:movie_manager/services/library_access_service.dart';
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
        videoSummaryTaskProvider(fixture.video.id),
      );
      expect(state?.phase, VideoSummaryTaskPhase.failed);
      expect(
        state?.error.toString(),
        contains(
          'Folder access needs repair. Reselect this folder in Settings.',
        ),
      );
      expect(fixture.mediaService.extractedPaths, isEmpty);
      expect(fixture.events, ['start:${fixture.root.path}']);
    },
  );

  test('subtitle discovery surfaces the Library repair outcome', () async {
    final fixture = await _SummaryControllerFixture.create(
      canAccessFolder: false,
    );
    addTearDown(fixture.dispose);

    final provider = videoSummarySubtitleAvailabilityProvider(fixture.video);
    final errorCompleter = Completer<Object>();
    final subscription = fixture.container.listen(provider, (_, next) {
      if (next.hasError && !errorCompleter.isCompleted) {
        errorCompleter.complete(next.error!);
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    expect(
      await errorCompleter.future,
      isA<LibraryAccessNeedsRepairException>().having(
        (error) => error.message,
        'message',
        libraryAccessRepairMessage,
      ),
    );
  });

  test(
    'starts folder access before extraction and stops it afterward',
    () async {
      final fixture = await _SummaryControllerFixture.create();
      addTearDown(fixture.dispose);

      await fixture.generate();

      final state = fixture.container.read(
        videoSummaryTaskProvider(fixture.video.id),
      );
      expect(state?.phase, VideoSummaryTaskPhase.completed);
      expect(fixture.events, [
        'start:${fixture.root.path}',
        'extract:${fixture.video.absolutePath}',
        'transcribe',
        'summarize',
        'stop:${fixture.root.path}',
      ]);

      final summary = await fixture.db.videoSummariesDao.getSummaryForVideo(
        fixture.video.id,
      );
      expect(summary, isNotNull);
      expect(summary!.transcriptText, 'transcript');
      expect(await fixture.audioFile.exists(), isFalse);
      expect(
        fixture.naturalLanguageService.lastApiUrl,
        'https://summary.example.test/v1/chat/completions',
      );
      expect(fixture.naturalLanguageService.lastApiKey, 'sk-test');
    },
  );

  test('requires a summarization API URL before summarizing', () async {
    final fixture = await _SummaryControllerFixture.create(summaryApiUrl: '');
    addTearDown(fixture.dispose);

    await fixture.generate();

    final state = fixture.container.read(
      videoSummaryTaskProvider(fixture.video.id),
    );
    expect(state?.phase, VideoSummaryTaskPhase.failed);
    expect(
      state?.error.toString(),
      contains('Summarization API URL is not configured.'),
    );
    expect(fixture.naturalLanguageService.lastTranscript, isNull);
  });

  test('publishes footer status while summary generation is running', () async {
    final transcriptCompleter = Completer<String>();
    final fixture = await _SummaryControllerFixture.create(
      transcriptCompleter: transcriptCompleter,
    );
    addTearDown(fixture.dispose);

    final generation = fixture.generate();
    await fixture.waitForEvent('transcribe');

    expect(
      fixture.container.read(videoSummaryStatusProvider),
      'Generating summary: video - Transcribing audio',
    );

    transcriptCompleter.complete('transcript');
    await generation;

    expect(fixture.container.read(videoSummaryStatusProvider), '');
  });

  test(
    'uses sibling VTT transcript before extracting audio when preference is enabled',
    () async {
      final fixture = await _SummaryControllerFixture.create();
      addTearDown(fixture.dispose);
      await File(p.join(fixture.root.path, 'video.vtt')).writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
First subtitle line.

00:00:02.000 --> 00:00:04.000
Second subtitle line.
''');

      await fixture.generate();

      expect(fixture.events, [
        'start:${fixture.root.path}',
        'summarize',
        'stop:${fixture.root.path}',
      ]);
      expect(fixture.mediaService.extractedPaths, isEmpty);
      expect(
        fixture.naturalLanguageService.lastTranscript,
        contains('First subtitle line.'),
      );
      expect(
        fixture.naturalLanguageService.lastTranscript,
        contains('Second subtitle line.'),
      );

      final summary = await fixture.db.videoSummariesDao.getSummaryForVideo(
        fixture.video.id,
      );
      expect(summary, isNotNull);
      expect(summary!.transcriptText, contains('First subtitle line.'));
      expect(summary.transcriptModel, startsWith('vtt:'));
    },
  );

  test(
    'uses localized sibling VTT transcript when default VTT is absent',
    () async {
      final fixture = await _SummaryControllerFixture.create();
      addTearDown(fixture.dispose);
      await File(p.join(fixture.root.path, 'video.en.vtt')).writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
Localized subtitle line.
''');

      await fixture.generate();

      expect(fixture.mediaService.extractedPaths, isEmpty);
      expect(
        fixture.naturalLanguageService.lastTranscript,
        contains('Localized subtitle line.'),
      );
    },
  );

  test('module state and generator agree when a summary is reusable', () async {
    final fixture = await _SummaryControllerFixture.create();
    addTearDown(fixture.dispose);

    await fixture.generate();
    fixture.events.clear();

    final state = await fixture.readState();
    expect(state.storedStatus, VideoSummaryStatus.fresh);
    expect(state.hasFreshSummary, isTrue);
    fixture.events.clear();

    await fixture.generate();

    expect(fixture.events, [
      'start:${fixture.root.path}',
      'stop:${fixture.root.path}',
    ]);
    expect(
      fixture.container.read(videoSummaryTaskProvider(fixture.video.id))?.phase,
      VideoSummaryTaskPhase.completed,
    );
  });

  test(
    'module state detects video size, mtime, model, and summarizer changes',
    () async {
      final fixture = await _SummaryControllerFixture.create();
      addTearDown(fixture.dispose);

      await fixture.seedSummary();
      expect(
        (await fixture.readState()).storedStatus,
        VideoSummaryStatus.fresh,
      );

      final originalStat = await fixture.videoFile.stat();
      await fixture.videoFile.setLastModified(
        originalStat.modified.add(const Duration(seconds: 2)),
      );
      fixture.invalidateState();
      expect(
        (await fixture.readState()).storedStatus,
        VideoSummaryStatus.stale,
      );

      await fixture.seedSummary();
      await fixture.videoFile.writeAsBytes(const [1, 2, 3, 4]);
      fixture.invalidateState();
      expect(
        (await fixture.readState()).storedStatus,
        VideoSummaryStatus.stale,
      );

      await fixture.seedSummary(transcriptModel: 'different-model.bin');
      fixture.invalidateState();
      expect(
        (await fixture.readState()).storedStatus,
        VideoSummaryStatus.stale,
      );

      await fixture.seedSummary(
        summaryModel: summaryModelNameFromApiUrl(
          'https://different.example.test/v1/chat/completions',
        ),
      );
      fixture.invalidateState();
      expect(
        (await fixture.readState()).storedStatus,
        VideoSummaryStatus.stale,
      );
    },
  );

  test('module state detects VTT modification and removal', () async {
    final fixture = await _SummaryControllerFixture.create();
    addTearDown(fixture.dispose);
    var subtitle = File(p.join(fixture.root.path, 'video.vtt'));
    await subtitle.writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
Original subtitle.
''');

    await fixture.generate();
    expect((await fixture.readState()).storedStatus, VideoSummaryStatus.fresh);

    final localizedSubtitle = await subtitle.rename(
      p.join(fixture.root.path, 'video.en.vtt'),
    );
    fixture.invalidateState();
    expect((await fixture.readState()).storedStatus, VideoSummaryStatus.stale);

    subtitle = await localizedSubtitle.rename(
      p.join(fixture.root.path, 'video.vtt'),
    );
    await subtitle.writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:03.000
Changed subtitle content.
''');
    fixture.invalidateState();
    expect((await fixture.readState()).storedStatus, VideoSummaryStatus.stale);

    await subtitle.delete();
    fixture.invalidateState();
    expect((await fixture.readState()).storedStatus, VideoSummaryStatus.stale);
  });

  test('malformed stored summary is reported and regenerated', () async {
    final fixture = await _SummaryControllerFixture.create();
    addTearDown(fixture.dispose);
    await fixture.seedSummary(summaryJson: '{not-json');

    final state = await fixture.readState();
    expect(state.status, VideoSummaryStatus.malformed);
    expect(state.summary, isNull);
    expect(state.error, isA<FormatException>());

    await fixture.generate();

    expect(
      fixture.container.read(videoSummaryTaskProvider(fixture.video.id))?.phase,
      VideoSummaryTaskPhase.completed,
    );
    expect(fixture.naturalLanguageService.summarizeCount, 1);
    expect(
      (await fixture.db.videoSummariesDao.getSummaryForVideo(
        fixture.video.id,
      ))?.summaryJson,
      contains('synopsis'),
    );
  });

  test('force refresh regenerates an otherwise fresh summary', () async {
    final fixture = await _SummaryControllerFixture.create();
    addTearDown(fixture.dispose);
    await fixture.seedSummary();

    await fixture.generate(forceRefresh: true);

    expect(fixture.naturalLanguageService.summarizeCount, 1);
    expect(fixture.events, contains('extract:${fixture.video.absolutePath}'));
  });

  test('failure releases Library access and deletes temporary audio', () async {
    final fixture = await _SummaryControllerFixture.create(failSummary: true);
    addTearDown(fixture.dispose);

    await fixture.generate();

    expect(
      fixture.container.read(videoSummaryTaskProvider(fixture.video.id))?.phase,
      VideoSummaryTaskPhase.failed,
    );
    expect(await fixture.audioFile.exists(), isFalse);
    expect(fixture.events.last, 'stop:${fixture.root.path}');
  });

  test(
    'cancellation prevents saving and releases temporary resources',
    () async {
      final transcriptCompleter = Completer<String>();
      final fixture = await _SummaryControllerFixture.create(
        transcriptCompleter: transcriptCompleter,
      );
      addTearDown(fixture.dispose);

      final generation = fixture.generate();
      await fixture.waitForEvent('transcribe');
      fixture.container
          .read(videoSummaryTasksProvider.notifier)
          .cancel(fixture.video.id);
      transcriptCompleter.complete('transcript');
      await generation;

      expect(
        fixture.container.read(videoSummaryTaskProvider(fixture.video.id)),
        isNull,
      );
      expect(
        await fixture.db.videoSummariesDao.getSummaryForVideo(fixture.video.id),
        isNull,
      );
      expect(await fixture.audioFile.exists(), isFalse);
      expect(fixture.events.last, 'stop:${fixture.root.path}');
    },
  );

  test('prefers default VTT over localized VTT', () async {
    final fixture = await _SummaryControllerFixture.create();
    addTearDown(fixture.dispose);
    await File(p.join(fixture.root.path, 'video.vtt')).writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
Default subtitle line.
''');
    await File(p.join(fixture.root.path, 'video.en.vtt')).writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
Localized subtitle line.
''');

    await fixture.generate();

    expect(
      fixture.naturalLanguageService.lastTranscript,
      contains('Default subtitle line.'),
    );
    expect(
      fixture.naturalLanguageService.lastTranscript,
      isNot(contains('Localized subtitle line.')),
    );
  });

  test(
    'does not require a whisper model when a VTT transcript is available',
    () async {
      final fixture = await _SummaryControllerFixture.create(
        modelValidation: const SummaryModelValidationResult.invalid(
          'Not configured',
        ),
      );
      addTearDown(fixture.dispose);
      await File(p.join(fixture.root.path, 'video.vtt')).writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
Subtitle transcript can be summarized directly.
''');

      await fixture.generate();

      final state = fixture.container.read(
        videoSummaryTaskProvider(fixture.video.id),
      );
      expect(state?.phase, VideoSummaryTaskPhase.completed);
      expect(fixture.mediaService.extractedPaths, isEmpty);
      expect(fixture.events, [
        'start:${fixture.root.path}',
        'summarize',
        'stop:${fixture.root.path}',
      ]);
    },
  );

  test(
    'requires a whisper model when no VTT transcript is available',
    () async {
      final fixture = await _SummaryControllerFixture.create(
        modelValidation: const SummaryModelValidationResult.invalid(
          'Not configured',
        ),
      );
      addTearDown(fixture.dispose);

      await fixture.generate();

      final state = fixture.container.read(
        videoSummaryTaskProvider(fixture.video.id),
      );
      expect(state?.phase, VideoSummaryTaskPhase.failed);
      expect(
        state?.error.toString(),
        contains('Summary model is not ready: Not configured.'),
      );
      expect(fixture.mediaService.extractedPaths, isEmpty);
    },
  );

  test(
    'falls back to audio extraction when VTT preference is disabled',
    () async {
      final fixture = await _SummaryControllerFixture.create(
        preferVttSubtitles: false,
      );
      addTearDown(fixture.dispose);
      await File(p.join(fixture.root.path, 'video.vtt')).writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
Subtitle should be ignored.
''');

      await fixture.generate();

      expect(fixture.events, [
        'start:${fixture.root.path}',
        'extract:${fixture.video.absolutePath}',
        'transcribe',
        'summarize',
        'stop:${fixture.root.path}',
      ]);
      expect(fixture.naturalLanguageService.lastTranscript, 'transcript');
    },
  );

  test('can override disabled VTT preference for one generation', () async {
    final fixture = await _SummaryControllerFixture.create(
      preferVttSubtitles: false,
    );
    addTearDown(fixture.dispose);
    await File(p.join(fixture.root.path, 'video.vtt')).writeAsString('''
WEBVTT

00:00:00.000 --> 00:00:02.000
Override subtitle should be used.
''');

    await fixture.generate(preferVttSubtitlesOverride: true);

    expect(fixture.mediaService.extractedPaths, isEmpty);
    expect(
      fixture.naturalLanguageService.lastTranscript,
      contains('Override subtitle should be used.'),
    );
    expect((await fixture.readState()).storedStatus, VideoSummaryStatus.fresh);

    final otherModel = File(p.join(fixture.root.path, 'ggml-other.bin'));
    await otherModel.writeAsBytes(const [9, 8, 7]);
    await fixture.container
        .read(settingsProvider.notifier)
        .setLocalSummaryModelPath(otherModel.path);
    fixture.invalidateState();

    expect((await fixture.readState()).storedStatus, VideoSummaryStatus.fresh);
    await fixture.generate();
    expect(fixture.naturalLanguageService.summarizeCount, 1);
  });
}

class _SummaryControllerFixture {
  _SummaryControllerFixture({
    required this.db,
    required this.container,
    required this.root,
    required this.video,
    required this.videoFile,
    required this.mediaService,
    required this.naturalLanguageService,
    required this.audioFile,
    required this.events,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final Directory root;
  final Video video;
  final File videoFile;
  final _FakeMediaService mediaService;
  final _FakeNaturalLanguageService naturalLanguageService;
  final File audioFile;
  final List<String> events;

  static Future<_SummaryControllerFixture> create({
    bool canAccessFolder = true,
    Completer<String>? transcriptCompleter,
    bool preferVttSubtitles = true,
    String summaryApiUrl = 'https://summary.example.test/v1/chat/completions',
    String summaryApiKey = 'sk-test',
    bool failSummary = false,
    SummaryModelValidationResult modelValidation =
        const SummaryModelValidationResult.valid('Ready'),
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
    final libraryAccessService = LibraryAccessService(
      adapter: _FakeLibraryAccessAdapter(
        canAccess: canAccessFolder,
        events: events,
      ),
    );
    final mediaService = _FakeMediaService(
      audioPath: audioFile.path,
      events: events,
    );
    final naturalLanguageService = _FakeNaturalLanguageService(
      events: events,
      transcriptCompleter: transcriptCompleter,
      failSummary: failSummary,
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsProvider.overrideWith(
          () => _FakeSettings(
            modelPath: modelFile.path,
            preferVttSubtitles: preferVttSubtitles,
            summaryApiUrl: summaryApiUrl,
            summaryApiKey: summaryApiKey,
          ),
        ),
        summaryModelValidationProvider.overrideWith(
          (_) async => modelValidation,
        ),
        libraryAccessServiceProvider.overrideWithValue(libraryAccessService),
        mediaServiceProvider.overrideWithValue(mediaService),
        naturalLanguageServiceProvider.overrideWithValue(
          naturalLanguageService,
        ),
      ],
    );

    return _SummaryControllerFixture(
      db: db,
      container: container,
      root: root,
      video: video,
      videoFile: videoFile,
      mediaService: mediaService,
      naturalLanguageService: naturalLanguageService,
      audioFile: audioFile,
      events: events,
    );
  }

  Future<void> generate({
    bool forceRefresh = false,
    bool? preferVttSubtitlesOverride,
  }) {
    return container
        .read(videoSummaryTasksProvider.notifier)
        .generate(
          video,
          forceRefresh: forceRefresh,
          preferVttSubtitlesOverride: preferVttSubtitlesOverride,
        );
  }

  Future<VideoSummaryState> readState() async {
    final provider = videoSummaryStateProvider(video);
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    try {
      return await container.read(provider.future);
    } finally {
      subscription.close();
    }
  }

  void invalidateState() {
    container.invalidate(videoSummaryStateProvider(video));
  }

  Future<void> seedSummary({
    String summaryJson =
        '{"synopsis":"synopsis","highlights":["highlight"],"keywords":["keyword"]}',
    String? transcriptModel,
    String? summaryModel,
  }) async {
    final stat = await videoFile.stat();
    final now = DateTime.now();
    await db.videoSummariesDao.upsertSummary(
      VideoSummariesCompanion.insert(
        videoId: drift.Value(video.id),
        transcriptText: 'transcript',
        summaryJson: summaryJson,
        transcriptModel:
            transcriptModel ??
            transcriptModelNameFromPath(mediaService.modelPath),
        summaryModel:
            summaryModel ??
            summaryModelNameFromApiUrl(
              'https://summary.example.test/v1/chat/completions',
            ),
        sourceVideoSize: stat.size,
        sourceVideoModifiedAt: stat.modified,
        generatedAt: drift.Value(now),
        updatedAt: drift.Value(now),
      ),
    );
  }

  Future<void> waitForEvent(String event) async {
    for (var i = 0; i < 100; i++) {
      if (events.contains(event)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Timed out waiting for $event');
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
  _FakeSettings({
    required this.modelPath,
    required this.preferVttSubtitles,
    required this.summaryApiUrl,
    required this.summaryApiKey,
  });

  final String modelPath;
  final bool preferVttSubtitles;
  final String summaryApiUrl;
  final String summaryApiKey;

  @override
  Future<AppSettings> build() async {
    return AppSettings.defaults.copyWith(
      videoSummary: VideoSummaryConfiguration.resolve(
        modelSourceValue: SummaryModelSourceMode.localFile.value,
        modelPath: modelPath,
        preferVttSubtitles: preferVttSubtitles,
        apiUrl: summaryApiUrl,
        apiKey: summaryApiKey,
      ),
    );
  }
}

class _FakeLibraryAccessAdapter implements LibraryAccessAdapter {
  _FakeLibraryAccessAdapter({required this.canAccess, required this.events});

  final bool canAccess;
  final List<String> events;

  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    events.add('start:$path');
    return canAccess;
  }

  @override
  Future<void> stopAccessing(String path) async {
    events.add('stop:$path');
  }
}

class _FakeMediaService extends MediaService {
  _FakeMediaService({required this.audioPath, required this.events})
    : modelPath = p.join(File(audioPath).parent.path, 'ggml-test.bin');

  final String audioPath;
  final String modelPath;
  final List<String> events;
  final extractedPaths = <String>[];

  @override
  Future<String?> extractTranscriptionAudio(String path) async {
    events.add('extract:$path');
    extractedPaths.add(path);
    final file = File(audioPath);
    if (!await file.exists()) {
      await file.writeAsBytes(const <int>[4, 5, 6]);
    }
    return audioPath;
  }
}

class _FakeNaturalLanguageService extends NaturalLanguageService {
  _FakeNaturalLanguageService({
    required this.events,
    this.transcriptCompleter,
    this.failSummary = false,
  });

  final List<String> events;
  final Completer<String>? transcriptCompleter;
  final bool failSummary;
  String? lastTranscript;
  String? lastApiUrl;
  String? lastApiKey;
  int summarizeCount = 0;

  @override
  Future<String> transcribeAudio({
    required String audioPath,
    required String modelPath,
  }) async {
    events.add('transcribe');
    return transcriptCompleter == null
        ? 'transcript'
        : await transcriptCompleter!.future;
  }

  @override
  Future<StructuredVideoSummary> summarizeTranscript({
    required String title,
    required String metadataJson,
    required String transcript,
    required String apiUrl,
    required String apiKey,
  }) async {
    events.add('summarize');
    summarizeCount += 1;
    if (failSummary) {
      throw StateError('Summary failed.');
    }
    lastTranscript = transcript;
    lastApiUrl = apiUrl;
    lastApiKey = apiKey;
    return StructuredVideoSummary(
      synopsis: 'synopsis',
      highlights: const ['highlight'],
      keywords: const ['keyword'],
    );
  }
}
