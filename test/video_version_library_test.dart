import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/media_deletion_service.dart';
import 'package:movie_manager/services/media_service.dart';
import 'package:movie_manager/services/scanner_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/library_access_test_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scan never imports registered version files', () async {
    final f = await _LibraryFixture.create();
    addTearDown(f.dispose);
    final movie = await f.addVideo('Movie.mp4');
    await f.addVersion(movie, movie.absolutePath, isOriginal: true);
    await f.addVersion(movie, await f.write('Movie [720p].mp4'));
    await f.write('Other.mp4');
    final latePath = await f.write('Movie [480p].mp4');
    // Registered while the scan is already running.
    f.scanner.beforeYield = () => f.addVersion(movie, latePath);

    await f.startAndWaitForScan();

    final paths = (await f.db.videosDao.getAllVideos())
        .map((v) => p.basename(v.absolutePath))
        .toSet();
    expect(paths, {'Movie.mp4', 'Other.mp4'});
    expect(await f.db.videoVersionsDao.getAllVersions(), hasLength(3));
  });

  test(
    'syncAll promotes a surviving version and prunes missing ones',
    () async {
      final f = await _LibraryFixture.create();
      addTearDown(f.dispose);
      final movie = await f.addVideo('Movie.mp4');
      await f.addVersion(movie, movie.absolutePath, isOriginal: true);
      final survivor = await f.write('Movie [720p].mp4', bytes: 7);
      await f.addVersion(movie, survivor, width: 1280, height: 720);
      await f.addVersion(movie, f.path('Movie [480p].mp4'), width: 854);
      await File(movie.absolutePath).delete();
      final gone = await f.addVideo('Gone.mp4');
      await f.addVersion(gone, gone.absolutePath, isOriginal: true);
      await f.addVersion(gone, f.path('Gone [720p].mp4'));
      await File(gone.absolutePath).delete();

      await f.startAndWaitForScan();

      final current = (await f.db.videosDao.getVideoById(movie.id))!;
      expect(current.absolutePath, survivor);
      expect(current.size, 7);
      expect(current.title, 'Movie');
      final rows = await f.db.videoVersionsDao.getVersionsForVideo(movie.id);
      expect(rows.map((r) => r.absolutePath), [survivor]);
      expect(await f.db.videosDao.getVideoById(gone.id), isNull);
      expect(await f.db.videoVersionsDao.getAllVersions(), hasLength(1));
    },
  );

  test(
    'rebuildLibrary re-links versions under the re-imported video',
    () async {
      final f = await _LibraryFixture.create();
      addTearDown(f.dispose);
      final movie = await f.addVideo('Movie.mp4');
      await f.addVersion(movie, movie.absolutePath, isOriginal: true);
      final converted = await f.write('Movie [720p].mp4');
      await f.addVersion(movie, converted, width: 1280, height: 720);
      await f.addVersion(movie, f.path('Movie [480p].mp4'));
      // A converted video whose primary vanished: its former version is
      // imported as a video of its own rather than lost.
      final orphan = await f.addVideo('Orphan.mp4');
      await f.addVersion(orphan, orphan.absolutePath, isOriginal: true);
      final orphanVersion = await f.write('Orphan [720p].mp4');
      await f.addVersion(orphan, orphanVersion);
      await File(orphan.absolutePath).delete();
      await f.startAndWaitForScan();
      // The startup sync already promoted the orphan's version; undo that so
      // the rebuild sees a lost primary.
      await (f.db.update(
        f.db.videos,
      )..where((t) => t.id.equals(orphan.id))).write(
        VideosCompanion(absolutePath: drift.Value(orphan.absolutePath)),
      );
      await f.addVersion(orphan, orphan.absolutePath, isOriginal: true);

      await f.container
          .read(libraryControllerProvider.notifier)
          .rebuildLibrary();

      final videos = await f.db.videosDao.getAllVideos();
      expect(videos.map((v) => p.basename(v.absolutePath)).toSet(), {
        'Movie.mp4',
        'Orphan [720p].mp4',
      });
      final rebuilt = videos.firstWhere(
        (v) => v.absolutePath == movie.absolutePath,
      );
      final rows = await f.db.videoVersionsDao.getVersionsForVideo(rebuilt.id);
      expect(rows.map((r) => r.absolutePath).toSet(), {
        movie.absolutePath,
        converted,
      });
      expect(
        rows.firstWhere((r) => r.absolutePath == movie.absolutePath).isOriginal,
        isTrue,
      );
      expect(rows.firstWhere((r) => r.absolutePath == converted).width, 1280);
    },
  );

  test('deleting a video removes its other version files', () async {
    final f = await _LibraryFixture.create();
    addTearDown(f.dispose);
    final movie = await f.addVideo('Movie.mp4');
    await f.addVersion(movie, movie.absolutePath, isOriginal: true);
    final converted = await f.write('Movie [720p].mp4');
    await f.addVersion(movie, converted);
    await f.addVersion(movie, f.path('Movie [480p].mp4'));
    final service = MediaDeletionService(
      videosDao: f.db.videosDao,
      foldersDao: f.db.foldersDao,
      libraryAccessService: LibraryAccessService(
        adapter: AlwaysAllowedLibraryAccessAdapter(),
      ),
      fileSystem: LocalMediaDeletionFileSystem(),
      videoVersionsDao: f.db.videoVersionsDao,
    );

    final result = await service.deleteVideo(movie.id);

    expect(result.isDeleted, isTrue);
    expect(await File(movie.absolutePath).exists(), isFalse);
    expect(await File(converted).exists(), isFalse);
    expect(await f.db.videoVersionsDao.getAllVersions(), isEmpty);
  });

  test('syncAll rerun is queued while a versioning operation runs', () async {
    final f = await _LibraryFixture.create();
    addTearDown(f.dispose);
    await f.startAndWaitForScan();
    final operation = f.container.read(
      libraryOperationControllerProvider.notifier,
    );
    final versioning = Completer<void>();
    final running = operation.runVersioning(() => versioning.future);

    await f.write('New.mp4');
    await f.container.read(libraryControllerProvider.notifier).syncAll();
    expect(f.container.read(scanStatusProvider), 'Updating video versions');
    expect(await f.db.videosDao.getAllVideos(), isEmpty);

    versioning.complete();
    await running;
    await _waitFor(
      () async => (await f.db.videosDao.getAllVideos()).isNotEmpty,
    );
  });
}

