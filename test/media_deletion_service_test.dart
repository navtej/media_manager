import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/media_deletion_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'deleteVideo removes media, subtitle variants, thumbnail, and catalog relationships',
    () async {
      final fixture = await _DeletionFixture.create();
      addTearDown(fixture.dispose);
      final item = await fixture.addVideo('feature', withRelationships: true);
      final directSubtitle = await fixture.createFile('feature.srt');
      final localizedSubtitle = await fixture.createFile('feature.en.vtt');
      final uppercaseSubtitle = await fixture.createFile('feature.forced.SRT');
      final unrelatedSubtitle = await fixture.createFile('featurette.srt');

      final result = await fixture.service.deleteVideo(item.video.id);

      expect(result.status, MediaDeletionStatus.deleted);
      expect(result.videoId, item.video.id);
      expect(await item.mediaFile.exists(), isFalse);
      expect(await directSubtitle.exists(), isFalse);
      expect(await localizedSubtitle.exists(), isFalse);
      expect(await uppercaseSubtitle.exists(), isFalse);
      expect(await unrelatedSubtitle.exists(), isTrue);
      expect(await item.thumbnailFile.exists(), isFalse);
      expect(await fixture.db.videosDao.getVideoById(item.video.id), isNull);
      expect(await fixture.db.tagsDao.getTagsForVideo(item.video.id), isEmpty);
      expect(
        await fixture.db.videoSummariesDao.getSummaryForVideo(item.video.id),
        isNull,
      );
    },
  );

  test(
    'deleteVideo succeeds when filesystem artifacts are already missing',
    () async {
      final fixture = await _DeletionFixture.create();
      addTearDown(fixture.dispose);
      final item = await fixture.addVideo(
        'missing',
        createMedia: false,
        createThumbnail: false,
      );

      final result = await fixture.service.deleteVideo(item.video.id);

      expect(result.status, MediaDeletionStatus.deleted);
      expect(await fixture.db.videosDao.getVideoById(item.video.id), isNull);
    },
  );

  test(
    'deleteVideo returns needs repair without mutating files or catalog',
    () async {
      final fixture = await _DeletionFixture.create(canAccess: false);
      addTearDown(fixture.dispose);
      final item = await fixture.addVideo('denied', withRelationships: true);

      final result = await fixture.service.deleteVideo(item.video.id);

      expect(result.status, MediaDeletionStatus.needsRepair);
      expect(result.userMessage, contains('Reselect this folder in Settings'));
      expect(await item.mediaFile.exists(), isTrue);
      expect(await item.thumbnailFile.exists(), isTrue);
      expect(await fixture.db.videosDao.getVideoById(item.video.id), isNotNull);
      expect(
        await fixture.db.videoSummariesDao.getSummaryForVideo(item.video.id),
        isNotNull,
      );
    },
  );

  test(
    'deleteVideo reports filesystem failure and preserves catalog record',
    () async {
      final fixture = await _DeletionFixture.create(
        fileSystem: _ThrowingDeletionFileSystem(),
      );
      addTearDown(fixture.dispose);
      final item = await fixture.addVideo('blocked');

      final result = await fixture.service.deleteVideo(item.video.id);

      expect(result.status, MediaDeletionStatus.filesystemFailure);
      expect(result.userMessage, contains('Check that the files are writable'));
      expect(await item.mediaFile.exists(), isTrue);
      expect(await fixture.db.videosDao.getVideoById(item.video.id), isNotNull);
    },
  );

  test('completed deletion result survives an access release error', () async {
    final fixture = await _DeletionFixture.create(throwOnStop: true);
    addTearDown(fixture.dispose);
    final item = await fixture.addVideo('release-error');

    final result = await fixture.service.deleteVideo(item.video.id);

    expect(result.status, MediaDeletionStatus.deleted);
    expect(await item.mediaFile.exists(), isFalse);
    expect(await fixture.db.videosDao.getVideoById(item.video.id), isNull);
  });

  test(
    'deleteVideos returns every result and continues after an item failure',
    () async {
      final fileSystem = _SelectiveDeletionFileSystem();
      final fixture = await _DeletionFixture.create(fileSystem: fileSystem);
      addTearDown(fixture.dispose);
      final blocked = await fixture.addVideo('blocked');
      final deletable = await fixture.addVideo('deletable');
      fileSystem.failPath = blocked.mediaFile.path;

      final result = await fixture.service.deleteVideos([
        blocked.video.id,
        deletable.video.id,
        987654,
      ]);

      expect(result.results.map((item) => item.status), [
        MediaDeletionStatus.filesystemFailure,
        MediaDeletionStatus.deleted,
        MediaDeletionStatus.notFound,
      ]);
      expect(result.deletedVideoIds, [deletable.video.id]);
      expect(result.userMessage, contains('Deleted 1 of 3 videos'));
      expect(
        await fixture.db.videosDao.getVideoById(blocked.video.id),
        isNotNull,
      );
      expect(
        await fixture.db.videosDao.getVideoById(deletable.video.id),
        isNull,
      );
    },
  );
}

