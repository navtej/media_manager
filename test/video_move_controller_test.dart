import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/logic/video_move_controller.dart';
import 'package:movie_manager/logic/video_selection_controller.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:path/path.dart' as p;

import 'support/library_access_test_adapter.dart';

void main() {
  test('plans moves by preserving the source-relative path', () async {
    final fixture = await _MoveFixture.create();
    addTearDown(fixture.dispose);

    final plan = buildVideoMovePlan(
      videos: [fixture.sourceVideo],
      foldersById: {
        fixture.sourceFolder.id: fixture.sourceFolder,
        fixture.destinationFolder.id: fixture.destinationFolder,
      },
      destinationFolder: fixture.destinationFolder,
    );

    expect(plan, hasLength(1));
    expect(plan.single.isNoOp, isFalse);
    expect(
      plan.single.destinationPath,
      p.join(fixture.destination.path, 'Nested', 'clip.mp4'),
    );
  });

  test('preflight blocks an existing destination path', () async {
    final fixture = await _MoveFixture.create(createDestinationConflict: true);
    addTearDown(fixture.dispose);

    final preflight = await fixture.container
        .read(videoMoveControllerProvider.notifier)
        .preflightMove(
          videoIds: [fixture.sourceVideo.id],
          destinationFolderId: fixture.destinationFolder.id,
        );

    expect(preflight.canMove, isFalse);
    expect(preflight.conflicts, hasLength(1));
    expect(preflight.conflicts.single.destinationPath, endsWith('clip.mp4'));
    expect(await fixture.sourceVideoFile.exists(), isTrue);
  });

  test(
    'preflight starts folder access before listing subtitle sidecars',
    () async {
      final fixture = await _MoveFixture.create(
        restrictSourceListingUntilAccess: true,
      );
      addTearDown(fixture.dispose);

      final preflight = await fixture.container
          .read(videoMoveControllerProvider.notifier)
          .preflightMove(
            videoIds: [fixture.sourceVideo.id],
            destinationFolderId: fixture.destinationFolder.id,
          );

      expect(preflight.canMove, isTrue);
      expect(preflight.errors, isEmpty);
      expect(preflight.items.single.sidecars, hasLength(1));
    },
  );

  test(
    'moves multiple videos, subtitle sidecars, and keeps tags and summaries',
    () async {
      final fixture = await _MoveFixture.create(addSecondVideo: true);
      addTearDown(fixture.dispose);

      await fixture.container
          .read(videoSelectionControllerProvider.notifier)
          .selectLoaded([fixture.sourceVideo.id, fixture.secondVideo!.id]);

      final result = await fixture.container
          .read(videoMoveControllerProvider.notifier)
          .moveVideos(
            videoIds: [fixture.sourceVideo.id, fixture.secondVideo!.id],
            destinationFolderId: fixture.destinationFolder.id,
          );
      final completed = result!;

      expect(completed.movedCount, 2);
      expect(completed.failedCount, 0);
      expect(await fixture.sourceVideoFile.exists(), isFalse);
      expect(await fixture.sourceSubtitleFile.exists(), isFalse);
      expect(
        await File(
          p.join(fixture.destination.path, 'Nested', 'clip.mp4'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(fixture.destination.path, 'Nested', 'clip.en.vtt'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(p.join(fixture.destination.path, 'flat.mov')).exists(),
        isTrue,
      );

      final movedVideo = await fixture.db.videosDao.getVideoById(
        fixture.sourceVideo.id,
      );
      expect(movedVideo?.folderId, fixture.destinationFolder.id);
      expect(
        movedVideo?.absolutePath,
        p.join(fixture.destination.path, 'Nested', 'clip.mp4'),
      );

      final tags = await fixture.db.tagsDao.getTagsForVideo(
        fixture.sourceVideo.id,
      );
      expect(tags.map((tag) => tag.tagText), contains('favorite'));
      final summary = await fixture.db.videoSummariesDao.getSummaryForVideo(
        fixture.sourceVideo.id,
      );
      expect(summary?.summaryJson, '{"synopsis":"kept"}');

      final selection = fixture.container.read(
        videoSelectionControllerProvider,
      );
      expect(selection.selectedIds, isEmpty);
    },
  );

  test(
    'continues after a runtime failure and leaves failed videos selected',
    () async {
      final fixture = await _MoveFixture.create(addSecondVideo: true);
      addTearDown(fixture.dispose);
      await fixture.sourceVideoFile.delete();

      await fixture.container
          .read(videoSelectionControllerProvider.notifier)
          .selectLoaded([fixture.sourceVideo.id, fixture.secondVideo!.id]);

      final result = await fixture.container
          .read(videoMoveControllerProvider.notifier)
          .moveVideos(
            videoIds: [fixture.sourceVideo.id, fixture.secondVideo!.id],
            destinationFolderId: fixture.destinationFolder.id,
          );
      final completed = result!;

      expect(completed.movedCount, 1);
      expect(completed.failedCount, 1);
      expect(
        await File(p.join(fixture.destination.path, 'flat.mov')).exists(),
        isTrue,
      );
      expect(
        await fixture.db.videosDao.getVideoById(fixture.sourceVideo.id),
        isNotNull,
      );

      final selection = fixture.container.read(
        videoSelectionControllerProvider,
      );
      expect(selection.selectedIds, {fixture.sourceVideo.id});
    },
  );

  test('blocks moves while a scan operation is active', () async {
    final fixture = await _MoveFixture.create();
    addTearDown(fixture.dispose);
    final operation = fixture.container.read(
      libraryOperationControllerProvider.notifier,
    );
    expect(operation.beginScan(), isTrue);

    final result = await fixture.container
        .read(videoMoveControllerProvider.notifier)
        .moveVideos(
          videoIds: [fixture.sourceVideo.id],
          destinationFolderId: fixture.destinationFolder.id,
        );
    final completed = result!;

    expect(completed.movedCount, 0);
    expect(completed.failedCount, 1);
    expect(completed.failures.single.message, contains('scan'));
    expect(await fixture.sourceVideoFile.exists(), isTrue);
  });

  test('cancelled authentication blocks moving a private video', () async {
    final fixture = await _MoveFixture.create(
      sourceIsPrivate: true,
      authenticationResult: false,
    );
    addTearDown(fixture.dispose);

    final result = await fixture.container
        .read(videoMoveControllerProvider.notifier)
        .moveVideos(
          videoIds: [fixture.sourceVideo.id],
          destinationFolderId: fixture.destinationFolder.id,
        );

    expect(result, isNull);
    expect(fixture.auth.attempts, 1);
    expect(await fixture.sourceVideoFile.exists(), isTrue);
    expect(
      await fixture.db.videosDao.getVideoById(fixture.sourceVideo.id),
      isNotNull,
    );
  });

  test(
    'cancelled authentication blocks moving into a private library',
    () async {
      final fixture = await _MoveFixture.create(
        destinationIsPrivate: true,
        authenticationResult: false,
      );
      addTearDown(fixture.dispose);

      final result = await fixture.container
          .read(videoMoveControllerProvider.notifier)
          .moveVideos(
            videoIds: [fixture.sourceVideo.id],
            destinationFolderId: fixture.destinationFolder.id,
          );

      expect(result, isNull);
      expect(fixture.auth.attempts, 1);
      expect(await fixture.sourceVideoFile.exists(), isTrue);
      expect(
        await fixture.db.videosDao.getVideoById(fixture.sourceVideo.id),
        isNotNull,
      );
    },
  );
}

class _MoveFixture {
  const _MoveFixture({
    required this.db,
    required this.container,
    required this.source,
    required this.destination,
    required this.sourceFolder,
    required this.destinationFolder,
    required this.sourceVideoFile,
    required this.sourceSubtitleFile,
    required this.sourceVideo,
    required this.secondVideo,
    required this.auth,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final Directory source;
  final Directory destination;
  final Folder sourceFolder;
  final Folder destinationFolder;
  final File sourceVideoFile;
  final File sourceSubtitleFile;
  final Video sourceVideo;
  final Video? secondVideo;
  final _FakePrivateLibraryAuthService auth;

  static Future<_MoveFixture> create({
    bool createDestinationConflict = false,
    bool addSecondVideo = false,
    bool restrictSourceListingUntilAccess = false,
    bool sourceIsPrivate = false,
    bool destinationIsPrivate = false,
    bool authenticationResult = true,
  }) async {
    final root = await Directory.systemTemp.createTemp('video-move-test');
    final source = Directory(p.join(root.path, 'Source Library'));
    final destination = Directory(p.join(root.path, 'Destination Library'));
    await source.create(recursive: true);
    await destination.create(recursive: true);

    final nested = Directory(p.join(source.path, 'Nested'));
    await nested.create(recursive: true);
    final sourceVideoFile = File(p.join(nested.path, 'clip.mp4'));
    await sourceVideoFile.writeAsBytes(const <int>[1, 2, 3]);
    final sourceSubtitleFile = File(p.join(nested.path, 'clip.en.vtt'));
    await sourceSubtitleFile.writeAsString('WEBVTT');

    if (createDestinationConflict) {
      final conflictDir = Directory(p.join(destination.path, 'Nested'));
      await conflictDir.create(recursive: true);
      await File(p.join(conflictDir.path, 'clip.mp4')).writeAsBytes(const [9]);
    }

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final sourceFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: source.path,
        alias: const drift.Value('Source Library'),
        securityScopedBookmark: const drift.Value('source-bookmark'),
        isPrivate: drift.Value(sourceIsPrivate),
      ),
    );
    final destinationFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: destination.path,
        alias: const drift.Value('Destination Library'),
        securityScopedBookmark: const drift.Value('destination-bookmark'),
        isPrivate: drift.Value(destinationIsPrivate),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: sourceFolderId,
        absolutePath: sourceVideoFile.path,
        title: 'clip',
        size: const drift.Value(3),
        fileCreatedAt: drift.Value(await sourceVideoFile.lastModified()),
      ),
    );
    final sourceVideo = (await db.videosDao.getVideoByPath(
      sourceVideoFile.path,
    ))!;
    await db.tagsDao.insertTag(
      TagsCompanion.insert(videoId: sourceVideo.id, tagText: 'favorite'),
    );
    await db.videoSummariesDao.upsertSummary(
      VideoSummariesCompanion.insert(
        videoId: drift.Value(sourceVideo.id),
        transcriptText: 'transcript',
        summaryJson: '{"synopsis":"kept"}',
        transcriptModel: 'model-a',
        summaryModel: 'model-b',
        sourceVideoSize: 3,
        sourceVideoModifiedAt: await sourceVideoFile.lastModified(),
      ),
    );

    Video? secondVideo;
    if (addSecondVideo) {
      final secondFile = File(p.join(source.path, 'flat.mov'));
      await secondFile.writeAsBytes(const <int>[4, 5]);
      await db.videosDao.insertVideo(
        VideosCompanion.insert(
          folderId: sourceFolderId,
          absolutePath: secondFile.path,
          title: 'flat',
          size: const drift.Value(2),
          fileCreatedAt: drift.Value(await secondFile.lastModified()),
        ),
      );
      secondVideo = (await db.videosDao.getVideoByPath(secondFile.path))!;
    }

    if (restrictSourceListingUntilAccess) {
      await _setDirectoryUserAccess(nested, canAccess: false);
    }

    final sourceFolder = (await db.foldersDao.getFolderById(sourceFolderId))!;
    final destinationFolder = (await db.foldersDao.getFolderById(
      destinationFolderId,
    ))!;
    final LibraryAccessAdapter libraryAccessAdapter =
        restrictSourceListingUntilAccess
        ? _UnlockingLibraryAccessAdapter(
            sourcePath: source.path,
            directoriesToUnlock: [nested],
          )
        : AlwaysAllowedLibraryAccessAdapter();
    final auth = _FakePrivateLibraryAuthService(result: authenticationResult);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        privateLibraryAuthServiceProvider.overrideWithValue(auth),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: libraryAccessAdapter),
        ),
      ],
    );

    return _MoveFixture(
      db: db,
      container: container,
      source: source,
      destination: destination,
      sourceFolder: sourceFolder,
      destinationFolder: destinationFolder,
      sourceVideoFile: sourceVideoFile,
      sourceSubtitleFile: sourceSubtitleFile,
      sourceVideo: sourceVideo,
      secondVideo: secondVideo,
      auth: auth,
    );
  }

  Future<void> dispose() async {
    final root = source.parent;
    container.dispose();
    await db.close();
    if (await root.exists()) {
      await _setDirectoryTreeUserAccess(root);
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

class _UnlockingLibraryAccessAdapter implements LibraryAccessAdapter {
  _UnlockingLibraryAccessAdapter({
    required this.sourcePath,
    required this.directoriesToUnlock,
  });

  final String sourcePath;
  final List<Directory> directoriesToUnlock;

  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    if (p.normalize(path) == p.normalize(sourcePath)) {
      for (final directory in directoriesToUnlock) {
        await _setDirectoryUserAccess(directory, canAccess: true);
      }
    }
    return true;
  }

  @override
  Future<void> stopAccessing(String path) async {}
}

Future<void> _setDirectoryUserAccess(
  Directory directory, {
  required bool canAccess,
}) async {
  if (Platform.isWindows) {
    return;
  }
  final mode = canAccess ? 'u+rwx' : '000';
  final result = await Process.run('chmod', [mode, directory.path]);
  if (result.exitCode != 0) {
    throw StateError('chmod failed: ${result.stderr}');
  }
}

Future<void> _setDirectoryTreeUserAccess(Directory directory) async {
  if (Platform.isWindows) {
    return;
  }
  final result = await Process.run('chmod', ['-R', 'u+rwx', directory.path]);
  if (result.exitCode != 0) {
    throw StateError('chmod failed: ${result.stderr}');
  }
}
