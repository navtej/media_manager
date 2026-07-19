import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/logic/managed_library_service.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'creates a Library and refreshes an existing path idempotently',
    () async {
      final fixture = _ManagedLibraryFixture();
      addTearDown(fixture.dispose);
      fixture.access.nextBookmark = null;

      final created = await fixture.service.addOrRefresh(
        '/Volumes/Media/Movies/',
      );

      expect(created.status, ManagedLibraryAddStatus.created);
      expect(created.folder?.path, '/Volumes/Media/Movies');
      expect(created.folder?.alias, 'Movies');
      expect(created.folder?.securityScopedBookmark, isNull);

      fixture.access.nextBookmark = 'bookmark-2';
      final refreshed = await fixture.service.addOrRefresh(
        '/Volumes/Media/Movies',
      );

      expect(refreshed.status, ManagedLibraryAddStatus.bookmarkRefreshed);
      expect(refreshed.folder?.id, created.folder?.id);
      expect(refreshed.folder?.securityScopedBookmark, 'bookmark-2');
      expect(await fixture.db.foldersDao.getAllFolders(), hasLength(1));
    },
  );

  test('assigns deterministic case-insensitively unique names', () async {
    final fixture = _ManagedLibraryFixture();
    addTearDown(fixture.dispose);
    await fixture.db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Media/Movies',
        alias: const drift.Value('MOVIES'),
      ),
    );

    final added = await fixture.service.addOrRefresh('/Volumes/Archive/Movies');

    expect(added.status, ManagedLibraryAddStatus.created);
    expect(added.folder?.alias, 'Archive / Movies');
  });

  test('serializes concurrent creation and rename uniqueness checks', () async {
    final fixture = _ManagedLibraryFixture();
    addTearDown(fixture.dispose);

    final created = await Future.wait([
      fixture.service.addOrRefresh('/Volumes/Media/Movies'),
      fixture.service.addOrRefresh('/Volumes/Archive/Movies'),
    ]);

    expect(created.map((result) => result.folder?.alias).toSet(), {
      'Movies',
      'Archive / Movies',
    });

    final renamed = await Future.wait([
      fixture.service.rename(created[0].folder!.id, 'Cinema'),
      fixture.service.rename(created[1].folder!.id, 'cinema'),
    ]);

    expect(renamed.map((result) => result.status).toSet(), {
      ManagedLibraryRenameStatus.renamed,
      ManagedLibraryRenameStatus.duplicateName,
    });
    final names = (await fixture.db.foldersDao.getAllFolders())
        .map((folder) => folder.alias!.toLowerCase())
        .toSet();
    expect(names, hasLength(2));
  });

  test('startup normalization uses the managed naming policy', () async {
    final fixture = _ManagedLibraryFixture();
    addTearDown(fixture.dispose);
    await fixture.db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Media/Movies',
        alias: const drift.Value(' movies '),
      ),
    );
    await fixture.db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Archive/Movies',
        alias: const drift.Value('MOVIES'),
      ),
    );
    await fixture.db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Volumes/Other/Shows'),
    );

    final normalizedCount = await fixture.service.normalizeNames();
    final folders = await fixture.db.foldersDao.getAllFolders();

    expect(normalizedCount, 3);
    expect(folders.map((folder) => folder.alias), [
      'movies',
      'Archive / Movies',
      'Shows',
    ]);
  });

  test('rename trims input and rejects blank or duplicate names', () async {
    final fixture = _ManagedLibraryFixture();
    addTearDown(fixture.dispose);
    final firstId = await fixture.db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Media/Movies',
        alias: const drift.Value('Movies'),
      ),
    );
    final secondId = await fixture.db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Media/Shows',
        alias: const drift.Value('Shows'),
      ),
    );

    expect(
      (await fixture.service.rename(secondId, '   ')).status,
      ManagedLibraryRenameStatus.blankName,
    );
    expect(
      (await fixture.service.rename(secondId, ' movies ')).status,
      ManagedLibraryRenameStatus.duplicateName,
    );

    final renamed = await fixture.service.rename(firstId, '  Cinema  ');
    expect(renamed.status, ManagedLibraryRenameStatus.renamed);
    expect(renamed.folder?.alias, 'Cinema');
  });

  test(
    'making a private Library public requires successful authentication',
    () async {
      final fixture = _ManagedLibraryFixture(authResults: [false, true]);
      addTearDown(fixture.dispose);
      final id = await fixture.db.foldersDao.insertFolder(
        FoldersCompanion.insert(
          path: '/Volumes/Private',
          isPrivate: const drift.Value(true),
        ),
      );

      final cancelled = await fixture.service.setPrivacy(id, isPrivate: false);
      expect(
        cancelled.status,
        ManagedLibraryPrivacyStatus.authenticationCancelled,
      );
      expect(
        (await fixture.db.foldersDao.getFolderById(id))?.isPrivate,
        isTrue,
      );

      final changed = await fixture.service.setPrivacy(id, isPrivate: false);
      expect(changed.status, ManagedLibraryPrivacyStatus.madePublic);
      expect(
        (await fixture.db.foldersDao.getFolderById(id))?.isPrivate,
        isFalse,
      );
      expect(fixture.auth.attempts, 2);
    },
  );

  test(
    'access repair accepts only the same path and a valid bookmark',
    () async {
      final fixture = _ManagedLibraryFixture();
      addTearDown(fixture.dispose);
      final id = await fixture.db.foldersDao.insertFolder(
        FoldersCompanion.insert(path: '/Volumes/Archive/Movies'),
      );

      final wrongPath = await fixture.service.repairAccess(
        id,
        '/Volumes/Other/Movies',
      );
      expect(wrongPath.status, ManagedLibraryRepairStatus.pathMismatch);
      expect(fixture.access.createdForPaths, isEmpty);

      fixture.access.nextBookmark = null;
      final unavailable = await fixture.service.repairAccess(
        id,
        '/Volumes/Archive/Movies/',
      );
      expect(
        unavailable.status,
        ManagedLibraryRepairStatus.bookmarkUnavailable,
      );

      fixture.access.nextBookmark = 'replacement-bookmark';
      final repaired = await fixture.service.repairAccess(
        id,
        '/Volumes/Archive/Movies',
      );
      expect(repaired.status, ManagedLibraryRepairStatus.repaired);
      expect(repaired.folder?.securityScopedBookmark, 'replacement-bookmark');
    },
  );

  test(
    'removal deletes catalog records but leaves media files on disk',
    () async {
      final fixture = _ManagedLibraryFixture();
      addTearDown(fixture.dispose);
      final root = await Directory.systemTemp.createTemp(
        'managed-library-remove-test',
      );
      addTearDown(() => root.delete(recursive: true));
      final media = File(p.join(root.path, 'clip.mp4'));
      await media.writeAsBytes(const [1, 2, 3]);
      final folderId = await fixture.db.foldersDao.insertFolder(
        FoldersCompanion.insert(path: root.path),
      );
      await fixture.db.videosDao.insertVideo(
        VideosCompanion.insert(
          folderId: folderId,
          absolutePath: media.path,
          title: 'clip',
        ),
      );

      final removed = await fixture.service.remove(folderId);

      expect(removed.status, ManagedLibraryRemoveStatus.removed);
      expect(removed.removedVideoCount, 1);
      expect(await fixture.db.foldersDao.getFolderById(folderId), isNull);
      expect(await fixture.db.videosDao.getVideoByPath(media.path), isNull);
      expect(await media.exists(), isTrue);
    },
  );
}

