import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/video_conversion_controller.dart';
import 'package:movie_manager/logic/video_version_models.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/media_service.dart';
import 'package:movie_manager/services/video_transcoder.dart';
import 'package:movie_manager/services/video_version_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/library_access_test_adapter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('keeps the original and registers the converted version', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final video = await fixture.addVideo('clip.mp4');

    final result = await fixture.controller.enqueue(
      videoIds: [video.id],
      preset: VideoResolutionPreset.hd720,
      keepSource: true,
    );
    expect(result.queued, 1);
    final job = await fixture.waitForFinish(video.id);

    expect(job.status, VideoConversionStatus.completed, reason: job.message);
    final output = p.join(fixture.library.path, 'clip [720p].mp4');
    expect(job.outputPath, output);
    expect(await File(output).exists(), isTrue);
    expect(await File(video.absolutePath).exists(), isTrue);
    expect(await File('$output.part').exists(), isFalse);

    final versions = await fixture.versions(video.id);
    expect(versions, hasLength(2));
    expect(versions.first.path, video.absolutePath);
    expect(versions.first.isPrimary, isTrue);
    expect(versions.first.isOriginal, isTrue);
    expect(versions.last.path, output);
    expect(versions.last.dimensions, const VideoDimensions(1280, 720));
    expect(
      (await fixture.db.videosDao.getVideoById(video.id))!.absolutePath,
      video.absolutePath,
    );

    final arguments = fixture.transcoder.starts.single;
    expect(arguments, contains('h264_videotoolbox'));
    expect(arguments.last, '$output.part');
  });

  test('replaces the original when it is not kept', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final video = await fixture.addVideo('feature.mkv');

    await fixture.controller.enqueue(
      videoIds: [video.id],
      preset: VideoResolutionPreset.sd480,
      keepSource: false,
    );
    final job = await fixture.waitForFinish(video.id);

    expect(job.status, VideoConversionStatus.completed, reason: job.message);
    final output = p.join(fixture.library.path, 'feature.mp4');
    expect(await File(video.absolutePath).exists(), isFalse);
    expect(await File(output).exists(), isTrue);
    final updated = (await fixture.db.videosDao.getVideoById(video.id))!;
    expect(updated.absolutePath, output);
    expect(updated.title, video.title);
    final versions = await fixture.versions(video.id);
    expect(versions.map((version) => version.path), [output]);
    expect(versions.single.isPrimary, isTrue);
  });

  test('falls back to the software encoder', () async {
    final fixture = await _Fixture.create(
      transcoder: _FakeTranscoder(
        failWhen: (args) {
          return args.contains('h264_videotoolbox');
        },
      ),
    );
    addTearDown(fixture.dispose);
    final video = await fixture.addVideo('clip.mp4');

    await fixture.controller.enqueue(
      videoIds: [video.id],
      preset: VideoResolutionPreset.hd720,
      keepSource: true,
    );
    final job = await fixture.waitForFinish(video.id);

    expect(job.status, VideoConversionStatus.completed, reason: job.message);
    expect(fixture.transcoder.starts, hasLength(2));
    expect(fixture.transcoder.starts.last, contains('libx264'));
  });

  test('reports a failure and leaves the original untouched', () async {
    final fixture = await _Fixture.create(
      transcoder: _FakeTranscoder(failWhen: (_) => true),
    );
    addTearDown(fixture.dispose);
    final video = await fixture.addVideo('clip.mp4');

    await fixture.controller.enqueue(
      videoIds: [video.id],
      preset: VideoResolutionPreset.hd720,
      keepSource: false,
    );
    final job = await fixture.waitForFinish(video.id);

    expect(job.status, VideoConversionStatus.failed);
    expect(job.message, contains('Encoder exploded'));
    expect(await File(video.absolutePath).exists(), isTrue);
    expect(
      fixture.library.listSync().map((entity) => p.basename(entity.path)),
      ['clip.mp4'],
    );
    expect(await fixture.versions(video.id), hasLength(1));
  });

  test('cancels a running conversion and removes its partial output', () async {
    final transcoder = _FakeTranscoder(waitForCancel: true);
    final fixture = await _Fixture.create(transcoder: transcoder);
    addTearDown(fixture.dispose);
    final video = await fixture.addVideo('clip.mp4');

    await fixture.controller.enqueue(
      videoIds: [video.id],
      preset: VideoResolutionPreset.hd720,
      keepSource: false,
    );
    await fixture.waitFor(
      () => fixture.state.latestJobFor(video.id)?.percent == 25,
    );
    final running = fixture.state.latestJobFor(video.id)!;
    expect(running.status, VideoConversionStatus.converting);
    expect(fixture.state.footerText(), contains('Converting “clip” to 720p'));

    fixture.controller.cancel(running.id);
    final job = await fixture.waitForFinish(video.id);

    expect(job.status, VideoConversionStatus.cancelled);
    expect(
      fixture.library.listSync().map((entity) => p.basename(entity.path)),
      ['clip.mp4'],
    );
    expect(await File(video.absolutePath).exists(), isTrue);
  });

  test('runs one job at a time and cancels queued jobs', () async {
    final transcoder = _FakeTranscoder(waitForCancel: true);
    final fixture = await _Fixture.create(transcoder: transcoder);
    addTearDown(fixture.dispose);
    final first = await fixture.addVideo('first.mp4');
    final second = await fixture.addVideo('second.mp4');

    await fixture.controller.enqueue(
      videoIds: [first.id, second.id],
      preset: VideoResolutionPreset.hd720,
      keepSource: true,
    );
    await fixture.waitFor(
      () =>
          fixture.state.latestJobFor(first.id)?.status ==
          VideoConversionStatus.converting,
    );
    expect(
      fixture.state.latestJobFor(second.id)?.status,
      VideoConversionStatus.queued,
    );
    expect(fixture.state.footerText(), endsWith('(+1 queued)'));

    fixture.controller.cancel(fixture.state.latestJobFor(second.id)!.id);
    await fixture.controller.cancelForVideos([first.id]);

    expect(
      fixture.state.latestJobFor(first.id)?.status,
      VideoConversionStatus.cancelled,
    );
    expect(
      fixture.state.latestJobFor(second.id)?.status,
      VideoConversionStatus.cancelled,
    );
    expect(transcoder.starts, hasLength(1));

    fixture.controller.clearFinished();
    expect(fixture.state.jobs, isEmpty);
  });

  test('hides private titles in the status line while locked', () {
    const state = VideoConversionState(
      jobs: [
        VideoConversionJob(
          id: 1,
          videoId: 1,
          title: 'secret',
          preset: VideoResolutionPreset.hd720,
          keepSource: true,
          isPrivate: true,
          status: VideoConversionStatus.converting,
          progress: 0.5,
        ),
        VideoConversionJob(
          id: 2,
          videoId: 2,
          title: 'next',
          preset: VideoResolutionPreset.hd720,
          keepSource: true,
        ),
      ],
    );

    expect(
      state.footerText(revealPrivate: false),
      'Converting a private video to 720p: 50% (+1 queued)',
    );
    expect(state.footerText(), 'Converting “secret” to 720p: 50% (+1 queued)');
  });

  test('skips videos that cannot or need not be converted', () async {
    final transcoder = _FakeTranscoder(waitForCancel: true);
    final fixture = await _Fixture.create(transcoder: transcoder);
    addTearDown(fixture.dispose);
    final busy = await fixture.addVideo('busy.mp4');
    final offline = await fixture.addVideo('offline.mp4', isOffline: true);
    final small = await fixture.addVideo(
      'small.mp4',
      dimensions: const VideoDimensions(854, 480),
    );

    await fixture.controller.enqueue(
      videoIds: [busy.id],
      preset: VideoResolutionPreset.hd720,
      keepSource: true,
    );
    final result = await fixture.controller.enqueue(
      videoIds: [busy.id, offline.id, small.id, 999],
      preset: VideoResolutionPreset.hd720,
      keepSource: false,
    );

    expect(result.queued, 0);
    expect(result.skipped, [
      '“busy” is already being converted.',
      '“offline” is offline.',
      '“small” is already 720p or lower.',
      'Video 999 is no longer in the Library.',
    ]);
    expect(result.userMessage, startsWith('No videos queued.'));

    final preferences = await fixture.container.read(
      videoConversionPreferencesProvider.future,
    );
    expect(preferences.preset, VideoResolutionPreset.hd720);
    expect(preferences.keepOriginal, isFalse);

    await fixture.controller.shutdown();
    expect(
      fixture.state.latestJobFor(busy.id)?.status,
      VideoConversionStatus.cancelled,
    );
  });
}

