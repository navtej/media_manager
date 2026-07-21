import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import 'private_library_controller.dart';
import 'settings_provider.dart';

enum LibraryCategory { all, favorites }

enum SortOption { title, duration, addedAt, size }

enum SortDirection { asc, desc }

final class CatalogCriteria {
  const CatalogCriteria({
    required this.searchQuery,
    required this.primaryTags,
    required this.relatedTags,
    required this.favoritesOnly,
    required this.sortBy,
    required this.sortDirection,
    required this.pageLimit,
    required this.includeOffline,
    required this.folderIds,
  });

  final String searchQuery;
  final List<String> primaryTags;
  final List<String> relatedTags;
  final bool favoritesOnly;
  final SortOption sortBy;
  final SortDirection sortDirection;
  final int pageLimit;
  final bool includeOffline;
  final List<int> folderIds;

  CatalogCriteria copyWith({
    String? searchQuery,
    List<String>? primaryTags,
    List<String>? relatedTags,
    bool? favoritesOnly,
    SortOption? sortBy,
    SortDirection? sortDirection,
    int? pageLimit,
    bool? includeOffline,
    List<int>? folderIds,
  }) {
    return CatalogCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      primaryTags: primaryTags ?? this.primaryTags,
      relatedTags: relatedTags ?? this.relatedTags,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      pageLimit: pageLimit ?? this.pageLimit,
      includeOffline: includeOffline ?? this.includeOffline,
      folderIds: folderIds ?? this.folderIds,
    );
  }
}

final class LibraryStats {
  const LibraryStats({
    required this.totalCount,
    required this.totalDurationSeconds,
    required this.totalSizeBytes,
  });

  final int totalCount;
  final int totalDurationSeconds;
  final int totalSizeBytes;

  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }

  String get formattedSize => formatSize(totalSizeBytes);

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

final class CatalogSnapshot {
  const CatalogSnapshot({
    required this.loadedVideos,
    required this.totalCount,
    required this.availableTags,
    required this.relatedTags,
    required this.statistics,
  });

  static const empty = CatalogSnapshot(
    loadedVideos: <Video>[],
    totalCount: 0,
    availableTags: <MapEntry<String, int>>[],
    relatedTags: <MapEntry<String, int>>[],
    statistics: LibraryStats(
      totalCount: 0,
      totalDurationSeconds: 0,
      totalSizeBytes: 0,
    ),
  );

  final List<Video> loadedVideos;
  final int totalCount;
  final List<MapEntry<String, int>> availableTags;
  final List<MapEntry<String, int>> relatedTags;
  final LibraryStats statistics;
}

/// Owns every persistence query used by Library browsing.
final class CatalogQueryModule {
  const CatalogQueryModule(this.database);

  final AppDatabase database;

  Stream<CatalogSnapshot> watch(CatalogCriteria criteria) {
    if (criteria.folderIds.isEmpty) {
      return Stream<CatalogSnapshot>.value(CatalogSnapshot.empty);
    }

    return database
        .customSelect(
          'SELECT COUNT(*) AS watched_rows FROM videos',
          readsFrom: {
            database.videos,
            database.videoTags,
            database.tagDefinitions,
          },
        )
        .watch()
        .asyncMap((_) => fetch(criteria));
  }

  Future<CatalogSnapshot> fetch(CatalogCriteria criteria) {
    if (criteria.folderIds.isEmpty) {
      return Future<CatalogSnapshot>.value(CatalogSnapshot.empty);
    }
    return database.transaction(() => _fetch(criteria));
  }