class _DeletionFixture {
  _DeletionFixture({
    required this.db,
    required this.root,
    required this.folderId,
    required this.service,
  });

  final AppDatabase db;
  final Directory root;
  final int folderId;
  final MediaDeletionService service;

  static Future<_DeletionFixture> create({
    bool canAccess = true,
    bool throwOnStop = false,
    MediaDeletionFileSystem? fileSystem,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('media-deletion-test');
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    final service = MediaDeletionService(
      videosDao: db.videosDao,
      foldersDao: db.foldersDao,
      libraryAccessService: LibraryAccessService(
        adapter: _DeletionAccessAdapter(
          canAccess: canAccess,
          throwOnStop: throwOnStop,
        ),
      ),
      fileSystem: fileSystem ?? LocalMediaDeletionFileSystem(),
    );
    return _DeletionFixture(
      db: db,
      root: root,
      folderId: folderId,
      service: service,
    );
  }

  Future<_DeletionVideo> addVideo(
    String basename, {
    bool createMedia = true,
    bool createThumbnail = true,
    bool withRelationships = false,
  }) async {
    final mediaFile = File(p.join(root.path, '$basename.mp4'));
    final thumbnailFile = File(p.join(root.path, '$basename-thumbnail.jpg'));
    if (createMedia) {
      await mediaFile.writeAsBytes(const [1, 2, 3]);
    }
    if (createThumbnail) {
      await thumbnailFile.writeAsBytes(const [4, 5, 6]);
    }
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: mediaFile.path,
        title: basename,
        thumbnailPath: drift.Value(thumbnailFile.path),
      ),
    );
    final video = (await db.videosDao.getVideoByPath(mediaFile.path))!;
    if (withRelationships) {
      await db.tagsDao.insertTag(
        TagsCompanion.insert(videoId: video.id, tagText: 'keep-clean'),
      );
      await db.videoSummariesDao.upsertSummary(
        VideoSummariesCompanion.insert(
          videoId: drift.Value(video.id),
          transcriptText: 'transcript',
          summaryJson: '{}',
          transcriptModel: 'transcript-model',
          summaryModel: 'summary-model',
          sourceVideoSize: 3,
          sourceVideoModifiedAt: DateTime(2026, 7, 19),
        ),
      );
    }
    return _DeletionVideo(
      video: video,
      mediaFile: mediaFile,
      thumbnailFile: thumbnailFile,
    );
  }

  Future<File> createFile(String name) async {
    final file = File(p.join(root.path, name));
    await file.writeAsString('subtitle');
    return file;
  }

  Future<void> dispose() async {
    await db.close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

class _DeletionVideo {
  const _DeletionVideo({
    required this.video,
    required this.mediaFile,
    required this.thumbnailFile,
  });

  final Video video;
  final File mediaFile;
  final File thumbnailFile;
}

class _DeletionAccessAdapter implements LibraryAccessAdapter {
  const _DeletionAccessAdapter({
    required this.canAccess,
    this.throwOnStop = false,
  });

  final bool canAccess;
  final bool throwOnStop;

  @override
  Future<String?> createBookmark(String path) async => 'bookmark';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async => canAccess;

  @override
  Future<void> stopAccessing(String path) async {
    if (throwOnStop) {
      throw FileSystemException('release failed', path);
    }
  }
}

class _ThrowingDeletionFileSystem implements MediaDeletionFileSystem {
  @override
  Future<void> deleteArtifacts({
    required String mediaPath,
    required String? thumbnailPath,
  }) {
    throw FileSystemException('denied', mediaPath);
  }
}

class _SelectiveDeletionFileSystem implements MediaDeletionFileSystem {
  final LocalMediaDeletionFileSystem _delegate = LocalMediaDeletionFileSystem();
  String? failPath;

  @override
  Future<void> deleteArtifacts({
    required String mediaPath,
    required String? thumbnailPath,
  }) {
    if (mediaPath == failPath) {
      throw FileSystemException('denied', mediaPath);
    }
    return _delegate.deleteArtifacts(
      mediaPath: mediaPath,
      thumbnailPath: thumbnailPath,
    );
  }
}
