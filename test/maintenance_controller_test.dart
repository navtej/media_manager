import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/maintenance_controller.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/services/data_compaction_service.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/media_deletion_service.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:movie_manager/services/thumbnail_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'compactDataFolder owns cleanup lock until compaction completes',
    () async {
      final started = Completer<void>();
      final completion = Completer<DataCompactionResult>();
      final fixture = await _MaintenanceFixture.create(
        dataCompactionRunner: () {
          started.complete();
          return completion.future;
        },
      );
      addTearDown(fixture.dispose);

      final future = fixture.container
          .read(maintenanceControllerProvider.notifier)
          .compactDataFolder();
      await started.future;

      expect(
        fixture.container.read(libraryOperationControllerProvider).isCleaning,
        isTrue,
      );
      expect(
        fixture.container
            .read(libraryOperationControllerProvider.notifier)
            .beginScan(),
        isFalse,
      );

      completion.complete(
        const DataCompactionResult(
          status: DataCompactionStatus.completed,
          beforeBytes: 200,
          afterBytes: 100,
          removedThumbnailCount: 2,
        ),
      );

      expect((await future).status, DataCompactionStatus.completed);
      expect(
        fixture.container.read(libraryOperationControllerProvider).isBusy,
        isFalse,
      );
    },
  );

  test('compactDataFolder rejects a busy Library operation', () async {
    var calls = 0;
    final fixture = await _MaintenanceFixture.create(
      dataCompactionRunner: () async {
        calls += 1;
        return const DataCompactionResult(
          status: DataCompactionStatus.completed,
          beforeBytes: 1,
          afterBytes: 1,
          removedThumbnailCount: 0,
        );
      },
    );
    addTearDown(fixture.dispose);
    fixture.container
        .read(libraryOperationControllerProvider.notifier)
        .beginMove();

    final result = await fixture.container
        .read(maintenanceControllerProvider.notifier)
        .compactDataFolder();

    expect(result.status, DataCompactionStatus.busy);
    expect(calls, 0);
    expect(
      fixture.container.read(libraryOperationControllerProvider).isMoving,
      isTrue,
    );
  });

  test(
    'compactDataFolder releases cleanup lock when the runner throws',
    () async {
      final fixture = await _MaintenanceFixture.create(
        dataCompactionRunner: () async => throw StateError('fixture failure'),
      );
      addTearDown(fixture.dispose);

      final result = await fixture.container
          .read(maintenanceControllerProvider.notifier)
          .compactDataFolder();

      expect(result.status, DataCompactionStatus.failed);
      expect(result.errorMessage, 'Failed while compacting the data folder.');
      expect(
        fixture.container.read(libraryOperationControllerProvider).isBusy,
        isFalse,
      );
    },
  );

  test('deleteVideo starts folder access before deleting media', () async {
    final fixture = await _MaintenanceFixture.create();
    addTearDown(fixture.dispose);

    await fixture.container
        .read(maintenanceControllerProvider.notifier)
        .deleteVideo(fixture.video.id);

    expect(fixture.events, [
      'start:${fixture.root.path}:bookmark',
      'stop:${fixture.root.path}',
    ]);
    expect(await fixture.videoFile.exists(), isFalse);
    expect(await fixture.subtitleFile.exists(), isFalse);
    expect(await fixture.db.videosDao.getVideoById(fixture.video.id), isNull);
  });

  test('deleteVideos deletes selected media files and sidecars', () async {
    final fixture = await _MaintenanceFixture.create();
    addTearDown(fixture.dispose);
    final second = await fixture.addVideo('second.mp4', '.srt');

    await fixture.container
        .read(maintenanceControllerProvider.notifier)
        .deleteVideos([fixture.video.id, second.video.id]);

    expect(fixture.events, [
      'start:${fixture.root.path}:bookmark',
      'stop:${fixture.root.path}',
      'start:${fixture.root.path}:bookmark',
      'stop:${fixture.root.path}',
    ]);
    expect(await fixture.videoFile.exists(), isFalse);
    expect(await fixture.subtitleFile.exists(), isFalse);
    expect(await second.videoFile.exists(), isFalse);
    expect(await second.subtitleFile.exists(), isFalse);
    expect(await fixture.db.videosDao.getVideoById(fixture.video.id), isNull);
    expect(await fixture.db.videosDao.getVideoById(second.video.id), isNull);
  });

  test(
    'deleteVideo keeps database row when folder access needs repair',
    () async {
      final fixture = await _MaintenanceFixture.create(canAccessFolder: false);
      addTearDown(fixture.dispose);

      final result = await fixture.container
          .read(maintenanceControllerProvider.notifier)
          .deleteVideo(fixture.video.id);

      expect(fixture.events, ['start:${fixture.root.path}:bookmark']);
      expect(await fixture.videoFile.exists(), isTrue);
      expect(
        await fixture.db.videosDao.getVideoById(fixture.video.id),
        isNotNull,
      );
      expect(result.status, MediaDeletionStatus.needsRepair);
      expect(result.userMessage, contains('Reselect this folder in Settings'));
    },
  );

  test(
    'deleteVideos keeps database rows when folder access needs repair',
    () async {
      final fixture = await _MaintenanceFixture.create(canAccessFolder: false);
      addTearDown(fixture.dispose);

      final result = await fixture.container
          .read(maintenanceControllerProvider.notifier)
          .deleteVideos([fixture.video.id]);

      expect(fixture.events, ['start:${fixture.root.path}:bookmark']);
      expect(await fixture.videoFile.exists(), isTrue);
      expect(
        await fixture.db.videosDao.getVideoById(fixture.video.id),
        isNotNull,
      );
      expect(result!.results.single.status, MediaDeletionStatus.needsRepair);
      expect(result.userMessage, contains('Reselect this folder in Settings'));
    },
  );

  test('removeFolder deletes only catalog records and leaves files', () async {
    final fixture = await _MaintenanceFixture.create();
    addTearDown(fixture.dispose);

    await fixture.container
        .read(maintenanceControllerProvider.notifier)
        .removeFolder(fixture.video.folderId);

    expect(await fixture.videoFile.exists(), isTrue);
    expect(await fixture.subtitleFile.exists(), isTrue);
    expect(await fixture.thumbnailFile.exists(), isFalse);
    expect(
      await fixture.db.foldersDao.getFolderById(fixture.video.folderId),
      isNull,
    );
    expect(await fixture.db.videosDao.getVideoById(fixture.video.id), isNull);
  });

  test('cancelled authentication blocks every private bulk action', () async {
    final fixture = await _MaintenanceFixture.create(
      isPrivate: true,
      authenticationResult: false,
    );
    addTearDown(fixture.dispose);
    await fixture.db.tagsDao.insertTag(
      TagsCompanion.insert(videoId: fixture.video.id, tagText: 'private-tag'),
    );
    final controller = fixture.container.read(
      maintenanceControllerProvider.notifier,
    );

    final favoriteRan = await controller.setFavoriteForVideos([
      fixture.video.id,
    ], true);
    final clearTagsRan = await controller.clearTagsForVideos([
      fixture.video.id,
    ]);
    final deletionResult = await controller.deleteVideos([fixture.video.id]);

    expect(favoriteRan, isFalse);
    expect(clearTagsRan, isFalse);
    expect(deletionResult, isNull);
    expect(fixture.auth.attempts, 3);
    expect(
      (await fixture.db.videosDao.getVideoById(fixture.video.id))!.isFavorite,
      isFalse,
    );
    expect(
      await fixture.db.tagsDao.getTagsForVideo(fixture.video.id),
      hasLength(1),
    );
    expect(await fixture.videoFile.exists(), isTrue);
    expect(fixture.events, isEmpty);
  });
}

