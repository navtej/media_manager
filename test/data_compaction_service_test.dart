import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/services/data_compaction_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'compacts SQLite and removes only unreferenced managed thumbnails',
    () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'data-compaction-service-test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });
      final databaseFile = File(
        p.join(supportDirectory.path, 'movie_manager.sqlite'),
      );
      final database = AppDatabase.forTesting(
        NativeDatabase.createInBackground(databaseFile),
      );
      addTearDown(database.close);
      final thumbnails = await Directory(
        p.join(supportDirectory.path, 'thumbnails'),
      ).create();
      final referencedThumbnail = File(p.join(thumbnails.path, 'keep.jpg'));
      final orphanedThumbnail = File(p.join(thumbnails.path, 'orphan.jpg'));
      final nestedDirectory = await Directory(
        p.join(thumbnails.path, 'nested'),
      ).create();
      final nestedFile = File(p.join(nestedDirectory.path, 'keep.jpg'));
      final model = File(p.join(supportDirectory.path, 'models', 'model.bin'));
      final backup = File(
        p.join(supportDirectory.path, 'movie_manager.sqlite.backup'),
      );
      final outsideFile = File(p.join(supportDirectory.path, 'outside.jpg'));
      final link = Link(p.join(thumbnails.path, 'outside-link.jpg'));

      await referencedThumbnail.writeAsBytes(List<int>.filled(32, 1));
      await orphanedThumbnail.writeAsBytes(List<int>.filled(64, 2));
      await nestedFile.writeAsBytes(List<int>.filled(16, 3));
      await model.parent.create(recursive: true);
      await model.writeAsBytes(List<int>.filled(16, 4));
      await backup.writeAsBytes(List<int>.filled(16, 5));
      await outsideFile.writeAsBytes(List<int>.filled(16, 6));
      await link.create(outsideFile.path);

      final folderId = await database.foldersDao.insertFolder(
        FoldersCompanion.insert(path: '/Volumes/Movies'),
      );
      await database.videosDao.insertVideo(
        VideosCompanion.insert(
          folderId: folderId,
          absolutePath: '/Volumes/Movies/keep.mp4',
          title: 'Keep',
          thumbnailPath: drift.Value(referencedThumbnail.path),
        ),
      );
      await database.customStatement(
        'CREATE TABLE compaction_fixture (payload BLOB)',
      );
      await database.customStatement(
        'INSERT INTO compaction_fixture VALUES (zeroblob(4194304))',
      );
      await database.customStatement('DELETE FROM compaction_fixture');
      final sizeBeforeVacuum = await databaseFile.length();

      final result = await DataCompactionService(
        database: database,
        applicationSupportDirectory: supportDirectory,
      ).compact();

      expect(result.status, DataCompactionStatus.completed);
      expect(result.removedThumbnailCount, 1);
      expect(await referencedThumbnail.exists(), isTrue);
      expect(await orphanedThumbnail.exists(), isFalse);
      expect(await nestedDirectory.exists(), isTrue);
      expect(await nestedFile.exists(), isTrue);
      expect(await model.exists(), isTrue);
      expect(await backup.exists(), isTrue);
      expect(await outsideFile.exists(), isTrue);
      expect(await link.exists(), isTrue);
      expect(await databaseFile.length(), lessThan(sizeBeforeVacuum));
      expect(result.afterBytes, lessThan(result.beforeBytes));
      expect(
        (await database.customSelect('PRAGMA quick_check').getSingle())
            .read<String>('quick_check'),
        'ok',
      );
    },
  );
}
