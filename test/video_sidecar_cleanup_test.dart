import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:path/path.dart' as p;

void main() {
  test('deleteVideo removes only the database row', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final root = await Directory.systemTemp.createTemp('dao-delete-test');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final mediaFile = File(p.join(root.path, 'catalog-only.mp4'));
    final subtitleFile = File(p.join(root.path, 'catalog-only.srt'));
    final thumbnailFile = File(p.join(root.path, 'catalog-only.jpg'));
    await mediaFile.writeAsBytes(const [1]);
    await subtitleFile.writeAsString('subtitle');
    await thumbnailFile.writeAsBytes(const [2]);
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: root.path),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: mediaFile.path,
        title: 'catalog-only',
        thumbnailPath: drift.Value(thumbnailFile.path),
      ),
    );
    final video = (await db.videosDao.getVideoByPath(mediaFile.path))!;

    await db.videosDao.deleteVideo(video.id);

    expect(await db.videosDao.getVideoById(video.id), isNull);
    expect(await mediaFile.exists(), isTrue);
    expect(await subtitleFile.exists(), isTrue);
    expect(await thumbnailFile.exists(), isTrue);
  });

  test('deleteAppleDoubleSidecarVideos removes only database rows', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final root = await Directory.systemTemp.createTemp('sidecar-cleanup-test');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final realFile = File(p.join(root.path, 'real.mp4'));
    final sidecarFile = File(p.join(root.path, '._real.mp4'));
    await realFile.writeAsBytes(const <int>[1, 2, 3]);
    await sidecarFile.writeAsBytes(const <int>[4, 5, 6]);

    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: root.path),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: realFile.path,
        title: 'real',
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: sidecarFile.path,
        title: 'sidecar',
      ),
    );

    final deleted = await db.videosDao.deleteAppleDoubleSidecarVideos();

    expect(deleted, 1);
    expect(await db.videosDao.getVideoByPath(realFile.path), isNotNull);
    expect(await db.videosDao.getVideoByPath(sidecarFile.path), isNull);
    expect(await realFile.exists(), isTrue);
    expect(await sidecarFile.exists(), isTrue);
  });
}