class _Fixture {
  _Fixture._(this.root, this.library, this.db, this.container, this.transcoder);

  final Directory root;
  final Directory library;
  final AppDatabase db;
  final ProviderContainer container;
  final _FakeTranscoder transcoder;
  late final Folder folder;

  static Future<_Fixture> create({_FakeTranscoder? transcoder}) async {
    final root = await Directory.systemTemp.createTemp('mm-conversion-');
    final library = await Directory(p.join(root.path, 'Library')).create();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final fakeTranscoder = transcoder ?? _FakeTranscoder();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: AlwaysAllowedLibraryAccessAdapter()),
        ),
        mediaServiceProvider.overrideWithValue(_FakeMediaService()),
        videoTranscoderProvider.overrideWithValue(fakeTranscoder),
      ],
    );
    final fixture = _Fixture._(root, library, db, container, fakeTranscoder);
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: library.path,
        securityScopedBookmark: drift.Value('bookmark:${library.path}'),
      ),
    );
    fixture.folder = (await db.foldersDao.getFolderById(folderId))!;
    // Keep the controller alive for the whole test.
    container.listen(videoConversionControllerProvider, (_, _) {});
    return fixture;
  }

  VideoConversionController get controller =>
      container.read(videoConversionControllerProvider.notifier);

  VideoConversionState get state =>
      container.read(videoConversionControllerProvider);

  Future<Video> addVideo(
    String fileName, {
    VideoDimensions dimensions = const VideoDimensions(1920, 1080),
    bool isOffline = false,
  }) async {
    final path = p.join(library.path, fileName);
    await File(path).writeAsBytes(List<int>.filled(4096, 1));
    _FakeMediaService.dimensionsByPath[path] = dimensions;
    final id = await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folder.id,
        absolutePath: path,
        title: p.basenameWithoutExtension(fileName),
        duration: const drift.Value(60),
        size: const drift.Value(4096),
        isOffline: drift.Value(isOffline),
        metadataJson: drift.Value(jsonEncode(_metadata(dimensions))),
      ),
    );
    return (await db.videosDao.getVideoById(id))!;
  }

  Future<List<VideoVersionInfo>> versions(int videoId) {
    return container.read(videoVersionServiceProvider).listVersions(videoId);
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var attempt = 0; attempt < 400; attempt++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException(
      'Condition not met: ${state.jobs.map((j) => '${j.title} ${j.status} ${j.message}')}',
    );
  }

  Future<VideoConversionJob> waitForFinish(int videoId) async {
    await waitFor(() {
      final job = state.latestJobFor(videoId);
      return job != null && !job.isActive;
    });
    return state.latestJobFor(videoId)!;
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
    _FakeMediaService.dimensionsByPath.clear();
    await root.delete(recursive: true);
  }
}