  Future<CatalogSnapshot> _fetch(CatalogCriteria criteria) async {
    final predicate = _CatalogPredicate(criteria);
    final rowsVariables = <Variable>[
      ...predicate.variables,
      if (criteria.pageLimit > 0) Variable.withInt(criteria.pageLimit),
    ];
    final rows = await database
        .customSelect(
          'SELECT v.* FROM videos v '
          '${predicate.whereClause} '
          '${_orderBy(criteria)} '
          '${criteria.pageLimit > 0 ? 'LIMIT ?' : ''}',
          variables: rowsVariables,
          readsFrom: {
            database.videos,
            database.videoTags,
            database.tagDefinitions,
          },
        )
        .get();

    final aggregate = await database
        .customSelect(
          '''
            SELECT
              COUNT(*) AS total_count,
              COALESCE(SUM(v.duration), 0) AS total_duration,
              COALESCE(SUM(v.size), 0) AS total_size
            FROM videos v
            ${predicate.whereClause}
          ''',
          variables: predicate.variables,
          readsFrom: {
            database.videos,
            database.videoTags,
            database.tagDefinitions,
          },
        )
        .getSingle();

    final tagRows = await database
        .customSelect(
          '''
            SELECT td.name AS tag_name, COUNT(DISTINCT vt.video_id) AS tag_count
            FROM videos v
            JOIN video_tags vt ON vt.video_id = v.id
            JOIN tag_definitions td ON td.id = vt.tag_id
            ${predicate.whereClause}
            GROUP BY td.name
            ORDER BY tag_count DESC, td.name ASC
          ''',
          variables: predicate.variables,
          readsFrom: {
            database.videos,
            database.videoTags,
            database.tagDefinitions,
          },
        )
        .get();

    final availableTags = tagRows
        .map(
          (row) => MapEntry(
            row.read<String>('tag_name'),
            row.read<int>('tag_count'),
          ),
        )
        .toList(growable: false);
    final primaryTags = criteria.primaryTags.toSet();
    final relatedTags = criteria.primaryTags.isEmpty
        ? const <MapEntry<String, int>>[]
        : availableTags
              .where((entry) => !primaryTags.contains(entry.key))
              .toList(growable: false);
    final totalCount = aggregate.read<int>('total_count');

    return CatalogSnapshot(
      loadedVideos: rows
          .map((row) => database.videos.map(row.data))
          .toList(growable: false),
      totalCount: totalCount,
      availableTags: availableTags,
      relatedTags: relatedTags,
      statistics: LibraryStats(
        totalCount: totalCount,
        totalDurationSeconds: aggregate.read<int>('total_duration'),
        totalSizeBytes: aggregate.read<int>('total_size'),
      ),
    );
  }

  String _orderBy(CatalogCriteria criteria) {
    final column = switch (criteria.sortBy) {
      SortOption.title => 'v.title',
      SortOption.duration => 'v.duration',
      SortOption.addedAt => 'v.file_created_at',
      SortOption.size => 'v.size',
    };
    final direction = criteria.sortDirection == SortDirection.asc
        ? 'ASC'
        : 'DESC';
    return 'ORDER BY $column $direction, v.id $direction';
  }
}

final class _CatalogPredicate {
  _CatalogPredicate(CatalogCriteria criteria) {
    final folderPlaceholders = criteria.folderIds.map((_) => '?').join(',');
    conditions.add('v.folder_id IN ($folderPlaceholders)');
    variables.addAll(
      criteria.folderIds.map((folderId) => Variable.withInt(folderId)),
    );

    if (criteria.primaryTags.isNotEmpty) {
      final placeholders = criteria.primaryTags.map((_) => '?').join(',');
      conditions.add('''
        v.id IN (
          SELECT vt.video_id
          FROM video_tags vt
          JOIN tag_definitions td ON td.id = vt.tag_id
          WHERE td.name IN ($placeholders)
        )
      ''');
      variables.addAll(
        criteria.primaryTags.map((tag) => Variable.withString(tag)),
      );
    }

    if (criteria.relatedTags.isNotEmpty) {
      final placeholders = criteria.relatedTags.map((_) => '?').join(',');
      conditions.add('''
        v.id IN (
          SELECT vt.video_id
          FROM video_tags vt
          JOIN tag_definitions td ON td.id = vt.tag_id
          WHERE td.name IN ($placeholders)
          GROUP BY vt.video_id
          HAVING COUNT(DISTINCT td.name) = ?
        )
      ''');
      variables.addAll(
        criteria.relatedTags.map((tag) => Variable.withString(tag)),
      );
      variables.add(Variable.withInt(criteria.relatedTags.length));
    }

    if (criteria.favoritesOnly) {
      conditions.add('v.is_favorite = 1');
    }
    if (!criteria.includeOffline) {
      conditions.add('v.is_offline = 0');
    }

    final searchQuery = criteria.searchQuery.trim().toLowerCase();
    if (searchQuery.isNotEmpty) {
      conditions.add(
        '(lower(v.title) LIKE ? OR lower(v.absolute_path) LIKE ?)',
      );
      final pattern = '%$searchQuery%';
      variables
        ..add(Variable.withString(pattern))
        ..add(Variable.withString(pattern));
    }
  }

