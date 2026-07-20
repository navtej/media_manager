import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/filter_controller.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/logic/stats_provider.dart';
import 'package:movie_manager/logic/video_selection_controller.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/provider_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'locked private libraries are excluded from videos counts tags and stats',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'showOfflineMedia': true,
      });
      final fixture = await _PrivateLibraryFixture.create();
      addTearDown(fixture.db.close);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(fixture.db),
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(fixture.db, fixture.folders),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(
            _FakePrivateLibraryAuthService(result: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      await readAsyncValue(container, libraryFoldersProvider);

      expect(container.read(effectiveLibraryFolderIdsProvider), [
        fixture.publicFolderId,
      ]);
      expect(
        (await readAsyncValue(
          container,
          filteredVideosProvider,
        )).map((video) => video.title),
        ['Public Clip'],
      );
      expect(await readAsyncValue(container, selectedVideoCountProvider), 1);
      expect(
        (await readAsyncValue(
          container,
          allTagsProvider,
        )).map((entry) => entry.key),
        ['public tag'],
      );
      expect(
        (await readAsyncValue(container, libraryStatsProvider)).totalCount,
        1,
      );
    },
  );

  test(
    'unlocking private libraries makes private folders selectable',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'showOfflineMedia': true,
      });
      final fixture = await _PrivateLibraryFixture.create();
      addTearDown(fixture.db.close);
      final auth = _FakePrivateLibraryAuthService(result: true);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(fixture.db),
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(fixture.db, fixture.folders),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);

      await readAsyncValue(container, libraryFoldersProvider);
      final unlocked = await container
          .read(privateLibraryAccessControllerProvider.notifier)
          .unlock();

      expect(unlocked, isTrue);
      expect(auth.attempts, 1);
      expect(container.read(effectiveLibraryFolderIdsProvider), [
        fixture.publicFolderId,
      ]);

      container
          .read(selectedLibraryFoldersControllerProvider.notifier)
          .toggle(fixture.privateFolderId);

      expect(container.read(effectiveLibraryFolderIdsProvider), [
        fixture.privateFolderId,
      ]);
      expect(
        (await readAsyncValue(
          container,
          filteredVideosProvider,
        )).map((video) => video.title),
        ['Private Clip'],
      );
    },
  );

  test(
    'select all visible returns to public libraries after private selection',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'showOfflineMedia': true,
      });
      final fixture = await _PrivateLibraryFixture.create();
      addTearDown(fixture.db.close);
      final auth = _FakePrivateLibraryAuthService(result: true);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(fixture.db),
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(fixture.db, fixture.folders),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(auth),
        ],
      );
      addTearDown(container.dispose);

      await readAsyncValue(container, libraryFoldersProvider);
      await container
          .read(privateLibraryAccessControllerProvider.notifier)
          .unlock();
      container
          .read(selectedLibraryFoldersControllerProvider.notifier)
          .toggle(fixture.privateFolderId);

      expect(container.read(effectiveLibraryFolderIdsProvider), [
        fixture.privateFolderId,
      ]);
      expect(
        (await readAsyncValue(
          container,
          filteredVideosProvider,
        )).map((video) => video.title),
        ['Private Clip'],
      );

      container
          .read(selectedLibraryFoldersControllerProvider.notifier)
          .selectAllVisible();

      expect(container.read(effectiveLibraryFolderIdsProvider), [
        fixture.publicFolderId,
      ]);
      expect(
        (await readAsyncValue(
          container,
          filteredVideosProvider,
        )).map((video) => video.title),
        ['Public Clip'],
      );
    },
  );

  testWidgets(
    'auto-lock hides private media and removes only private selections',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'showOfflineMedia': true,
        'privateLibraryAutoLockMinutes': 1,
      });
      final fixture = await _PrivateLibraryFixture.create();
      addTearDown(fixture.db.close);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(fixture.db),
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(fixture.db, fixture.folders),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(
            _FakePrivateLibraryAuthService(result: true),
          ),
        ],
      );
      final filteredVideosSubscription = container.listen(
        filteredVideosProvider,
        (_, _) {},
      );
      await tester.runAsync(
        () => readAsyncValue<List<Folder>>(container, libraryFoldersProvider),
      );

      await container
          .read(privateLibraryAccessControllerProvider.notifier)
          .unlock();
      final selectedFolders = container.read(
        selectedLibraryFoldersControllerProvider.notifier,
      );
      selectedFolders.toggle(fixture.publicFolderId);
      selectedFolders.toggle(fixture.privateFolderId);
      await tester.pump();
      expect(
        (await tester.runAsync(
          () => readAsyncValue<List<Video>>(container, filteredVideosProvider),
        ))!.map((video) => video.title).toSet(),
        {'Public Clip', 'Private Clip'},
      );

      final selectedVideos = container.read(
        videoSelectionControllerProvider.notifier,
      );
      selectedVideos.toggle(fixture.publicVideoId);
      selectedVideos.toggle(fixture.privateVideoId);
      container.read(searchQueryProvider.notifier).set('Private Clip');
      await tester.pump();
      expect(
        (await tester.runAsync(
          () => readAsyncValue<List<Video>>(container, filteredVideosProvider),
        ))!.map((video) => video.title),
        ['Private Clip'],
      );

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(
        container.read(privateLibraryAccessControllerProvider).isUnlocked,
        isFalse,
      );
      expect(container.read(selectedLibraryFoldersControllerProvider), {
        fixture.publicFolderId,
      });
      expect(container.read(videoSelectionControllerProvider).selectedIds, {
        fixture.publicVideoId,
      });
      container.read(searchQueryProvider.notifier).set('');
      await tester.pump();
      expect(
        (await tester.runAsync(
          () => readAsyncValue<List<Video>>(container, filteredVideosProvider),
        ))!.map((video) => video.title),
        ['Public Clip'],
      );

      filteredVideosSubscription.close();
      container.dispose();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

