import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/catalog_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/ui/widgets/video_grid.dart';

void main() {
  test(
    'append allows one request and publishes only an expanded prefix',
    () async {
      final query = _ControlledCatalogQuery(_snapshot(2, totalCount: 6));
      addTearDown(query.close);
      final container = _container(query);
      addTearDown(container.dispose);

      await container.read(catalogPaginationProvider.future);
      final controller = container.read(catalogPaginationProvider.notifier);

      final firstAppend = controller.loadMore();
      final duplicateAppend = controller.loadMore();

      expect(query.fetchLimits, [4]);
      expect(
        container
            .read(catalogPaginationProvider)
            .requireValue
            .snapshot
            .loadedVideos,
        hasLength(2),
      );
      expect(
        container.read(catalogPaginationProvider).requireValue.isAppending,
        isTrue,
      );

      query.completeNext(_snapshot(4, totalCount: 6));
      await Future.wait([firstAppend, duplicateAppend]);

      final presentation = container
          .read(catalogPaginationProvider)
          .requireValue;
      expect(presentation.snapshot.loadedVideos.map((video) => video.id), [
        1,
        2,
        3,
        4,
      ]);
      expect(presentation.loadedPages, 2);
      expect(presentation.isAppending, isFalse);
      expect(presentation.appendError, isNull);
    },
  );

  test(
    'append failure retains content and retry requests the same page',
    () async {
      final query = _ControlledCatalogQuery(_snapshot(2, totalCount: 6));
      addTearDown(query.close);
      final container = _container(query);
      addTearDown(container.dispose);

      await container.read(catalogPaginationProvider.future);
      final controller = container.read(catalogPaginationProvider.notifier);

      final failedAppend = controller.loadMore();
      query.failNext(StateError('offline'));
      await failedAppend;

      var presentation = container.read(catalogPaginationProvider).requireValue;
      expect(presentation.snapshot.loadedVideos, hasLength(2));
      expect(presentation.loadedPages, 1);
      expect(presentation.failedTargetPage, 2);
      expect(presentation.appendError, isA<StateError>());

      final retry = controller.loadMore();
      expect(query.fetchLimits, [4, 4]);
      query.completeNext(_snapshot(4, totalCount: 6));
      await retry;

      presentation = container.read(catalogPaginationProvider).requireValue;
      expect(presentation.snapshot.loadedVideos, hasLength(4));
      expect(presentation.loadedPages, 2);
      expect(presentation.failedTargetPage, isNull);
    },
  );

  test('loadMore is a no-op when every matching Video is loaded', () async {
    final query = _ControlledCatalogQuery(_snapshot(2, totalCount: 2));
    addTearDown(query.close);
    final container = _container(query);
    addTearDown(container.dispose);

    await container.read(catalogPaginationProvider.future);
    await container.read(catalogPaginationProvider.notifier).loadMore();

    expect(query.fetchLimits, isEmpty);
  });

  test(
    'invalid expanded prefixes are rejected without replacing content',
    () async {
      final query = _ControlledCatalogQuery(_snapshot(2, totalCount: 6));
      addTearDown(query.close);
      final container = _container(query);
      addTearDown(container.dispose);

      await container.read(catalogPaginationProvider.future);
      final append = container
          .read(catalogPaginationProvider.notifier)
          .loadMore();
      query.completeNext(
        CatalogSnapshot(
          loadedVideos: [
            ..._snapshot(2, totalCount: 6).loadedVideos,
            _snapshot(1, totalCount: 6).loadedVideos.single,
          ],
          totalCount: 6,
          availableTags: const [],
          relatedTags: const [],
          statistics: const LibraryStats(
            totalCount: 6,
            totalDurationSeconds: 360,
            totalSizeBytes: 6144,
          ),
        ),
      );
      await append;

      final presentation = container
          .read(catalogPaginationProvider)
          .requireValue;
      expect(presentation.snapshot.loadedVideos.map((video) => video.id), [
        1,
        2,
      ]);
      expect(presentation.appendError, isA<StateError>());
      expect(presentation.failedTargetPage, 2);
    },
  );

  test('criteria refresh rejects stale append success and error', () async {
    final query = _ControlledCatalogQuery(_snapshot(2, totalCount: 6))
      ..watchSnapshots['new'] = _snapshot(1, totalCount: 1, firstId: 20);
    addTearDown(query.close);
    final container = _container(query);
    addTearDown(container.dispose);

    await container.read(catalogPaginationProvider.future);
    final staleSuccess = container
        .read(catalogPaginationProvider.notifier)
        .loadMore();

    container
        .read(_testCriteriaProvider.notifier)
        .setCriteria(_criteria(searchQuery: 'new'));
    final refreshed = await container.read(catalogPaginationProvider.future);
    expect(refreshed.snapshot.loadedVideos.single.id, 20);
    expect(refreshed.loadedPages, 1);

    query.completeNext(_snapshot(4, totalCount: 6));
    await staleSuccess;
    expect(
      container
          .read(catalogPaginationProvider)
          .requireValue
          .snapshot
          .loadedVideos
          .single
          .id,
      20,
    );

    container.read(_testCriteriaProvider.notifier).setCriteria(_criteria());
    await container.read(catalogPaginationProvider.future);
    final staleError = container
        .read(catalogPaginationProvider.notifier)
        .loadMore();
    container
        .read(_testCriteriaProvider.notifier)
        .setCriteria(_criteria(searchQuery: 'new'));
    await container.read(catalogPaginationProvider.future);
    query.failNext(StateError('stale'));
    await staleError;

    final finalState = container.read(catalogPaginationProvider).requireValue;
    expect(finalState.snapshot.loadedVideos.single.id, 20);
    expect(finalState.appendError, isNull);
  });

  test('criteria change exposes page one while refresh is pending', () async {
    final query = _ControlledCatalogQuery(_snapshot(2, totalCount: 6));
    addTearDown(query.close);
    final container = _container(query);
    addTearDown(container.dispose);

    await container.read(catalogPaginationProvider.future);
    final append = container
        .read(catalogPaginationProvider.notifier)
        .loadMore();
    query.completeNext(_snapshot(4, totalCount: 6));
    await append;
    expect(container.read(catalogCriteriaProvider).pageLimit, 4);

    container
        .read(_testCriteriaProvider.notifier)
        .setCriteria(_criteria(searchQuery: 'new', pageLimit: 3));

    expect(container.read(catalogCriteriaProvider).pageLimit, 3);
  });

  testWidgets(
    'automatic pagination keeps mounted Videos and scroll offset across pages',
    (tester) async {
      final query = _ControlledCatalogQuery(_snapshot(12, totalCount: 36));
      addTearDown(query.close);
      final folder = Folder(
        id: 1,
        path: '/Library',
        alias: 'Library',
        isPrivate: false,
        addedAt: DateTime(2026, 7, 21),
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogBaseCriteriaProvider.overrideWithValue(
              _criteria(pageLimit: 12),
            ),
            catalogWatchProvider.overrideWithValue(query.watch),
            catalogFetchProvider.overrideWithValue(query.fetch),
            foldersDaoProvider.overrideWithValue(
              _TestFoldersDao(query.database, [folder]),
            ),
            tagsDaoProvider.overrideWithValue(_TestTagsDao(query.database)),
            videoSummariesDaoProvider.overrideWithValue(
              _TestVideoSummariesDao(query.database),
            ),
            settingsProvider.overrideWith(_TestSettings.new),
          ],
          child: MacosApp(
            home: MacosWindow(
              child: MacosScaffold(
                children: [
                  ContentArea(
                    builder: (context, _) => SizedBox(
                      width: 800,
                      height: 600,
                      child: CatalogScrollView(
                        scrollController: scrollController,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();

      expect(query.fetchLimits, [24]);
      expect(find.text('Loading more Videos…'), findsOneWidget);
      final visibleWhilePending = _visibleIds(tester).toList();
      expect(visibleWhilePending, isNotEmpty);
      expect(visibleWhilePending, everyElement(lessThanOrEqualTo(12)));
      final pendingOffset = scrollController.offset;
      expect(pendingOffset, greaterThan(0));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pump();
      expect(query.fetchLimits, [24]);
      expect(scrollController.offset, closeTo(pendingOffset, 80));
      final stablePendingOffset = scrollController.offset;

      query.failNext(StateError('offline'));
      await tester.pumpAndSettle();
      expect(scrollController.offset, closeTo(stablePendingOffset, 1));
      expect(find.text('Couldn’t load more Videos.'), findsOneWidget);
      expect(_visibleIds(tester), containsAll(visibleWhilePending));

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(query.fetchLimits, [24, 24]);
      final retryPendingOffset = scrollController.offset;
      query.completeNext(_snapshot(24, totalCount: 36));
      await tester.pumpAndSettle();
      expect(scrollController.offset, closeTo(retryPendingOffset, 1));
      expect(_visibleIds(tester), containsAll(visibleWhilePending));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
      await tester.pump();
      expect(query.fetchLimits, [24, 24, 36]);
      final secondPendingOffset = scrollController.offset;

      query.completeNext(_snapshot(36, totalCount: 36));
      await tester.pumpAndSettle();
      expect(scrollController.offset, closeTo(secondPendingOffset, 1));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CatalogScrollView)),
      );
      expect(
        container
            .read(catalogPaginationProvider)
            .requireValue
            .snapshot
            .loadedVideos
            .map((video) => video.id),
        List.generate(36, (index) => index + 1),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('list presentation keeps content mounted during pagination', (
    tester,
  ) async {
    final query = _ControlledCatalogQuery(_snapshot(12, totalCount: 24));
    addTearDown(query.close);
    final folder = Folder(
      id: 1,
      path: '/Library',
      alias: 'Library',
      isPrivate: false,
      addedAt: DateTime(2026, 7, 21),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogBaseCriteriaProvider.overrideWithValue(
            _criteria(pageLimit: 12),
          ),
          catalogWatchProvider.overrideWithValue(query.watch),
          catalogFetchProvider.overrideWithValue(query.fetch),
          foldersDaoProvider.overrideWithValue(
            _TestFoldersDao(query.database, [folder]),
          ),
          tagsDaoProvider.overrideWithValue(_TestTagsDao(query.database)),
          videoSummariesDaoProvider.overrideWithValue(
            _TestVideoSummariesDao(query.database),
          ),
          settingsProvider.overrideWith(_TestListSettings.new),
        ],
        child: MacosApp(
          home: MacosWindow(
            child: SizedBox(
              width: 800,
              height: 600,
              child: CatalogScrollView(scrollController: scrollController),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pump();
    expect(query.fetchLimits, [24]);
    expect(find.text('Loading more Videos…'), findsOneWidget);
    expect(_visibleIds(tester), isNotEmpty);
    final pendingOffset = scrollController.offset;

    query.completeNext(_snapshot(24, totalCount: 24));
    await tester.pumpAndSettle();
    expect(scrollController.offset, closeTo(pendingOffset, 1));
    expect(
      ProviderScope.containerOf(tester.element(find.byType(CatalogScrollView)))
          .read(catalogPaginationProvider)
          .requireValue
          .snapshot
          .loadedVideos
          .map((video) => video.id),
      List.generate(24, (index) => index + 1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Iterable<int> _visibleIds(WidgetTester tester) => tester
    .widgetList<VideoGridItem>(find.byType(VideoGridItem))
    .map((item) => item.video.id);

final _testCriteriaProvider =
    NotifierProvider<_TestCriteriaController, CatalogCriteria>(
      _TestCriteriaController.new,
    );

class _TestCriteriaController extends Notifier<CatalogCriteria> {
  @override
  CatalogCriteria build() => _criteria();

  void setCriteria(CatalogCriteria criteria) => state = criteria;
}

ProviderContainer _container(_ControlledCatalogQuery query) {
  return ProviderContainer(
    overrides: [
      catalogBaseCriteriaProvider.overrideWith(
        (ref) => ref.watch(_testCriteriaProvider),
      ),
      catalogWatchProvider.overrideWithValue(query.watch),
      catalogFetchProvider.overrideWithValue(query.fetch),
    ],
  );
}

CatalogCriteria _criteria({String searchQuery = '', int pageLimit = 2}) =>
    CatalogCriteria(
      searchQuery: searchQuery,
      primaryTags: const [],
      relatedTags: const [],
      favoritesOnly: false,
      sortBy: SortOption.addedAt,
      sortDirection: SortDirection.desc,
      pageLimit: pageLimit,
      includeOffline: false,
      folderIds: const [1],
    );

CatalogSnapshot _snapshot(
  int count, {
  required int totalCount,
  int firstId = 1,
}) {
  final now = DateTime(2026, 7, 21);
  return CatalogSnapshot(
    loadedVideos: List.generate(count, (index) {
      final id = firstId + index;
      return Video(
        id: id,
        folderId: 1,
        absolutePath: '/Library/video-$id.mp4',
        title: 'Video $id',
        duration: 60,
        size: 1024,
        metadataJson: '{}',
        isOffline: false,
        isFavorite: false,
        addedAt: now,
        fileCreatedAt: now,
        aiProcessed: false,
      );
    }),
    totalCount: totalCount,
    availableTags: const [MapEntry('tag', 1)],
    relatedTags: const [],
    statistics: LibraryStats(
      totalCount: totalCount,
      totalDurationSeconds: totalCount * 60,
      totalSizeBytes: totalCount * 1024,
    ),
  );
}

final class _ControlledCatalogQuery {
  _ControlledCatalogQuery(this.initialSnapshot)
    : _latestSnapshot = initialSnapshot,
      database = AppDatabase.forTesting(NativeDatabase.memory());

  final AppDatabase database;
  final CatalogSnapshot initialSnapshot;
  CatalogSnapshot _latestSnapshot;
  final Map<String, CatalogSnapshot> watchSnapshots = {};
  final List<int> fetchLimits = [];
  final List<Completer<CatalogSnapshot>> _pending = [];

  Stream<CatalogSnapshot> watch(CatalogCriteria criteria) => Stream.value(
    watchSnapshots[criteria.searchQuery] ??
        (criteria.pageLimit == initialSnapshot.loadedVideos.length
            ? initialSnapshot
            : _latestSnapshot),
  );

  Future<CatalogSnapshot> fetch(CatalogCriteria criteria) {
    fetchLimits.add(criteria.pageLimit);
    final completer = Completer<CatalogSnapshot>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext(CatalogSnapshot snapshot) {
    _latestSnapshot = snapshot;
    _pending.removeAt(0).complete(snapshot);
  }

  void failNext(Object error) {
    _pending.removeAt(0).completeError(error, StackTrace.current);
  }

  Future<void> close() async {
    await database.close();
  }
}

class _TestSettings extends Settings {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _TestListSettings extends Settings {
  @override
  Future<AppSettings> build() async => AppSettings.defaults.copyWith(
    catalogBrowsing: CatalogBrowsingConfiguration.resolve(
      presentationValue: CatalogPresentation.list.value,
    ),
  );
}

class _TestFoldersDao extends FoldersDao {
  _TestFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Future<List<Folder>> getAllFolders() async => _folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);
}

class _TestTagsDao extends TagsDao {
  _TestTagsDao(super.db);

  @override
  Stream<List<Tag>> watchTagsForVideo(int videoId) => Stream.value(const []);

  @override
  Stream<List<String>> watchAllUniqueTags({List<int>? folderIds}) =>
      Stream.value(const []);
}

class _TestVideoSummariesDao extends VideoSummariesDao {
  _TestVideoSummariesDao(super.db);

  @override
  Stream<VideoSummary?> watchSummaryForVideo(int videoId) => Stream.value(null);
}