  final List<String> conditions = <String>[];
  final List<Variable> variables = <Variable>[];

  String get whereClause => 'WHERE ${conditions.join(' AND ')}';
}

final class CatalogControlState {
  CatalogControlState({
    required LibraryCategory category,
    required SortOption sortBy,
    required SortDirection sortDirection,
    required String searchQuery,
    required String tagFilterQuery,
    required List<String> primaryTags,
    required List<String> relatedTags,
  }) : this._(
         category: category,
         sortBy: sortBy,
         sortDirection: sortDirection,
         searchQuery: searchQuery,
         tagFilterQuery: tagFilterQuery,
         primaryTags: List<String>.unmodifiable(primaryTags),
         relatedTags: List<String>.unmodifiable(relatedTags),
       );

  const CatalogControlState._({
    required this.category,
    required this.sortBy,
    required this.sortDirection,
    required this.searchQuery,
    required this.tagFilterQuery,
    required this.primaryTags,
    required this.relatedTags,
  });

  factory CatalogControlState.initial() => CatalogControlState(
    category: LibraryCategory.all,
    sortBy: SortOption.addedAt,
    sortDirection: SortDirection.desc,
    searchQuery: '',
    tagFilterQuery: '',
    primaryTags: const <String>[],
    relatedTags: const <String>[],
  );

  final LibraryCategory category;
  final SortOption sortBy;
  final SortDirection sortDirection;
  final String searchQuery;
  final String tagFilterQuery;
  final List<String> primaryTags;
  final List<String> relatedTags;

  List<String> get combinedTags =>
      <String>{...primaryTags, ...relatedTags}.toList(growable: false);

  CatalogControlState copyWith({
    LibraryCategory? category,
    SortOption? sortBy,
    SortDirection? sortDirection,
    String? searchQuery,
    String? tagFilterQuery,
    List<String>? primaryTags,
    List<String>? relatedTags,
  }) {
    return CatalogControlState._(
      category: category ?? this.category,
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      searchQuery: searchQuery ?? this.searchQuery,
      tagFilterQuery: tagFilterQuery ?? this.tagFilterQuery,
      primaryTags: primaryTags == null
          ? this.primaryTags
          : List<String>.unmodifiable(primaryTags),
      relatedTags: relatedTags == null
          ? this.relatedTags
          : List<String>.unmodifiable(relatedTags),
    );
  }
}

final class CatalogController extends Notifier<CatalogControlState> {
  @override
  CatalogControlState build() => CatalogControlState.initial();

  void showCategory(LibraryCategory category) {
    state = state.copyWith(
      category: category,
      searchQuery: '',
      primaryTags: const <String>[],
      relatedTags: const <String>[],
    );
  }

