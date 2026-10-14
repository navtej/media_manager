import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('coalesces duplicate database close requests', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());

    final firstClose = database.close();
    expect(identical(firstClose, database.close()), isTrue);
    await firstClose;
  });

  test(
    'resumes a partially completed version 10 library-groups migration',
    () async {
      final directory = await Directory.systemTemp.createTemp('movie-manager-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File(p.join(directory.path, 'movie_manager.sqlite'));
      final legacy = sqlite3.open(file.path);
      legacy.execute('''
      CREATE TABLE folders (
        id INTEGER NOT NULL PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        alias TEXT,
        group_name TEXT,
        security_scoped_bookmark TEXT,
        is_private INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL
      );
      CREATE TABLE library_groups (
        id INTEGER NOT NULL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        added_at INTEGER NOT NULL
      );
      INSERT INTO folders (id, path, alias, group_name, is_private, added_at)
      VALUES (1, '/Volumes/Media/Movies', 'Movies', 'Default Group', 0, 0);
      INSERT INTO library_groups (id, name, added_at)
      VALUES (1, 'Default Group', 0);
      PRAGMA user_version = 9;
    ''');
      legacy.dispose();

      final database = AppDatabase.forTesting(
        NativeDatabase.createInBackground(file),
      );
      addTearDown(database.close);

      final folders = await database.foldersDao.getAllFolders();
      expect(folders, hasLength(1));
      expect(folders.single.groupName, 'Default Group');
      expect(await database.libraryGroupsDao.getAllGroups(), hasLength(1));
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        11,
      );
    },
  );

  test('migrates a version 10 database to add video versions', () async {
    final directory = await Directory.systemTemp.createTemp('movie-manager-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'movie_manager.sqlite'));

    // Build a genuine v10 schema with the current code, then drop the new
    // table and rewind the version so the v11 migration runs on open.
    final seed = AppDatabase.forTesting(NativeDatabase(file));
    final folderId = await seed.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Volumes/Media/Movies'),
    );
    await seed.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: '/Volumes/Media/Movies/clip.mp4',
        title: 'clip',
        size: const drift.Value(42),
      ),
    );
    await seed.customStatement('DROP TABLE video_versions');
    await seed.customStatement('PRAGMA user_version = 10');
    await seed.close();

    final database = AppDatabase.forTesting(
      NativeDatabase.createInBackground(file),
    );
    addTearDown(database.close);

    final videos = await database.videosDao.getAllVideos();
    expect(videos.single.absolutePath, '/Volumes/Media/Movies/clip.mp4');
    expect(videos.single.size, 42);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      11,
    );
    final index = await database
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'index' "
          "AND name = 'video_versions_video_id'",
        )
        .get();
    expect(index, hasLength(1));

    await database.videoVersionsDao.insertVersion(
      VideoVersionsCompanion.insert(
        videoId: videos.single.id,
        absolutePath: '/Volumes/Media/Movies/clip [720p].mp4',
        width: const drift.Value(1280),
        height: const drift.Value(720),
      ),
    );
    final versions = await database.videoVersionsDao.getVersionsForVideo(
      videos.single.id,
    );
    expect(versions.single.isOriginal, isFalse);
    expect(versions.single.metadataJson, '{}');

    // Deleting the video cascades to its versions.
    await database.videosDao.deleteVideo(videos.single.id);
    expect(await database.videoVersionsDao.getAllVersions(), isEmpty);
  });

  test('resumes a v11 migration whose table already exists', () async {
    final directory = await Directory.systemTemp.createTemp('movie-manager-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'movie_manager.sqlite'));
    final seed = AppDatabase.forTesting(NativeDatabase(file));
    await seed.foldersDao.getAllFolders();
    await seed.customStatement('DROP INDEX video_versions_video_id');
    await seed.customStatement('PRAGMA user_version = 10');
    await seed.close();

    final database = AppDatabase.forTesting(
      NativeDatabase.createInBackground(file),
    );
    addTearDown(database.close);
    expect(await database.videoVersionsDao.getAllVersions(), isEmpty);
    final index = await database
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type = 'index' "
          "AND name = 'video_versions_video_id'",
        )
        .get();
    expect(index, hasLength(1));
  });
}