class _ManagedLibraryFixture {
  _ManagedLibraryFixture({List<bool> authResults = const [true]})
    : db = AppDatabase.forTesting(NativeDatabase.memory()),
      access = _FakeLibraryAccessAdapter(),
      auth = _FakePrivateLibraryAuthService(authResults) {
    service = ManagedLibraryService(
      foldersDao: db.foldersDao,
      catalogVideoCount: (folderId) async {
        final videos = await db.videosDao.getVideosByFolder(folderId);
        return videos.length;
      },
      libraryAccessService: LibraryAccessService(adapter: access),
      privateLibraryAuthService: auth,
    );
  }

  final AppDatabase db;
  final _FakeLibraryAccessAdapter access;
  final _FakePrivateLibraryAuthService auth;
  late final ManagedLibraryService service;

  Future<void> dispose() => db.close();
}

class _FakeLibraryAccessAdapter implements LibraryAccessAdapter {
  String? nextBookmark = 'bookmark';
  final List<String> createdForPaths = [];

  @override
  Future<String?> createBookmark(String path) async {
    createdForPaths.add(path);
    return nextBookmark;
  }

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async => true;

  @override
  Future<void> stopAccessing(String path) async {}
}

class _FakePrivateLibraryAuthService extends PrivateLibraryAuthService {
  _FakePrivateLibraryAuthService(this._results);

  final List<bool> _results;
  int attempts = 0;

  @override
  Future<bool> authenticate() async {
    final result = _results[attempts.clamp(0, _results.length - 1)];
    attempts += 1;
    return result;
  }
}
