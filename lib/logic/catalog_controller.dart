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
    required this.category,
    required this.sortBy,
    required this.sortDirection,
    required this.searchQuery,
    required this.tagFilterQuery,
    required List<String> primaryTags,
    required List<String> relatedTags,
    required this.loadedPages,
  }) : primaryTags = List<String>.unmodifiable(primaryTags),
       relatedTags = List<String>.unmodifiable(relatedTags);

  factory CatalogControlState.initial() => CatalogControlState(
    category: LibraryCategory.all,
    sortBy: SortOption.addedAt,
    sortDirection: SortDirection.desc,
    searchQuery: '',
    tagFilterQuery: '',
    primaryTags: const <String>[],
    relatedTags: const <String>[],
    loadedPages: 1,
  );

  final LibraryCategory category;
  final SortOption sortBy;
  final SortDirection sortDirection;
  final String searchQuery;
  final String tagFilterQuery;
  final List<String> primaryTags;
  final List<String> relatedTags;
  final int loadedPages;

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
    int? loadedPages,
  }) {
    return CatalogControlState(
      category: category ?? this.category,
      sortBy: sortBy ?? this.sortBy,
      sortDirection: sortDirection ?? this.sortDirection,
      searchQuery: searchQuery ?? this.searchQuery,
      tagFilterQuery: tagFilterQuery ?? this.tagFilterQuery,
      primaryTags: primaryTags ?? this.primaryTags,
      relatedTags: relatedTags ?? this.relatedTags,
      loadedPages: loadedPages ?? this.loadedPages,
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
      loadedPages: 1,
    );
  }

  void setSort(SortOption sortBy) {
    state = state.copyWith(sortBy: sortBy, loadedPages: 1);
  }

  void toggleSortDirection() {
    state = state.copyWith(
      sortDirection: state.sortDirection == SortDirection.asc
          ? SortDirection.desc
          : SortDirection.asc,
      loadedPages: 1,
    );
  }

  void setSearchQuery(String searchQuery) {
    if (searchQuery == state.searchQuery) return;
    state = state.copyWith(searchQuery: searchQuery, loadedPages: 1);
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
      loadedPages: 1,
    );
  }

  void clearPrimaryTags() {
    state = state.copyWith(
      primaryTags: const <String>[],
      relatedTags: const <String>[],
      loadedPages: 1,
    );
  }

  void setPrimaryTag(String tag) {
    state = state.copyWith(
      primaryTags: <String>[tag],
      relatedTags: const <String>[],
      loadedPages: 1,
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
      loadedPages: 1,
    );
  }

  void toggleRelatedTag(String tag) {
    final relatedTags = state.relatedTags.contains(tag)
        ? state.relatedTags.where((value) => value != tag).toList()
        : <String>[...state.relatedTags, tag];
    state = state.copyWith(relatedTags: relatedTags, loadedPages: 1);
  }

  void clearSearchAndTags() {
    state = state.copyWith(
      searchQuery: '',
      primaryTags: const <String>[],
      relatedTags: const <String>[],
      loadedPages: 1,
    );
  }

  void loadMore() {
    state = state.copyWith(loadedPages: state.loadedPages + 1);
  }
}

final catalogControllerProvider =
    NotifierProvider<CatalogController, CatalogControlState>(
      CatalogController.new,
    );

final catalogCriteriaProvider = Provider<CatalogCriteria>((ref) {
  final controls = ref.watch(catalogControllerProvider);
  final pageSize = ref.watch(catalogPageSizeProvider);
  return CatalogCriteria(
    searchQuery: controls.searchQuery,
    primaryTags: controls.primaryTags,
    relatedTags: controls.relatedTags,
    favoritesOnly: controls.category == LibraryCategory.favorites,
    sortBy: controls.sortBy,
    sortDirection: controls.sortDirection,
    pageLimit: controls.loadedPages * pageSize,
    includeOffline: ref.watch(showOfflineMediaProvider),
    folderIds: List<int>.unmodifiable(
      ref.watch(effectiveLibraryFolderIdsProvider),
    ),
  );
});

final catalogQueryModuleProvider = Provider<CatalogQueryModule>((ref) {
  return CatalogQueryModule(ref.watch(databaseProvider));
});

final catalogSnapshotProvider = StreamProvider.autoDispose<CatalogSnapshot>((
  ref,
) {
  return ref
      .watch(catalogQueryModuleProvider)
      .watch(ref.watch(catalogCriteriaProvider));
});

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