class _HookedScannerService extends ScannerService {
  FutureOr<void> Function()? beforeYield;

  @override
  Stream<List<String>> scanPaths(List<String> rootPaths) async* {
    final paths = <String>[];
    await for (final batch in super.scanPaths(rootPaths)) {
      paths.addAll(batch);
    }
    await beforeYield?.call();
    yield paths;
  }
}

class _StubMediaService extends MediaService {
  @override
  Future<Map<String, dynamic>> getMetadata(String path) async => const {
    'duration': 10.0,
  };

  @override
  Future<Uint8List?> generateThumbnail(
    String path,
    double durationSeconds,
  ) async => null;
}

class _LibraryFixture {
  _LibraryFixture(this.db, this.root, this.folderId, this.scanner);

  final AppDatabase db;
  final Directory root;
  final int folderId;
  final _HookedScannerService scanner;
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      scannerServiceProvider.overrideWithValue(scanner),
      mediaServiceProvider.overrideWithValue(_StubMediaService()),
      libraryAccessServiceProvider.overrideWithValue(
        LibraryAccessService(adapter: AlwaysAllowedLibraryAccessAdapter()),
      ),
    ],
  );

  static Future<_LibraryFixture> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('video-version-lib');
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: root.path,
        securityScopedBookmark: const drift.Value('bookmark'),
      ),
    );
    return _LibraryFixture(db, root, folderId, _HookedScannerService());
  }

  String path(String name) => p.join(root.path, name);

  Future<String> write(String name, {int bytes = 3}) async {
    final file = File(path(name));
    await file.writeAsBytes(List<int>.filled(bytes, 1));
    return file.path;
  }

  Future<Video> addVideo(String name) async {
    final filePath = await write(name);
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: filePath,
        title: p.basenameWithoutExtension(name),
        size: const drift.Value(3),
        fileCreatedAt: drift.Value(DateTime(2024)),
        aiProcessed: const drift.Value(true),
      ),
    );
    return (await db.videosDao.getVideoByPath(filePath))!;
  }

  Future<void> addVersion(
    Video video,
    String path, {
    bool isOriginal = false,
    int? width,
    int? height,
  }) async {
    await db.videoVersionsDao.insertVersion(
      VideoVersionsCompanion.insert(
        videoId: video.id,
        absolutePath: path,
        isOriginal: drift.Value(isOriginal),
        width: drift.Value(width),
        height: drift.Value(height),
        size: const drift.Value(3),
      ),
    );
  }

  Future<void> startAndWaitForScan() async {
    await container.read(libraryControllerProvider.future);
    // The startup scan is scheduled in a microtask after build.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await _waitFor(
      () async => !container.read(libraryOperationControllerProvider).isBusy,
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

Future<void> _waitFor(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Condition not met.');
}