Map<String, dynamic> _metadata(VideoDimensions dimensions) => {
  'duration': 60.0,
  'bitrate': '8000000',
  'raw': {
    'streams': [
      {
        'index': 0,
        'codec_type': 'video',
        'codec_name': 'h264',
        'width': dimensions.width,
        'height': dimensions.height,
      },
      {'index': 1, 'codec_type': 'audio', 'codec_name': 'aac', 'channels': 2},
    ],
  },
};

/// ffprobe stand-in: sources report their registered size; transcoder output
/// reports the size the fake transcoder wrote into it.
class _FakeMediaService extends MediaService {
  static final dimensionsByPath = <String, VideoDimensions>{};

  @override
  Future<Map<String, dynamic>> getMetadata(String path) async {
    final known = dimensionsByPath[path];
    if (known != null) return _metadata(known);
    final file = File(path);
    if (!await file.exists()) return {};
    final contents = await file.readAsString();
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(contents.trim());
    if (match == null) return {};
    return _metadata(
      VideoDimensions(int.parse(match.group(1)!), int.parse(match.group(2)!)),
    );
  }
}

class _FakeTranscoder implements VideoTranscoder {
  _FakeTranscoder({this.failWhen, this.waitForCancel = false});

  final bool Function(List<String> arguments)? failWhen;
  final bool waitForCancel;
  final starts = <List<String>>[];

  @override
  VideoTranscodeTask start(
    List<String> arguments, {
    void Function(Duration processed)? onProgress,
  }) {
    starts.add(arguments);
    final task = _FakeTask();
    unawaited(() async {
      await Future<void>.delayed(Duration.zero);
      if (failWhen?.call(arguments) ?? false) {
        task.finish(
          const VideoTranscodeResult(
            VideoTranscodeStatus.failed,
            errorMessage: 'Encoder exploded',
          ),
        );
        return;
      }
      final output = File(arguments.last);
      await output.writeAsString(_outputSize(arguments));
      onProgress?.call(const Duration(seconds: 15));
      if (waitForCancel) {
        await task.cancelled.future;
        task.finish(const VideoTranscodeResult(VideoTranscodeStatus.cancelled));
        return;
      }
      onProgress?.call(const Duration(seconds: 60));
      task.finish(const VideoTranscodeResult(VideoTranscodeStatus.succeeded));
    }());
    return task;
  }

  /// Output size implied by the scale filter's preset box (landscape input).
  String _outputSize(List<String> arguments) {
    final filter = arguments[arguments.indexOf('-vf') + 1];
    final match = RegExp(r'gte\(iw,ih\),(\d+),(\d+)\)').firstMatch(filter)!;
    return '${match.group(1)}x${match.group(2)}';
  }
}

class _FakeTask implements VideoTranscodeTask {
  final _result = Completer<VideoTranscodeResult>();
  final cancelled = Completer<void>();

  void finish(VideoTranscodeResult result) {
    if (!_result.isCompleted) _result.complete(result);
  }

  @override
  Future<VideoTranscodeResult> get result => _result.future;

  @override
  Future<void> cancel() async {
    if (!cancelled.isCompleted) cancelled.complete();
  }
}
