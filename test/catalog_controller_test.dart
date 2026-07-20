import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/catalog_controller.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/provider_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rows and aggregates share every catalog filter dimension', () async {
    final fixture = await _CatalogFixture.create();
    addTearDown(fixture.db.close);
    final catalog = CatalogQueryModule(fixture.db);

    final cases = <CatalogCriteria>[
      fixture.criteria(),
      fixture.criteria(searchQuery: 'gamma'),
      fixture.criteria(favoritesOnly: true),
      fixture.criteria(primaryTags: const <String>['red', 'blue']),
      fixture.criteria(relatedTags: const <String>['red', 'common']),
      fixture.criteria(includeOffline: false),
      fixture.criteria(folderIds: <int>[fixture.secondPublicFolderId]),
      fixture.criteria(folderIds: const <int>[]),
      fixture.criteria(
        searchQuery: 'a',
        favoritesOnly: true,
        primaryTags: const <String>['red'],
        relatedTags: const <String>['common'],
        includeOffline: false,
        sortBy: SortOption.size,
        sortDirection: SortDirection.desc,
      ),
    ];

    for (final criteria in cases) {
      final snapshot = await catalog.fetch(criteria);
      expect(snapshot.loadedVideos.length, snapshot.totalCount);
      expect(snapshot.statistics.totalCount, snapshot.totalCount);
      expect(
        snapshot.statistics.totalDurationSeconds,
        snapshot.loadedVideos.fold<int>(
          0,
          (total, video) => total + video.duration,
        ),
      );
      expect(
        snapshot.statistics.totalSizeBytes,
        snapshot.loadedVideos.fold<int>(
          0,
          (total, video) => total + video.size,
        ),
      );
    }

    final anyMatch = await catalog.fetch(
      fixture.criteria(primaryTags: const <String>['red', 'blue']),
    );
    expect(anyMatch.loadedVideos.map((video) => video.title), [
      'Alpha',
      'Beta',
      'Gamma',
    ]);

    final allMatch = await catalog.fetch(
      fixture.criteria(relatedTags: const <String>['red', 'blue']),
    );
    expect(allMatch.loadedVideos.map((video) => video.title), ['Gamma']);

    final sorted = await catalog.fetch(
      fixture.criteria(
        sortBy: SortOption.size,
        sortDirection: SortDirection.desc,
      ),
    );
    expect(sorted.loadedVideos.map((video) => video.title), [
      'Delta',
      'Gamma',
      'Beta',
      'Alpha',
    ]);

    final combined = await catalog.fetch(cases.last);
    expect(combined.loadedVideos.map((video) => video.title), [
      'Gamma',
      'Alpha',
    ]);

    final empty = await catalog.fetch(
      fixture.criteria(folderIds: const <int>[]),
    );
    expect(empty.loadedVideos, isEmpty);
    expect(empty.totalCount, 0);
    expect(empty.availableTags, isEmpty);
    expect(empty.relatedTags, isEmpty);
    expect(empty.statistics.totalCount, 0);
    expect(empty.statistics.totalDurationSeconds, 0);
    expect(empty.statistics.totalSizeBytes, 0);
  });

  test('pagination changes only the loaded video window', () async {
    final fixture = await _CatalogFixture.create();
    addTearDown(fixture.db.close);
    final catalog = CatalogQueryModule(fixture.db);
    final criteria = fixture.criteria(
      primaryTags: const <String>['red'],
      pageLimit: 1,
    );

    final firstPage = await catalog.fetch(criteria);
    final expanded = await catalog.fetch(criteria.copyWith(pageLimit: 2));

    expect(firstPage.loadedVideos, hasLength(1));
    expect(expanded.loadedVideos, hasLength(2));
    expect(expanded.totalCount, firstPage.totalCount);
    expect(
      _tagCounts(expanded.availableTags),
      _tagCounts(firstPage.availableTags),
    );
    expect(_tagCounts(expanded.relatedTags), _tagCounts(firstPage.relatedTags));
    expect(expanded.statistics.totalCount, firstPage.statistics.totalCount);
    expect(
      expanded.statistics.totalDurationSeconds,
      firstPage.statistics.totalDurationSeconds,
    );
    expect(
      expanded.statistics.totalSizeBytes,
      firstPage.statistics.totalSizeBytes,
    );
    expect(_tagCounts(firstPage.relatedTags), {'common': 2, 'blue': 1});
  });

  test('criteria changes update every derived catalog result', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'showOfflineMedia': false,
      'paginationSize': 1,
    });
    final fixture = await _CatalogFixture.create();
    addTearDown(fixture.db.close);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(fixture.db),
        foldersDaoProvider.overrideWithValue(
          _StaticFoldersDao(fixture.db, fixture.folders),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(catalogSnapshotProvider, (_, _) {});
    addTearDown(subscription.close);

    await container.read(settingsProvider.future);
    await readAsyncValue(container, libraryFoldersProvider);

    var snapshot = await _waitForSnapshot(
      container,
      (value) => value.totalCount == 3 && value.loadedVideos.length == 1,
    );
    expect(snapshot.availableTags.map((entry) => entry.key).toSet(), {
      'blue',
      'common',
      'green',
      'red',
    });

    container.read(catalogControllerProvider.notifier).setSearchQuery('Gamma');
    snapshot = await _waitForSnapshot(
      container,
      (value) =>
          value.totalCount == 1 && value.loadedVideos.single.title == 'Gamma',
    );
    expect(snapshot.statistics.totalDurationSeconds, 30);
    expect(snapshot.availableTags.map((entry) => entry.key).toSet(), {
      'blue',
      'common',
      'red',
    });

    container
        .read(catalogControllerProvider.notifier)
        .showCategory(LibraryCategory.favorites);
    snapshot = await _waitForSnapshot(
      container,
      (value) => value.totalCount == 2 && value.loadedVideos.length == 1,
    );
    final beforePaginationTags = snapshot.availableTags;
    final beforePaginationStats = snapshot.statistics;

    await container.read(catalogPresentationProvider.notifier).loadMore();
    expect(
      container
          .read(catalogPresentationProvider)
          .requireValue
          .snapshot
          .loadedVideos,
      hasLength(2),
    );
    expect(
      container.read(catalogSnapshotProvider).requireValue.loadedVideos,
      hasLength(2),
    );
    snapshot = await _waitForSnapshot(
      container,
      (value) => value.totalCount == 2 && value.loadedVideos.length == 2,
    );
    expect(
      _tagCounts(snapshot.availableTags),
      _tagCounts(beforePaginationTags),
    );
    expect(
      snapshot.statistics.totalDurationSeconds,
      beforePaginationStats.totalDurationSeconds,
    );
    expect(
      snapshot.statistics.totalSizeBytes,
      beforePaginationStats.totalSizeBytes,
    );

    expect(await readAsyncValue(container, selectedVideoCountProvider), 2);
    expect(
      (await readAsyncValue(container, libraryStatsProvider)).totalCount,
      2,
    );
    expect(
      await readAsyncValue(container, filteredVideosProvider),
      hasLength(2),
    );
  });
}