class _MaintenanceFixture {
  const _MaintenanceFixture({
    required this.db,
    required this.container,
    required this.root,
    required this.videoFile,
    required this.subtitleFile,
    required this.thumbnailFile,
    required this.video,
    required this.events,
    required this.auth,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final Directory root;
  final File videoFile;
  final File subtitleFile;
  final File thumbnailFile;
  final Video video;
  final List<String> events;
  final _FakePrivateLibraryAuthService auth;

  static Future<_MaintenanceFixture> create({
    bool canAccessFolder = true,
    bool isPrivate = false,
    bool authenticationResult = true,
    DataCompactionRunner? dataCompactionRunner,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'maintenance-controller-test',
    );
    final videoFile = File(p.join(root.path, 'video.mp4'));
    await videoFile.writeAsBytes(const <int>[1, 2, 3]);
    final subtitleFile = File(p.join(root.path, 'video.en.vtt'));
    await subtitleFile.writeAsString('WEBVTT');
    final supportDirectory = await Directory(
      p.join(root.path, 'application-support'),
    ).create();
    final thumbnailService = ThumbnailService(
      applicationSupportDirectory: () async => supportDirectory,
    );
    final thumbnailFile = File(
      await thumbnailService.saveThumbnail('video.jpg', const [4, 5, 6]),
    );

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
        isPrivate: drift.Value(isPrivate),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: videoFile.path,
        title: 'video',
        thumbnailPath: drift.Value(thumbnailFile.path),
      ),
    );
    final video = (await db.videosDao.getVideoByPath(videoFile.path))!;
    final events = <String>[];
    final auth = _FakePrivateLibraryAuthService(result: authenticationResult);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        thumbnailServiceProvider.overrideWithValue(thumbnailService),
        if (dataCompactionRunner != null)
          dataCompactionRunnerProvider.overrideWithValue(dataCompactionRunner),
        privateLibraryAuthServiceProvider.overrideWithValue(auth),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(
            adapter: _FakeLibraryAccessAdapter(
              canAccess: canAccessFolder,
              events: events,
            ),
          ),
        ),
      ],
    );

    return _MaintenanceFixture(
      db: db,
      container: container,
      root: root,
      videoFile: videoFile,
      subtitleFile: subtitleFile,
      thumbnailFile: thumbnailFile,
      video: video,
      events: events,
      auth: auth,
    );
  }

  Future<_FixtureVideo> addVideo(
    String fileName,
    String subtitleExtension,
  ) async {
    final videoFile = File(p.join(root.path, fileName));
    await videoFile.writeAsBytes(const <int>[1, 2, 3]);
    final subtitleFile = File(
      p.join(
        root.path,
        '${p.basenameWithoutExtension(fileName)}$subtitleExtension',
      ),
    );
    await subtitleFile.writeAsString('WEBVTT');

    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: video.folderId,
        absolutePath: videoFile.path,
        title: p.basenameWithoutExtension(fileName),
      ),
    );
    final inserted = (await db.videosDao.getVideoByPath(videoFile.path))!;
    return _FixtureVideo(
      videoFile: videoFile,
      subtitleFile: subtitleFile,
      video: inserted,
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

class _FakePrivateLibraryAuthService extends PrivateLibraryAuthService {
  _FakePrivateLibraryAuthService({required this.result});

  final bool result;
  int attempts = 0;

  @override
  Future<bool> authenticate() async {
    attempts += 1;
    return result;
  }
}

class _FixtureVideo {
  const _FixtureVideo({
    required this.videoFile,
    required this.subtitleFile,
    required this.video,
  });

  final File videoFile;
  final File subtitleFile;
  final Video video;
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
    events.add('start:$path:$bookmark');
    return canAccess;
  }

  @override
  Future<void> stopAccessing(String path) async {
    events.add('stop:$path');
  }
}