  void setSort(SortOption sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  void toggleSortDirection() {
    state = state.copyWith(
      sortDirection: state.sortDirection == SortDirection.asc
          ? SortDirection.desc
          : SortDirection.asc,
    );
  }

  void setSearchQuery(String searchQuery) {
    if (searchQuery == state.searchQuery) return;
    state = state.copyWith(searchQuery: searchQuery);
  }

  void setTagFilterQuery(String tagFilterQuery) {
    if (tagFilterQuery == state.tagFilterQuery) return;
    state = state.copyWith(tagFilterQuery: tagFilterQuery);
  }

  void togglePrimaryTag(String tag) {
    final primaryTags = state.primaryTags.contains(tag)
        ? state.primaryTags.where((value) => value != tag).toList()
        : <String>[...state.primaryTags, tag];
    state = state.copyWith(
      primaryTags: primaryTags,
      relatedTags: primaryTags.isEmpty ? const <String>[] : state.relatedTags,
    );
  }

  void clearPrimaryTags() {
    state = state.copyWith(
      primaryTags: const <String>[],
      relatedTags: const <String>[],
    );
  }

  void setPrimaryTag(String tag) {
    state = state.copyWith(
      primaryTags: <String>[tag],
      relatedTags: const <String>[],
    );
  }

  void deselectPrimaryTagsNotIn(Iterable<String> availableTags) {
    final available = availableTags.toSet();
    final primaryTags = state.primaryTags
        .where(available.contains)
        .toList(growable: false);
    if (primaryTags.length == state.primaryTags.length) return;
    state = state.copyWith(
      primaryTags: primaryTags,
      relatedTags: primaryTags.isEmpty ? const <String>[] : state.relatedTags,
    );
  }

  void toggleRelatedTag(String tag) {
    final relatedTags = state.relatedTags.contains(tag)
        ? state.relatedTags.where((value) => value != tag).toList()
        : <String>[...state.relatedTags, tag];
    state = state.copyWith(relatedTags: relatedTags);
  }

  void clearSearchAndTags() {
    state = state.copyWith(
      searchQuery: '',
      primaryTags: const <String>[],
      relatedTags: const <String>[],
    );
  }
}

final catalogControllerProvider =
    NotifierProvider<CatalogController, CatalogControlState>(
      CatalogController.new,
    );

final catalogBaseCriteriaProvider = Provider<CatalogCriteria>((ref) {
  final controls = ref.watch(
    catalogControllerProvider.select(
      (state) => (
        category: state.category,
        sortBy: state.sortBy,
        sortDirection: state.sortDirection,
        searchQuery: state.searchQuery,
        primaryTags: state.primaryTags,
        relatedTags: state.relatedTags,
      ),
    ),
  );
  final pageSize = ref.watch(catalogPageSizeProvider);
  return CatalogCriteria(
    searchQuery: controls.searchQuery,
    primaryTags: controls.primaryTags,
    relatedTags: controls.relatedTags,
    favoritesOnly: controls.category == LibraryCategory.favorites,
    sortBy: controls.sortBy,
    sortDirection: controls.sortDirection,
    pageLimit: pageSize,
    includeOffline: ref.watch(showOfflineMediaProvider),
    folderIds: List<int>.unmodifiable(
      ref.watch(effectiveLibraryFolderIdsProvider),
    ),
  );
});

final catalogCriteriaProvider = Provider<CatalogCriteria>((ref) {
  final base = ref.watch(catalogBaseCriteriaProvider);
  final loadedPages = ref.watch(
    catalogPaginationProvider.select(
      (state) => state is AsyncData<CatalogPaginationState>
          ? state.value.loadedPages
          : 1,
    ),
  );
  return base.copyWith(pageLimit: base.pageLimit * loadedPages);
});

final catalogQueryModuleProvider = Provider<CatalogQueryModule>((ref) {
  return CatalogQueryModule(ref.watch(databaseProvider));
});

final catalogWatchProvider =
    Provider<Stream<CatalogSnapshot> Function(CatalogCriteria)>(
      (ref) => ref.watch(catalogQueryModuleProvider).watch,
    );

final catalogFetchProvider =
    Provider<Future<CatalogSnapshot> Function(CatalogCriteria)>(
      (ref) => ref.watch(catalogQueryModuleProvider).fetch,
    );

enum CatalogAppendPhase { idle, loading, failed }

final class CatalogAppendState {
  const CatalogAppendState.idle()
    : phase = CatalogAppendPhase.idle,
      targetPage = null,
      error = null;

  const CatalogAppendState.loading(this.targetPage)
    : phase = CatalogAppendPhase.loading,
      error = null;

  const CatalogAppendState.failed(this.targetPage, this.error)
    : phase = CatalogAppendPhase.failed;

  final CatalogAppendPhase phase;
  final int? targetPage;
  final Object? error;
}

final class CatalogPaginationState {
  const CatalogPaginationState({
    required this.snapshot,
    required this.loadedPages,
    this.append = const CatalogAppendState.idle(),
  });

  final CatalogSnapshot snapshot;
  final int loadedPages;
  final CatalogAppendState append;

  bool get hasMore => snapshot.loadedVideos.length < snapshot.totalCount;
  bool get isAppending => append.phase == CatalogAppendPhase.loading;
  Object? get appendError => append.error;
  int? get failedTargetPage =>
      append.phase == CatalogAppendPhase.failed ? append.targetPage : null;

