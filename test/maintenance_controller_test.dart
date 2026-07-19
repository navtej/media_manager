import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/maintenance_controller.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:path/path.dart' as p;

void main() {
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

      await fixture.container
          .read(maintenanceControllerProvider.notifier)
          .deleteVideo(fixture.video.id);

      expect(fixture.events, ['start:${fixture.root.path}:bookmark']);
      expect(await fixture.videoFile.exists(), isTrue);
      expect(
        await fixture.db.videosDao.getVideoById(fixture.video.id),
        isNotNull,
      );
      expect(
        fixture.container.read(scanStatusProvider),
        'Folder access needs repair. Reselect this folder in Settings.',
      );
    },
  );

  test(
    'deleteVideos keeps database rows when folder access needs repair',
    () async {
      final fixture = await _MaintenanceFixture.create(canAccessFolder: false);
      addTearDown(fixture.dispose);

      await fixture.container
          .read(maintenanceControllerProvider.notifier)
          .deleteVideos([fixture.video.id]);

      expect(fixture.events, ['start:${fixture.root.path}:bookmark']);
      expect(await fixture.videoFile.exists(), isTrue);
      expect(
        await fixture.db.videosDao.getVideoById(fixture.video.id),
        isNotNull,
      );
      expect(
        fixture.container.read(scanStatusProvider),
        'Folder access needs repair. Reselect this folder in Settings.',
      );
    },
  );
}

class _MaintenanceFixture {
  const _MaintenanceFixture({
    required this.db,
    required this.container,
    required this.root,
    required this.videoFile,
    required this.subtitleFile,
    required this.video,
    required this.events,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final Directory root;
  final File videoFile;
  final File subtitleFile;
  final Video video;
  final List<String> events;

  static Future<_MaintenanceFixture> create({
    bool canAccessFolder = true,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'maintenance-controller-test',
    );
    final videoFile = File(p.join(root.path, 'video.mp4'));
    await videoFile.writeAsBytes(const <int>[1, 2, 3]);
    final subtitleFile = File(p.join(root.path, 'video.en.vtt'));
    await subtitleFile.writeAsString('WEBVTT');

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
      ),
    );
    final video = (await db.videosDao.getVideoByPath(videoFile.path))!;
    final events = <String>[];

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
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
      video: video,
      events: events,
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