Map<String, int> _tagCounts(List<MapEntry<String, int>> tags) =>
    Map<String, int>.fromEntries(tags);

Future<CatalogSnapshot> _waitForSnapshot(
  ProviderContainer container,
  bool Function(CatalogSnapshot) predicate,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final snapshot = await readAsyncValue(container, catalogSnapshotProvider);
    if (predicate(snapshot)) return snapshot;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Catalog snapshot did not reach expected state.');
}

final class _CatalogFixture {
  const _CatalogFixture({
    required this.db,
    required this.firstPublicFolderId,
    required this.secondPublicFolderId,
    required this.privateFolderId,
    required this.folders,
  });

  final AppDatabase db;
  final int firstPublicFolderId;
  final int secondPublicFolderId;
  final int privateFolderId;
  final List<Folder> folders;

  static Future<_CatalogFixture> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firstPublicFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Library/One'),
    );
    final secondPublicFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Library/Two'),
    );
    final privateFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Library/Private',
        isPrivate: const drift.Value(true),
      ),
    );

    await _insertVideo(
      db,
      folderId: firstPublicFolderId,
      title: 'Alpha',
      duration: 10,
      size: 100,
      favorite: true,
      tags: const <String>['red', 'common'],
    );
    await _insertVideo(
      db,
      folderId: firstPublicFolderId,
      title: 'Beta',
      duration: 20,
      size: 200,
      offline: true,
      tags: const <String>['blue', 'common'],
    );
    await _insertVideo(
      db,
      folderId: secondPublicFolderId,
      title: 'Gamma',
      duration: 30,
      size: 300,
      favorite: true,
      tags: const <String>['red', 'blue', 'common'],
    );
    await _insertVideo(
      db,
      folderId: secondPublicFolderId,
      title: 'Delta',
      duration: 40,
      size: 400,
      tags: const <String>['green', 'common'],
    );
    await _insertVideo(
      db,
      folderId: privateFolderId,
      title: 'Secret',
      duration: 50,
      size: 500,
      favorite: true,
      tags: const <String>['red', 'secret'],
    );

    return _CatalogFixture(
      db: db,
      firstPublicFolderId: firstPublicFolderId,
      secondPublicFolderId: secondPublicFolderId,
      privateFolderId: privateFolderId,
      folders: await db.foldersDao.getAllFolders(),
    );
  }

  CatalogCriteria criteria({
    String searchQuery = '',
    List<String> primaryTags = const <String>[],
    List<String> relatedTags = const <String>[],
    bool favoritesOnly = false,
    SortOption sortBy = SortOption.title,
    SortDirection sortDirection = SortDirection.asc,
    int pageLimit = 100,
    bool includeOffline = true,
    List<int>? folderIds,
  }) {
    return CatalogCriteria(
      searchQuery: searchQuery,
      primaryTags: primaryTags,
      relatedTags: relatedTags,
      favoritesOnly: favoritesOnly,
      sortBy: sortBy,
      sortDirection: sortDirection,
      pageLimit: pageLimit,
      includeOffline: includeOffline,
      folderIds: folderIds ?? <int>[firstPublicFolderId, secondPublicFolderId],
    );
  }
}

Future<void> _insertVideo(
  AppDatabase db, {
  required int folderId,
  required String title,
  required int duration,
  required int size,
  required List<String> tags,
  bool favorite = false,
  bool offline = false,
}) async {
  final path = '/$folderId/$title.mp4';
  await db.videosDao.insertVideo(
    VideosCompanion.insert(
      folderId: folderId,
      absolutePath: path,
      title: title,
      duration: drift.Value(duration),
      size: drift.Value(size),
      isFavorite: drift.Value(favorite),
      isOffline: drift.Value(offline),
    ),
  );
  final video = (await db.videosDao.getVideoByPath(path))!;
  await db.tagsDao.insertTagsBatch(
    tags
        .map(
          (tag) => TagsCompanion.insert(
            videoId: video.id,
            tagText: tag,
            source: const drift.Value('user'),
          ),
        )
        .toList(growable: false),
  );
}

final class _StaticFoldersDao extends FoldersDao {
  _StaticFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Stream<List<Folder>> watchAllFolders() =>
      Stream<List<Folder>>.value(_folders);
}
