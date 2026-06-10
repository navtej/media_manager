import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/services/folder_access_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('syncAll marks inaccessible removable-folder videos offline', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Archive/Movies',
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: '/Volumes/Archive/Movies/clip.mp4',
        title: 'clip',
        aiProcessed: const drift.Value(true),
      ),
    );
    final video = (await db.videosDao.getVideoByPath(
      '/Volumes/Archive/Movies/clip.mp4',
    ))!;
    expect(video.isOffline, isFalse);

    final folderAccessService = _DenyingFolderAccessService();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        folderAccessServiceProvider.overrideWithValue(folderAccessService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.future);
    await folderAccessService.started;
    await _waitForScanIdle(container);

    final updated = (await db.videosDao.getVideoById(video.id))!;
    expect(updated.isOffline, isTrue);
    expect(
      await db.videosDao.searchVideos(includeOffline: false).first,
      isEmpty,
    );
    expect(await db.videosDao.countVideos(includeOffline: false).first, 0);
  });

  test('online removable-folder videos remain visible', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Mounted/Movies',
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: '/Volumes/Mounted/Movies/clip.mp4',
        title: 'clip',
        aiProcessed: const drift.Value(true),
      ),
    );

    final visible = await db.videosDao
        .searchVideos(includeOffline: false)
        .first;
    expect(visible.map((video) => video.absolutePath), [
      '/Volumes/Mounted/Movies/clip.mp4',
    ]);
  });
}

class _DenyingFolderAccessService extends FolderAccessService {
  final Completer<void> _started = Completer<void>();

  Future<void> get started => _started.future;

  @override
  Future<FolderAccessSession> startAccessing({
    required String path,
    required String? bookmark,
  }) async {
    if (!_started.isCompleted) {
      _started.complete();
    }
    return FolderAccessSession(
      path: path,
      canAccess: false,
      needsRepair: true,
      message: 'Folder access needs repair. Reselect this folder in Settings.',
    );
  }

  @override
  Future<void> stopAccessing({
    required String path,
    required String? bookmark,
  }) async {}
}

Future<void> _waitForScanIdle(ProviderContainer container) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!container.read(libraryOperationControllerProvider).isScanning) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Timed out waiting for library scan to finish.');
}
