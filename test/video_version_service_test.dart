import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/logic/video_version_models.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/media_service.dart';
import 'package:movie_manager/services/video_version_service.dart';
import 'package:path/path.dart' as p;

import 'support/library_access_test_adapter.dart';

void main() {
  group('listVersions', () {
    test('an unconverted video has one implicit primary version', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);

      final versions = await f.service.listVersions(video.id);

      expect(versions, hasLength(1));
      final only = versions.single;
      expect(only.id, isNull);
      expect(only.isPrimary, isTrue);
      expect(only.isOriginal, isTrue);
      expect(only.dimensions, const VideoDimensions(1920, 1080));
      expect(only.durationSeconds, 100);
      expect(only.videoCodec, 'h264');
      expect(await f.service.listVersions(video.id + 99), isEmpty);
    });

    test('orders primary first, then quality, then newest', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1280, height: 720);
      await f.addVersionRow(video, video.absolutePath, 1280, 720);
      await f.addVersionRow(
        video,
        f.path('Movie [1080p].mp4'),
        1920,
        1080,
        isOriginal: true,
        createdAt: DateTime(2020),
      );
      await f.addVersionRow(
        video,
        f.path('Movie [480p].mp4'),
        854,
        480,
        createdAt: DateTime(2021),
      );
      await f.addVersionRow(
        video,
        f.path('Movie [480p] (2).mp4'),
        854,
        480,
        createdAt: DateTime(2022),
      );
      await f.addVersionRow(video, f.path('Movie unknown.mp4'), null, null);

      final names = (await f.service.listVersions(
        video.id,
      )).map((v) => v.fileName).toList();

      expect(names, [
        'Movie.mp4',
        'Movie [1080p].mp4',
        'Movie [480p] (2).mp4',
        'Movie [480p].mp4',
        'Movie unknown.mp4',
      ]);
    });

    test('synthesizes a missing primary row', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1280, height: 720);
      await f.addVersionRow(
        video,
        f.path('Movie [480p].mp4'),
        854,
        480,
        isOriginal: true,
      );

      final versions = await f.service.listVersions(video.id);

      expect(versions.first.path, video.absolutePath);
      expect(versions.first.isPrimary, isTrue);
      expect(versions.first.id, isNull);
      expect(versions.first.isOriginal, isFalse);
      expect(versions, hasLength(2));
    });

    test('videoVersionsProvider re-emits on changes', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);
      final emissions = <List<VideoVersionInfo>>[];
      final subscription = f.service
          .watchVersions(video.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await _until(() => emissions.isNotEmpty);
      expect(emissions.last, hasLength(1));

      await f.addVersionRow(video, video.absolutePath, 1920, 1080);
      await f.addVersionRow(video, f.path('Movie [720p].mp4'), 1280, 720);
      await _until(() => emissions.last.length == 2);

      await f.db.videosDao.deleteVideo(video.id);
      await _until(() => emissions.last.isEmpty);
    });
  });

  group('planConversion', () {
    test('names keep-mode output and numbers collisions', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);

      var plan = await f.plan(video, VideoResolutionPreset.hd720);
      expect(plan.outputPath, f.path('Movie [720p].mp4'));
      expect(plan.temporaryPath, '${f.path('Movie [720p].mp4')}.part');
      expect(plan.source.path, video.absolutePath);
      expect(plan.libraryAccess.path, f.root.path);
      expect(plan.libraryAccess.bookmark, 'bookmark');
      expect(plan.folderId, video.folderId);

      // Taken on disk.
      await File(f.path('Movie [720p].mp4')).writeAsBytes([1]);
      plan = await f.plan(video, VideoResolutionPreset.hd720);
      expect(plan.outputPath, f.path('Movie [720p] (2).mp4'));

      // Taken in the catalog only.
      await f.addVersionRow(video, video.absolutePath, 1920, 1080);
      await f.addVersionRow(video, f.path('Movie [720p] (2).mp4'), 1280, 720);
      plan = await f.plan(video, VideoResolutionPreset.hd720);
      expect(plan.outputPath, f.path('Movie [720p] (3).mp4'));
    });

    test('strips an existing version suffix from the stem', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo(
        'Rocky (1976) [1080p] (2).mp4',
        width: 1920,
        height: 1080,
      );

      final plan = await f.plan(video, VideoResolutionPreset.hd720);
      expect(plan.outputPath, f.path('Rocky (1976) [720p].mp4'));
      expect(videoVersionBaseStem('/x/Rocky (1976).mp4'), 'Rocky (1976)');
    });

    test('replace mode prefers in-place or the plain stem', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final mp4 = await f.addVideo('Movie.mp4', width: 1920, height: 1080);
      final mkv = await f.addVideo('Show.mkv', width: 1920, height: 1080);

      var plan = await f.plan(mp4, VideoResolutionPreset.hd720, keep: false);
      expect(plan.outputPath, mp4.absolutePath);

      plan = await f.plan(mkv, VideoResolutionPreset.hd720, keep: false);
      expect(plan.outputPath, f.path('Show.mp4'));

      await File(f.path('Show.mp4')).writeAsBytes([1]);
      plan = await f.plan(mkv, VideoResolutionPreset.hd720, keep: false);
      expect(plan.outputPath, f.path('Show [720p].mp4'));
    });

    test('picks the highest-quality source, preferring the original', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1280, height: 720);
      await f.addVersionRow(video, video.absolutePath, 1280, 720);
      final original = f.path('Movie.mkv');
      await File(original).writeAsBytes([1, 2]);
      await f.addVersionRow(video, original, 1920, 1080, isOriginal: true);
      final copy = f.path('Movie copy.mkv');
      await File(copy).writeAsBytes([1, 2]);
      await f.addVersionRow(video, copy, 1920, 1080);

      final plan = await f.plan(video, VideoResolutionPreset.sd480);
      expect(plan.source.path, original);
      expect(plan.outputPath, f.path('Movie [480p].mp4'));
    });

    test('rejects sources already at or below the preset', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1280, height: 720);

      await expectLater(
        f.plan(video, VideoResolutionPreset.hd720),
        throwsA(
          isA<VideoVersionException>().having(
            (e) => e.message,
            'message',
            '"Movie" is already 720p or lower.',
          ),
        ),
      );
    });

    test('rejects offline, missing and inaccessible videos', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);

      await f.db.videosDao.updateVideoStatus(video.id, true);
      await expectLater(
        f.plan(video, VideoResolutionPreset.hd720),
        throwsA(isA<VideoVersionException>()),
      );
      await f.db.videosDao.updateVideoStatus(video.id, false);

      await File(video.absolutePath).delete();
      await expectLater(
        f.plan(video, VideoResolutionPreset.hd720),
        throwsA(isA<VideoVersionException>()),
      );

      await f.db.foldersDao.updateFolderBookmark(video.folderId, null);
      await expectLater(
        f.plan(video, VideoResolutionPreset.hd720),
        throwsA(
          isA<VideoVersionException>().having(
            (e) => e.message,
            'message',
            contains(libraryAccessRepairMessage),
          ),
        ),
      );

      await expectLater(
        f.service.planConversion(
          videoId: 999,
          preset: VideoResolutionPreset.hd720,
          keepSource: true,
        ),
        throwsA(isA<VideoVersionException>()),
      );
    });
  });

  group('finalizeConversion', () {
    test('keep mode registers both files and leaves the primary', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);
      final plan = await f.plan(video, VideoResolutionPreset.hd720);
      await f.transcode(plan, width: 1280, height: 720, duration: 100.4);

      final outcome = await f.service.finalizeConversion(
        plan,
        expectedDurationSeconds: 100,
      );

      expect(outcome.replacedSource, isFalse);
      expect(outcome.warnings, isEmpty);
      expect(outcome.version.path, plan.outputPath);
      expect(outcome.version.isPrimary, isFalse);
      expect(outcome.version.isOriginal, isFalse);
      expect(outcome.version.dimensions, const VideoDimensions(1280, 720));
      expect(outcome.version.durationSeconds, 100);
      expect(outcome.version.sizeBytes, 5);
      expect(await File(plan.outputPath).exists(), isTrue);
      expect(await File(plan.temporaryPath).exists(), isFalse);
      expect(await File(video.absolutePath).exists(), isTrue);

      final current = (await f.db.videosDao.getVideoById(video.id))!;
      expect(current.absolutePath, video.absolutePath);
      expect(current.metadataJson, video.metadataJson);
      final rows = await f.db.videoVersionsDao.getVersionsForVideo(video.id);
      expect(rows, hasLength(2));
      final primaryRow = rows.firstWhere(
        (r) => r.absolutePath == video.absolutePath,
      );
      expect(primaryRow.isOriginal, isTrue);
      expect(primaryRow.width, 1920);
      final versions = await f.service.listVersions(video.id);
      expect(versions.map((v) => v.path), [
        video.absolutePath,
        plan.outputPath,
      ]);
    });

    test(
      'replace in place swaps the file and rebinds a fresh summary',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);
        await f.addFreshSummary(video);
        final plan = await f.plan(
          video,
          VideoResolutionPreset.hd720,
          keep: false,
        );
        expect(plan.outputPath, video.absolutePath);
        await f.transcode(plan, width: 1280, height: 720, duration: 99);

        final outcome = await f.service.finalizeConversion(
          plan,
          expectedDurationSeconds: 100,
        );

        expect(outcome.replacedSource, isTrue);
        expect(outcome.version.path, video.absolutePath);
        expect(outcome.version.isPrimary, isTrue);
        expect(await File(video.absolutePath).readAsBytes(), _convertedBytes);
        expect(await File(plan.temporaryPath).exists(), isFalse);

        final current = (await f.db.videosDao.getVideoById(video.id))!;
        expect(current.absolutePath, video.absolutePath);
        expect(current.size, _convertedBytes.length);
        expect(current.duration, 99);
        expect(
          videoDimensionsFromMetadataJson(current.metadataJson),
          const VideoDimensions(1280, 720),
        );
        expect(current.title, video.title);
        expect(current.thumbnailPath, video.thumbnailPath);
        final rows = await f.db.videoVersionsDao.getVersionsForVideo(video.id);
        expect(rows.single.isOriginal, isFalse);
        expect(rows.single.width, 1280);

        final summary = (await f.db.videoSummariesDao.getSummaryForVideo(
          video.id,
        ))!;
        final stat = await File(video.absolutePath).stat();
        expect(summary.sourceVideoSize, stat.size);
        expect(
          summary.sourceVideoModifiedAt.millisecondsSinceEpoch ~/ 1000,
          stat.modified.millisecondsSinceEpoch ~/ 1000,
        );
      },
    );

    test('replace with a new path deletes the source and switches', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mkv', width: 1920, height: 1080);
      await f.addFreshSummary(video);
      final plan = await f.plan(
        video,
        VideoResolutionPreset.hd720,
        keep: false,
      );
      expect(plan.outputPath, f.path('Movie.mp4'));
      await f.transcode(plan, width: 1280, height: 720, duration: 100);

      final outcome = await f.service.finalizeConversion(
        plan,
        expectedDurationSeconds: 100,
      );

      expect(outcome.replacedSource, isTrue);
      expect(outcome.warnings, isEmpty);
      expect(await File(video.absolutePath).exists(), isFalse);
      expect(await File(f.path('Movie.mp4')).exists(), isTrue);
      final current = (await f.db.videosDao.getVideoById(video.id))!;
      expect(current.absolutePath, f.path('Movie.mp4'));
      expect(current.isFavorite, isTrue);
      final rows = await f.db.videoVersionsDao.getVersionsForVideo(video.id);
      expect(rows.map((r) => r.absolutePath), [f.path('Movie.mp4')]);
      final summary = (await f.db.videoSummariesDao.getSummaryForVideo(
        video.id,
      ))!;
      expect(summary.sourceVideoSize, _convertedBytes.length);
    });

    test('replace leaves a stale summary alone', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mkv', width: 1920, height: 1080);
      await f.addFreshSummary(video, size: 1234);
      final plan = await f.plan(
        video,
        VideoResolutionPreset.hd720,
        keep: false,
      );
      await f.transcode(plan, width: 1280, height: 720, duration: 100);

      await f.service.finalizeConversion(plan, expectedDurationSeconds: 100);

      final summary = (await f.db.videoSummariesDao.getSummaryForVideo(
        video.id,
      ))!;
      expect(summary.sourceVideoSize, 1234);
    });

    test('a failed verification leaves source and catalog untouched', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mkv', width: 1920, height: 1080);

      for (final (width, height, duration, message) in [
        (1920, 1080, 100.0, 'is 1080p'),
        (1280, 720, 80.0, 's long'),
        (0, 0, 100.0, 'no readable video stream'),
      ]) {
        final plan = await f.plan(
          video,
          VideoResolutionPreset.hd720,
          keep: false,
        );
        await f.transcode(
          plan,
          width: width,
          height: height,
          duration: duration,
        );
        await expectLater(
          f.service.finalizeConversion(plan, expectedDurationSeconds: 100),
          throwsA(
            isA<VideoVersionException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
        expect(await File(plan.temporaryPath).exists(), isFalse);
        expect(await File(plan.outputPath).exists(), isFalse);
      }

      expect(await File(video.absolutePath).exists(), isTrue);
      final current = (await f.db.videosDao.getVideoById(video.id))!;
      expect(current.absolutePath, video.absolutePath);
      expect(await f.db.videoVersionsDao.getAllVersions(), isEmpty);
    });

    test('discards output when the video was deleted meanwhile', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);
      final plan = await f.plan(video, VideoResolutionPreset.hd720);
      await f.transcode(plan, width: 1280, height: 720, duration: 100);
      await f.db.videosDao.deleteVideo(video.id);

      await expectLater(
        f.service.finalizeConversion(plan, expectedDurationSeconds: 100),
        throwsA(
          isA<VideoVersionException>().having(
            (e) => e.message,
            'message',
            contains('was moved, deleted, or changed during conversion'),
          ),
        ),
      );
      expect(await File(plan.temporaryPath).exists(), isFalse);
      expect(await File(plan.outputPath).exists(), isFalse);
      expect(await f.db.videoVersionsDao.getAllVersions(), isEmpty);
    });

    test('picks a free name if the output path was taken meanwhile', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);
      final plan = await f.plan(video, VideoResolutionPreset.hd720);
      await f.transcode(plan, width: 1280, height: 720, duration: 100);
      await File(plan.outputPath).writeAsBytes([7]);

      final outcome = await f.service.finalizeConversion(
        plan,
        expectedDurationSeconds: 100,
      );

      expect(outcome.version.path, f.path('Movie [720p] (2).mp4'));
      expect(await File(plan.outputPath).readAsBytes(), [7]);
    });

    test('waits for a running scan before touching the catalog', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);
      final plan = await f.plan(video, VideoResolutionPreset.hd720);
      await f.transcode(plan, width: 1280, height: 720, duration: 100);
      final operation = f.container.read(
        libraryOperationControllerProvider.notifier,
      );
      expect(operation.beginScan(), isTrue);

      var completed = false;
      final pending = f.service
          .finalizeConversion(plan, expectedDurationSeconds: 100)
          .whenComplete(() => completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(completed, isFalse);
      expect(await File(plan.temporaryPath).exists(), isTrue);
      expect(await f.db.videoVersionsDao.getAllVersions(), isEmpty);

      operation.endScan();
      final outcome = await pending;
      expect(outcome.version.path, plan.outputPath);
      expect(
        f.container.read(libraryOperationControllerProvider).isBusy,
        false,
      );
      // The versioning operation was released.
      expect(operation.beginMove(), isTrue);
      operation.endMove();
    });
  });

  group('deleteVersions', () {
    test('promotes another version when the primary is deleted', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addConvertedVideo(f);
      await f.addFreshSummary(video);

      final result = await f.service.deleteVersions(
        videoId: video.id,
        paths: [video.absolutePath, f.path('Unknown.mp4')],
      );

      expect(result.deletedPaths, [video.absolutePath]);
      expect(result.failures.keys, [f.path('Unknown.mp4')]);
      expect(result.newPrimaryPath, f.path('Movie [720p].mp4'));
      expect(await File(video.absolutePath).exists(), isFalse);
      final current = (await f.db.videosDao.getVideoById(video.id))!;
      expect(current.absolutePath, f.path('Movie [720p].mp4'));
      expect(current.size, 4);
      expect(
        videoDimensionsFromMetadataJson(current.metadataJson),
        const VideoDimensions(1280, 720),
      );
      final rows = await f.db.videoVersionsDao.getVersionsForVideo(video.id);
      expect(rows.map((r) => r.absolutePath), [f.path('Movie [720p].mp4')]);
      final summary = (await f.db.videoSummariesDao.getSummaryForVideo(
        video.id,
      ))!;
      expect(summary.sourceVideoSize, 4);
    });

    test('prefers the original when promoting', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addConvertedVideo(f, primaryIsOriginal: false);
      final original = f.path('Movie.mkv');
      await File(original).writeAsBytes([1]);
      await f.addVersionRow(video, original, 1920, 1080, isOriginal: true);

      final result = await f.service.deleteVersions(
        videoId: video.id,
        paths: [video.absolutePath],
      );
      expect(result.newPrimaryPath, original);
    });

    test('refuses to delete every version', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addConvertedVideo(f);

      await expectLater(
        f.service.deleteVersions(
          videoId: video.id,
          paths: [video.absolutePath, f.path('Movie [720p].mp4')],
        ),
        throwsA(
          isA<VideoVersionException>().having(
            (e) => e.message,
            'message',
            startsWith('Keep at least one version.'),
          ),
        ),
      );
      final unconverted = await f.addVideo('Solo.mp4', width: 640, height: 360);
      await expectLater(
        f.service.deleteVersions(
          videoId: unconverted.id,
          paths: [unconverted.absolutePath],
        ),
        throwsA(isA<VideoVersionException>()),
      );
      expect(await File(video.absolutePath).exists(), isTrue);
      expect(await File(unconverted.absolutePath).exists(), isTrue);
    });

    test(
      'deletes a non-primary version and tolerates a missing file',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        final video = await f.addConvertedVideo(f);
        await File(f.path('Movie [720p].mp4')).delete();

        final result = await f.service.deleteVersions(
          videoId: video.id,
          paths: [f.path('Movie [720p].mp4')],
        );

        expect(result.deletedPaths, [f.path('Movie [720p].mp4')]);
        expect(result.newPrimaryPath, isNull);
        final versions = await f.service.listVersions(video.id);
        expect(versions.single.path, video.absolutePath);
      },
    );
  });

  group('setPrimaryVersion', () {
    test('switches the primary file and rebinds the summary', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addConvertedVideo(f);
      await f.addFreshSummary(video);

      await f.service.setPrimaryVersion(
        videoId: video.id,
        path: f.path('Movie [720p].mp4'),
      );

      final current = (await f.db.videosDao.getVideoById(video.id))!;
      expect(current.absolutePath, f.path('Movie [720p].mp4'));
      expect(current.duration, 100);
      expect(current.title, 'Movie');
      final versions = await f.service.listVersions(video.id);
      expect(versions.first.path, f.path('Movie [720p].mp4'));
      expect(versions.last.isOriginal, isTrue);
      final summary = (await f.db.videoSummariesDao.getSummaryForVideo(
        video.id,
      ))!;
      expect(summary.sourceVideoSize, 4);

      await expectLater(
        f.service.setPrimaryVersion(
          videoId: video.id,
          path: f.path('Other.mp4'),
        ),
        throwsA(isA<VideoVersionException>()),
      );
    });

    test('is a no-op for the primary of an unconverted video', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final video = await f.addVideo('Movie.mp4', width: 1920, height: 1080);

      await f.service.setPrimaryVersion(
        videoId: video.id,
        path: video.absolutePath,
      );
      expect(await f.db.videoVersionsDao.getAllVersions(), isEmpty);
    });
  });
}

