import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/services/empty_folder_cleanup_service.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'removes only empty descendants bottom-up and isolates access failures',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'empty-folder-cleanup-test',
      );
      final publicRoot = await Directory(
        p.join(sandbox.path, 'public'),
      ).create();
      final privateRoot = await Directory(
        p.join(sandbox.path, 'private'),
      ).create();
      final deniedRoot = await Directory(
        p.join(sandbox.path, 'denied'),
      ).create();
      final outsideRoot = await Directory(
        p.join(sandbox.path, 'outside'),
      ).create();
      addTearDown(() async {
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      });

      await Directory(
        p.join(publicRoot.path, 'empty-parent', 'empty-child'),
      ).create(recursive: true);
      final nonEmpty = await Directory(
        p.join(publicRoot.path, 'non-empty'),
      ).create();
      await File(p.join(nonEmpty.path, 'video.mp4')).writeAsBytes([1]);
      final hidden = await Directory(
        p.join(publicRoot.path, 'hidden-entry'),
      ).create();
      await File(p.join(hidden.path, '.DS_Store')).writeAsBytes([1]);
      await File(p.join(publicRoot.path, 'root-file.txt')).writeAsBytes([1]);
      final linkTarget = await Directory(
        p.join(outsideRoot.path, 'link-target'),
      ).create();
      final link = Link(p.join(publicRoot.path, 'directory-link'));
      await link.create(linkTarget.path);
      final privateEmpty = await Directory(
        p.join(privateRoot.path, 'empty'),
      ).create();
      final deniedEmpty = await Directory(
        p.join(deniedRoot.path, 'empty'),
      ).create();

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _insertLibrary(db, publicRoot.path);
      await _insertLibrary(db, deniedRoot.path);
      await _insertLibrary(db, privateRoot.path, isPrivate: true);
      final adapter = _RecordingAccessAdapter(deniedPath: deniedRoot.path);
      final service = EmptyFolderCleanupService(
        foldersDao: db.foldersDao,
        libraryAccessService: LibraryAccessService(adapter: adapter),
      );

      final result = await service.cleanup();

      expect(result.librariesAttempted, 3);
      expect(result.directoriesRemoved, 3);
      expect(result.libraryFailures, 1);
      expect(result.directoryFailures, 0);
      expect(
        await Directory(p.join(publicRoot.path, 'empty-parent')).exists(),
        isFalse,
      );
      expect(await privateEmpty.exists(), isFalse);
      expect(await publicRoot.exists(), isTrue);
      expect(await privateRoot.exists(), isTrue);
      expect(await nonEmpty.exists(), isTrue);
      expect(await hidden.exists(), isTrue);
      expect(
        await File(p.join(publicRoot.path, 'root-file.txt')).exists(),
        isTrue,
      );
      expect(await link.exists(), isTrue);
      expect(await linkTarget.exists(), isTrue);
      expect(await deniedEmpty.exists(), isTrue);
      expect(adapter.startedPaths, [
        publicRoot.path,
        deniedRoot.path,
        privateRoot.path,
      ]);
    },
  );

  test(
    'reports missing, non-directory, and bookmark-repair Libraries',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'empty-folder-cleanup-invalid-root-test',
      );
      addTearDown(() async {
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      });
      final rootFile = File(p.join(sandbox.path, 'library-file'));
      await rootFile.writeAsBytes([1]);

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _insertLibrary(db, p.join(sandbox.path, 'missing'));
      await _insertLibrary(db, rootFile.path);
      await db.foldersDao.insertFolder(
        FoldersCompanion.insert(path: sandbox.path),
      );
      final service = EmptyFolderCleanupService(
        foldersDao: db.foldersDao,
        libraryAccessService: LibraryAccessService(
          adapter: _RecordingAccessAdapter(),
        ),
      );

      final result = await service.cleanup();

      expect(result.librariesAttempted, 3);
      expect(result.directoriesRemoved, 0);
      expect(result.libraryFailures, 3);
      expect(await sandbox.exists(), isTrue);
      expect(await rootFile.exists(), isTrue);
    },
  );
}

Future<void> _insertLibrary(
  AppDatabase db,
  String path, {
  bool isPrivate = false,
}) async {
  await db.foldersDao.insertFolder(
    FoldersCompanion.insert(
      path: path,
      securityScopedBookmark: const drift.Value('bookmark'),
      isPrivate: drift.Value(isPrivate),
    ),
  );
}

class _RecordingAccessAdapter implements LibraryAccessAdapter {
  _RecordingAccessAdapter({this.deniedPath});

  final String? deniedPath;
  final List<String> startedPaths = [];

  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    startedPaths.add(path);
    return path != deniedPath;
  }

  @override
  Future<void> stopAccessing(String path) async {}
}
