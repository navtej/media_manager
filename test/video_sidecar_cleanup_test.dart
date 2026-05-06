import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:path/path.dart' as p;

void main() {
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