final _convertedBytes = [9, 9, 9, 9, 9];

Map<String, dynamic> _metadata(int width, int height, double duration) {
  return {
    'duration': duration,
    'bitrate': null,
    'raw': {
      'streams': [
        if (width > 0)
          {
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': width,
            'height': height,
          },
        {'codec_type': 'audio', 'codec_name': 'aac'},
      ],
      'format': {'duration': '$duration'},
    },
  };
}

class _FakeMediaService extends MediaService {
  final Map<String, Map<String, dynamic>> metadataByPath = {};

  @override
  Future<Map<String, dynamic>> getMetadata(String path) async =>
      metadataByPath[path] ?? const {};
}

class _Fixture {
  _Fixture({
    required this.db,
    required this.root,
    required this.folderId,
    required this.container,
    required this.media,
    required this.service,
  });

  final AppDatabase db;
  final Directory root;
  final int folderId;
  final ProviderContainer container;
  final _FakeMediaService media;
  final VideoVersionService service;

  static Future<_Fixture> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('video-version-test');
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    final container = ProviderContainer();
    final media = _FakeMediaService();
    final operation = container.read(
      libraryOperationControllerProvider.notifier,
    );
    final service = VideoVersionService(
      database: db,
      libraryAccessService: LibraryAccessService(
        adapter: AlwaysAllowedLibraryAccessAdapter(),
      ),
      mediaService: media,
      runExclusive: operation.runVersioning,
    );
    return _Fixture(
      db: db,
      root: root,
      folderId: folderId,
      container: container,
      media: media,
      service: service,
    );
  }

  String path(String name) => p.join(root.path, name);

  Future<Video> addVideo(
    String name, {
    required int width,
    required int height,
  }) async {
    final file = File(path(name));
    await file.writeAsBytes(const [1, 2, 3]);
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: file.path,
        title: p.basenameWithoutExtension(name).split(' [').first,
        duration: const drift.Value(100),
        size: const drift.Value(3),
        isFavorite: const drift.Value(true),
        metadataJson: drift.Value(jsonEncode(_metadata(width, height, 100))),
      ),
    );
    return (await db.videosDao.getVideoByPath(file.path))!;
  }

  Future<void> addVersionRow(
    Video video,
    String path,
    int? width,
    int? height, {
    bool isOriginal = false,
    DateTime? createdAt,
  }) async {
    await db.videoVersionsDao.insertVersion(
      VideoVersionsCompanion.insert(
        videoId: video.id,
        absolutePath: path,
        width: drift.Value(width),
        height: drift.Value(height),
        duration: const drift.Value(100),
        size: const drift.Value(3),
        metadataJson: drift.Value(
          jsonEncode(_metadata(width ?? 0, height ?? 0, 100)),
        ),
        isOriginal: drift.Value(isOriginal),
        createdAt: createdAt == null
            ? const drift.Value.absent()
            : drift.Value(createdAt),
      ),
    );
  }

  /// "Movie.mp4" (1080p, primary) plus "Movie [720p].mp4" (4 bytes).
  Future<Video> addConvertedVideo(
    _Fixture f, {
    bool primaryIsOriginal = true,
  }) async {
    final video = await addVideo('Movie.mp4', width: 1920, height: 1080);
    await addVersionRow(
      video,
      video.absolutePath,
      1920,
      1080,
      isOriginal: primaryIsOriginal,
    );
    final version = File(path('Movie [720p].mp4'));
    await version.writeAsBytes(const [5, 6, 7, 8]);
    await addVersionRow(video, version.path, 1280, 720);
    return video;
  }

  Future<void> addFreshSummary(Video video, {int? size}) async {
    final stat = await File(video.absolutePath).stat();
    await db.videoSummariesDao.upsertSummary(
      VideoSummariesCompanion.insert(
        videoId: drift.Value(video.id),
        transcriptText: 'transcript',
        summaryJson: '{}',
        transcriptModel: 'a',
        summaryModel: 'b',
        sourceVideoSize: size ?? stat.size,
        sourceVideoModifiedAt: stat.modified,
      ),
    );
  }

  Future<VideoConversionPlan> plan(
    Video video,
    VideoResolutionPreset preset, {
    bool keep = true,
  }) {
    return service.planConversion(
      videoId: video.id,
      preset: preset,
      keepSource: keep,
    );
  }

  Future<void> transcode(
    VideoConversionPlan plan, {
    required int width,
    required int height,
    required double duration,
  }) async {
    await File(plan.temporaryPath).writeAsBytes(_convertedBytes);
    media.metadataByPath[plan.temporaryPath] = _metadata(
      width,
      height,
      duration,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Condition not met.');
}
