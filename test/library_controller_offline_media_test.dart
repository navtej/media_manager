import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/catalog_controller.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/services/library_access_service.dart';
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

    final libraryAccessAdapter = _DenyingLibraryAccessAdapter();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: libraryAccessAdapter),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.future);
    await libraryAccessAdapter.started;
    await _waitForScanIdle(container);

    final updated = (await db.videosDao.getVideoById(video.id))!;
    expect(updated.isOffline, isTrue);
    final catalog = await CatalogQueryModule(
      db,
    ).fetch(_criteria(folderId: folderId));
    expect(catalog.loadedVideos, isEmpty);
    expect(catalog.totalCount, 0);
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

    final visible = (await CatalogQueryModule(
      db,
    ).fetch(_criteria(folderId: folderId))).loadedVideos;
    expect(visible.map((video) => video.absolutePath), [
      '/Volumes/Mounted/Movies/clip.mp4',
    ]);
  });

  test('syncAll runs scanning inside the Library access seam', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final root = await Directory.systemTemp.createTemp(
      'library-access-scan-test',
    );
    addTearDown(() => root.delete(recursive: true));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    final adapter = _RecordingLibraryAccessAdapter();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: adapter),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.future);
    await adapter.started;
    await _waitForScanIdle(container);

    expect(adapter.events, [
      'start:${root.path}:bookmark',
      'stop:${root.path}',
    ]);
  });
}

CatalogCriteria _criteria({required int folderId}) {
  return CatalogCriteria(
    searchQuery: '',
    primaryTags: const <String>[],
    relatedTags: const <String>[],
    favoritesOnly: false,
    sortBy: SortOption.title,
    sortDirection: SortDirection.asc,
    pageLimit: 50,
    includeOffline: false,
    folderIds: <int>[folderId],
  );
}

class _DenyingLibraryAccessAdapter implements LibraryAccessAdapter {
  final Completer<void> _started = Completer<void>();

  Future<void> get started => _started.future;

  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    if (!_started.isCompleted) {
      _started.complete();
    }
    return false;
  }

  @override
  Future<void> stopAccessing(String path) async {}
}

class _RecordingLibraryAccessAdapter implements LibraryAccessAdapter {
  final Completer<void> _started = Completer<void>();
  final List<String> events = [];

  Future<void> get started => _started.future;

  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    events.add('start:$path:$bookmark');
    if (!_started.isCompleted) {
      _started.complete();
    }
    return true;
  }

  @override
  Future<void> stopAccessing(String path) async {
    events.add('stop:$path');
  }
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