  CatalogPaginationState copyWith({
    CatalogSnapshot? snapshot,
    int? loadedPages,
    CatalogAppendState? append,
  }) {
    return CatalogPaginationState(
      snapshot: snapshot ?? this.snapshot,
      loadedPages: loadedPages ?? this.loadedPages,
      append: append ?? this.append,
    );
  }
}

final class CatalogPaginationController
    extends AsyncNotifier<CatalogPaginationState> {
  StreamSubscription<CatalogSnapshot>? _subscription;
  CatalogCriteria? _baseCriteria;
  int _generation = 0;

  @override
  Future<CatalogPaginationState> build() async {
    final criteria = ref.watch(catalogBaseCriteriaProvider);
    final generation = ++_generation;
    ref.onDispose(() {
      if (generation != _generation) return;
      _generation++;
      _subscription?.cancel();
    });
    _baseCriteria = criteria;
    final firstSnapshot = Completer<CatalogSnapshot>();
    _replaceSubscription(
      criteria: criteria,
      generation: generation,
      firstSnapshot: firstSnapshot,
    );
    final snapshot = await firstSnapshot.future;
    return CatalogPaginationState(snapshot: snapshot, loadedPages: 1);
  }

  Future<void> loadMore() async {
    final currentAsync = state;
    if (currentAsync is! AsyncData<CatalogPaginationState>) return;
    final current = currentAsync.value;
    if (current.isAppending || !current.hasMore) return;

    final generation = _generation;
    final baseCriteria = _baseCriteria;
    if (baseCriteria == null) return;
    final targetPage = current.failedTargetPage ?? current.loadedPages + 1;
    state = AsyncData(
      current.copyWith(append: CatalogAppendState.loading(targetPage)),
    );

    try {
      final expandedCriteria = baseCriteria.copyWith(
        pageLimit: baseCriteria.pageLimit * targetPage,
      );
      final expanded = await ref.read(catalogFetchProvider)(expandedCriteria);
      if (generation != _generation) return;

      _validateExpandedPrefix(current.snapshot, expanded);
      final next = CatalogPaginationState(
        snapshot: expanded,
        loadedPages: targetPage,
      );
      state = AsyncData(next);
      _replaceSubscription(criteria: expandedCriteria, generation: generation);
    } catch (error) {
      if (generation != _generation) return;
      final latest = state;
      if (latest is! AsyncData<CatalogPaginationState>) return;
      state = AsyncData(
        latest.value.copyWith(
          append: CatalogAppendState.failed(targetPage, error),
        ),
      );
    }
  }

  void _replaceSubscription({
    required CatalogCriteria criteria,
    required int generation,
    Completer<CatalogSnapshot>? firstSnapshot,
  }) {
    final previous = _subscription;
    _subscription = null;
    if (previous != null) unawaited(previous.cancel());
    if (generation != _generation) return;

    _subscription = ref
        .read(catalogWatchProvider)(criteria)
        .listen(
          (snapshot) {
            if (generation != _generation) return;
            if (firstSnapshot != null && !firstSnapshot.isCompleted) {
              firstSnapshot.complete(snapshot);
              return;
            }
            final current = state;
            if (current is AsyncData<CatalogPaginationState>) {
              state = AsyncData(current.value.copyWith(snapshot: snapshot));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (generation != _generation) return;
            if (firstSnapshot != null && !firstSnapshot.isCompleted) {
              firstSnapshot.completeError(error, stackTrace);
              return;
            }
            state = AsyncError<CatalogPaginationState>(error, stackTrace);
          },
        );
  }

  void _validateExpandedPrefix(
    CatalogSnapshot current,
    CatalogSnapshot expanded,
  ) {
    final currentIds = current.loadedVideos.map((video) => video.id).toList();
    final expandedIds = expanded.loadedVideos.map((video) => video.id).toList();
    if (expandedIds.length < currentIds.length ||
        expandedIds.toSet().length != expandedIds.length) {
      throw StateError('Catalog append returned an invalid Video prefix.');
    }
    for (var index = 0; index < currentIds.length; index++) {
      if (currentIds[index] != expandedIds[index]) {
        throw StateError('Catalog append changed the existing Video order.');
      }
    }
  }
}

final catalogPaginationProvider =
    AsyncNotifierProvider<CatalogPaginationController, CatalogPaginationState>(
      CatalogPaginationController.new,
    );

final catalogSnapshotProvider =
    Provider.autoDispose<AsyncValue<CatalogSnapshot>>(
      (ref) => ref
          .watch(catalogPaginationProvider)
          .whenData((presentation) => presentation.snapshot),
    );

final filteredVideosProvider = Provider.autoDispose<AsyncValue<List<Video>>>((
  ref,
) {
  return ref
      .watch(catalogSnapshotProvider)
      .whenData((snapshot) => snapshot.loadedVideos);
});

final selectedVideoCountProvider = Provider.autoDispose<AsyncValue<int>>((ref) {
  return ref
      .watch(catalogSnapshotProvider)
      .whenData((snapshot) => snapshot.totalCount);
});

final libraryStatsProvider = Provider.autoDispose<AsyncValue<LibraryStats>>((
  ref,
) {
  return ref
      .watch(catalogSnapshotProvider)
      .whenData((snapshot) => snapshot.statistics);
});

final allTagsProvider =
    Provider.autoDispose<AsyncValue<List<MapEntry<String, int>>>>((ref) {
      final controls = ref.watch(catalogControllerProvider);
      ref.watch(visibleUniqueTagsProvider).whenData((availableTags) {
        Future<void>.microtask(
          () => ref
              .read(catalogControllerProvider.notifier)
              .deselectPrimaryTagsNotIn(availableTags),
        );
      });
      return ref.watch(catalogSnapshotProvider).whenData((snapshot) {
        final filterQuery = controls.tagFilterQuery.toLowerCase();
        final tags = snapshot.availableTags
            .where(
              (entry) =>
                  filterQuery.isEmpty ||
                  entry.key.toLowerCase().contains(filterQuery),
            )
            .toList();
        tags.sort((a, b) {
          final aSelected = controls.primaryTags.contains(a.key);
          final bSelected = controls.primaryTags.contains(b.key);
          if (aSelected != bSelected) return aSelected ? -1 : 1;
          if (a.value != b.value) return b.value.compareTo(a.value);
          return a.key.compareTo(b.key);
        });
        return tags;
      });
    });

final relatedTagsProvider =
    Provider.autoDispose<AsyncValue<List<MapEntry<String, int>>>>((ref) {
      return ref
          .watch(catalogSnapshotProvider)
          .whenData((snapshot) => snapshot.relatedTags);
    });

// Tag-entry autocomplete is an editor concern, not a browsing facet. Keeping
// its complete Library vocabulary prevents active catalog filters from hiding
// valid tags that a user may want to add.
final visibleUniqueTagsProvider = StreamProvider.autoDispose<List<String>>((
  ref,
) {
  return ref
      .watch(tagsDaoProvider)
      .watchAllUniqueTags(
        folderIds: ref.watch(effectiveLibraryFolderIdsProvider),
      );
});

final selectedCategoryProvider = Provider<LibraryCategory>(
  (ref) =>
      ref.watch(catalogControllerProvider.select((state) => state.category)),
);
final selectedSortProvider = Provider<SortOption>(
  (ref) => ref.watch(catalogControllerProvider.select((state) => state.sortBy)),
);
final selectedSortDirectionProvider = Provider<SortDirection>(
  (ref) => ref.watch(
    catalogControllerProvider.select((state) => state.sortDirection),
  ),
);
final searchQueryProvider = Provider<String>(
  (ref) =>
      ref.watch(catalogControllerProvider.select((state) => state.searchQuery)),
);
final tagFilterQueryProvider = Provider<String>(
  (ref) => ref.watch(
    catalogControllerProvider.select((state) => state.tagFilterQuery),
  ),
);
final primarySelectedTagsProvider = Provider<List<String>>(
  (ref) =>
      ref.watch(catalogControllerProvider.select((state) => state.primaryTags)),
);
final secondarySelectedTagsProvider = Provider<List<String>>(
  (ref) =>
      ref.watch(catalogControllerProvider.select((state) => state.relatedTags)),
);
final combinedSelectedTagsProvider = Provider<List<String>>(
  (ref) => ref.watch(
    catalogControllerProvider.select((state) => state.combinedTags),
  ),
);
final videoLimitProvider = Provider<int>(
  (ref) => ref.watch(catalogCriteriaProvider).pageLimit,
);