class _PrivateLibraryFixture {
  const _PrivateLibraryFixture({
    required this.db,
    required this.publicFolderId,
    required this.privateFolderId,
    required this.publicVideoId,
    required this.privateVideoId,
    required this.folders,
  });

  final AppDatabase db;
  final int publicFolderId;
  final int privateFolderId;
  final int publicVideoId;
  final int privateVideoId;
  final List<Folder> folders;

  static Future<_PrivateLibraryFixture> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final publicFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Public Movies',
        alias: const drift.Value('Public Movies'),
      ),
    );
    final privateFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Private Movies',
        alias: const drift.Value('Private Movies'),
        isPrivate: const drift.Value(true),
      ),
    );
    final publicVideo = await _insertVideo(
      db,
      publicFolderId,
      '/Volumes/Public Movies/public.mp4',
      'Public Clip',
    );
    final privateVideo = await _insertVideo(
      db,
      privateFolderId,
      '/Volumes/Private Movies/private.mp4',
      'Private Clip',
    );
    await db.tagsDao.insertTagsBatch([
      TagsCompanion.insert(
        videoId: publicVideo.id,
        tagText: 'PublicTag',
        source: const drift.Value('user'),
      ),
      TagsCompanion.insert(
        videoId: privateVideo.id,
        tagText: 'PrivateTag',
        source: const drift.Value('user'),
      ),
    ]);
    final publicFolder = (await db.foldersDao.getFolderById(publicFolderId))!;
    final privateFolder = (await db.foldersDao.getFolderById(privateFolderId))!;
    return _PrivateLibraryFixture(
      db: db,
      publicFolderId: publicFolderId,
      privateFolderId: privateFolderId,
      publicVideoId: publicVideo.id,
      privateVideoId: privateVideo.id,
      folders: [publicFolder, privateFolder],
    );
  }
}

Future<Video> _insertVideo(
  AppDatabase db,
  int folderId,
  String path,
  String title,
) async {
  await db.videosDao.insertVideo(
    VideosCompanion.insert(
      folderId: folderId,
      absolutePath: path,
      title: title,
    ),
  );
  return (await db.videosDao.getVideoByPath(path))!;
}

class _FakePrivateLibraryAuthService extends PrivateLibraryAuthService {
  _FakePrivateLibraryAuthService({required this.result});

  final bool result;
  int attempts = 0;

  @override
  Future<bool> authenticate() async {
    attempts += 1;
    return result;
  }
}

class _StaticFoldersDao extends FoldersDao {
  _StaticFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);
}
