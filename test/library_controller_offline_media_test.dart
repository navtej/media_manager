import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:movie_manager/services/media_service.dart';
import 'package:movie_manager/services/scanner_service.dart';
import 'package:movie_manager/services/thumbnail_service.dart';
import 'package:path/path.dart' as p;
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

  test('scan skips a candidate that disappears during preparation', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final root = await Directory.systemTemp.createTemp(
      'library-scan-missing-candidate-test',
    );
    addTearDown(() => root.delete(recursive: true));
    final survivingFile = File(p.join(root.path, 'नाम ｜ video.mp4'));
    await survivingFile.writeAsBytes(const <int>[1, 2, 3]);
    final missingPath = p.join(root.path, 'gone-？-video.mp4');

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    final messages = <String>[];
    final adapter = _RecordingLibraryAccessAdapter();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        scannerServiceProvider.overrideWithValue(
          _FixedBatchScannerService(<String>[missingPath, survivingFile.path]),
        ),
        mediaServiceProvider.overrideWithValue(_StubMediaService()),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: adapter),
        ),
      ],
    );
    addTearDown(container.dispose);

    await runZoned(
      () async {
        await container.read(libraryControllerProvider.future);
        await adapter.started;
        await _waitForScanIdle(container);
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => messages.add(line),
      ),
    );

    expect(
      (await db.videosDao.getVideosByFolder(
        folderId,
      )).map((video) => video.absolutePath),
      [survivingFile.path],
    );
    expect(
      messages.where((message) => message.contains('Error preparing')),
      isEmpty,
    );
  });

  test('startup scan retries after Library maintenance finishes', () async {
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
    final adapter = _DenyingLibraryAccessAdapter();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: adapter),
        ),
      ],
    );
    addTearDown(container.dispose);
    final operations = container.read(
      libraryOperationControllerProvider.notifier,
    );
    expect(operations.beginCleanup(), isTrue);

    await container.read(libraryControllerProvider.future);
    await _waitForScanStatus(container, 'Library maintenance in progress');
    expect(adapter.hasStarted, isFalse);

    operations.endCleanup();
    await adapter.started;
    await _waitForScanIdle(container);

    final video = (await db.videosDao.getVideoByPath(
      '/Volumes/Archive/Movies/clip.mp4',
    ))!;
    expect(video.isOffline, isTrue);
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

  test('syncAll removes thumbnails for missing catalog videos', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final root = await Directory.systemTemp.createTemp(
      'library-thumbnail-sync-test',
    );
    addTearDown(() => root.delete(recursive: true));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    final thumbnailService = ThumbnailService(
      applicationSupportDirectory: () async => root,
    );
    final thumbnail = File(
      await thumbnailService.saveThumbnail('stale.jpg', [1, 2, 3]),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        thumbnailServiceProvider.overrideWithValue(thumbnailService),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: _RecordingLibraryAccessAdapter()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _waitForScanIdle(container);
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: p.join(root.path, 'missing.mp4'),
        title: 'Missing',
        thumbnailPath: drift.Value(thumbnail.path),
      ),
    );

    await container.read(libraryControllerProvider.notifier).syncAll();

    expect(
      await db.videosDao.getVideoByPath(p.join(root.path, 'missing.mp4')),
      isNull,
    );
    expect(await thumbnail.exists(), isFalse);
  });

  test(
    'syncAll retries thumbnails missing from existing catalog videos',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final root = await Directory.systemTemp.createTemp(
        'library-thumbnail-repair-test',
      );
      addTearDown(() => root.delete(recursive: true));
      final videoFile = File(p.join(root.path, 'clip.mp4'));
      await videoFile.writeAsBytes(const <int>[1, 2, 3]);

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
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
          title: 'clip',
          duration: const drift.Value(12),
        ),
      );
      final thumbnailService = ThumbnailService(
        applicationSupportDirectory: () async => root,
      );
      final mediaService = _StubMediaService(
        thumbnailBytes: Uint8List.fromList(const <int>[4, 5, 6]),
      );
      final adapter = _RecordingLibraryAccessAdapter();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mediaServiceProvider.overrideWithValue(mediaService),
          thumbnailServiceProvider.overrideWithValue(thumbnailService),
          libraryAccessServiceProvider.overrideWithValue(
            LibraryAccessService(adapter: adapter),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider.future);
      await adapter.started;
      await _waitForScanIdle(container);

      final repaired = (await db.videosDao.getVideoByPath(videoFile.path))!;
      expect(repaired.thumbnailPath, isNotNull);
      expect(await File(repaired.thumbnailPath!).exists(), isTrue);
      expect(mediaService.thumbnailRequests, [videoFile.path]);
    },
  );

  test(
    'syncAll retries existing catalog videos with empty thumbnail files',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final root = await Directory.systemTemp.createTemp(
        'library-empty-thumbnail-repair-test',
      );
      addTearDown(() => root.delete(recursive: true));
      final videoFile = File(p.join(root.path, 'clip.mp4'));
      await videoFile.writeAsBytes(const <int>[1, 2, 3]);
      final emptyThumbnail = File(p.join(root.path, 'empty.jpg'));
      await emptyThumbnail.writeAsBytes(const <int>[]);

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
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
          title: 'clip',
          duration: const drift.Value(12),
          thumbnailPath: drift.Value(emptyThumbnail.path),
        ),
      );
      final thumbnailService = ThumbnailService(
        applicationSupportDirectory: () async => root,
      );
      final mediaService = _StubMediaService(
        thumbnailBytes: Uint8List.fromList(const <int>[4, 5, 6]),
      );
      final adapter = _RecordingLibraryAccessAdapter();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mediaServiceProvider.overrideWithValue(mediaService),
          thumbnailServiceProvider.overrideWithValue(thumbnailService),
          libraryAccessServiceProvider.overrideWithValue(
            LibraryAccessService(adapter: adapter),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider.future);
      await adapter.started;
      await _waitForScanIdle(container);

      final repaired = (await db.videosDao.getVideoByPath(videoFile.path))!;
      expect(repaired.thumbnailPath, isNot(emptyThumbnail.path));
      expect(await File(repaired.thumbnailPath!).length(), greaterThan(0));
      expect(mediaService.thumbnailRequests, [videoFile.path]);
    },
  );

  test(
    'syncAll skips zero-byte source files during thumbnail repair',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final root = await Directory.systemTemp.createTemp(
        'library-zero-byte-thumbnail-repair-test',
      );
      addTearDown(() => root.delete(recursive: true));
      final videoFile = File(p.join(root.path, 'placeholder.mp4'));
      await videoFile.writeAsBytes(const <int>[]);

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
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
          title: 'placeholder',
        ),
      );
      final mediaService = _StubMediaService(
        thumbnailBytes: Uint8List.fromList(const <int>[4, 5, 6]),
      );
      final adapter = _RecordingLibraryAccessAdapter();
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mediaServiceProvider.overrideWithValue(mediaService),
          thumbnailServiceProvider.overrideWithValue(
            ThumbnailService(applicationSupportDirectory: () async => root),
          ),
          libraryAccessServiceProvider.overrideWithValue(
            LibraryAccessService(adapter: adapter),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider.future);
      await adapter.started;
      await _waitForScanIdle(container);

      final unchanged = (await db.videosDao.getVideoByPath(videoFile.path))!;
      expect(unchanged.thumbnailPath, isNull);
      expect(mediaService.thumbnailRequests, isEmpty);
    },
  );

  test('rebuildLibrary removes thumbnails for cleared catalog rows', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final root = await Directory.systemTemp.createTemp(
      'library-thumbnail-rebuild-test',
    );
    addTearDown(() => root.delete(recursive: true));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: root.path),
    );
    final thumbnailService = ThumbnailService(
      applicationSupportDirectory: () async => root,
    );
    final thumbnail = File(
      await thumbnailService.saveThumbnail('rebuild.jpg', [1, 2, 3]),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        thumbnailServiceProvider.overrideWithValue(thumbnailService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _waitForScanIdle(container);
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: p.join(root.path, 'removed-by-rebuild.mp4'),
        title: 'Removed by rebuild',
        thumbnailPath: drift.Value(thumbnail.path),
      ),
    );

    await container.read(libraryControllerProvider.notifier).rebuildLibrary();

    expect(
      await db.videosDao.getVideoByPath(
        p.join(root.path, 'removed-by-rebuild.mp4'),
      ),
      isNull,
    );
    expect(await thumbnail.exists(), isFalse);
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
  bool get hasStarted => _started.isCompleted;

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

class _FixedBatchScannerService extends ScannerService {
  _FixedBatchScannerService(this.paths);

  final List<String> paths;

  @override
  Stream<List<String>> scanPaths(List<String> rootPaths) async* {
    yield paths;
  }
}

class _StubMediaService extends MediaService {
  _StubMediaService({this.thumbnailBytes});

  final Uint8List? thumbnailBytes;
  final List<String> thumbnailRequests = <String>[];

  @override
  Future<Map<String, dynamic>> getMetadata(String path) async => const {
    'duration': 0.0,
  };

  @override
  Future<Uint8List?> generateThumbnail(
    String path,
    double durationSeconds,
  ) async {
    thumbnailRequests.add(path);
    return thumbnailBytes;
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

Future<void> _waitForScanStatus(
  ProviderContainer container,
  String expected,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (container.read(scanStatusProvider) == expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Timed out waiting for scan status "$expected".');
}
