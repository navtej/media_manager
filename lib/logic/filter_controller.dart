import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import '../data/providers.dart';
import 'settings_provider.dart';

part 'filter_controller.g.dart';

enum LibraryCategory { all, favorites }

@riverpod
class SelectedCategory extends _$SelectedCategory {
  @override
  LibraryCategory build() => LibraryCategory.all;
  
  void set(LibraryCategory category) => state = category;
}

@riverpod
class SelectedSort extends _$SelectedSort {
  @override
  SortOption build() => SortOption.addedAt;
  
  void set(SortOption sort) => state = sort;
}

@riverpod
class SelectedSortDirection extends _$SelectedSortDirection {
  @override
  SortDirection build() => SortDirection.desc;
  
  void toggle() => state = state == SortDirection.asc ? SortDirection.desc : SortDirection.asc;
}

@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void set(String query) => state = query;
}

@riverpod
class TagFilterQuery extends _$TagFilterQuery {
  @override
  String build() => '';

  void set(String query) => state = query;
}

@riverpod
class PrimarySelectedTags extends _$PrimarySelectedTags {
  @override
  List<String> build() => [];

  void toggle(String tag) {
    if (state.contains(tag)) {
      state = state.where((t) => t != tag).toList();
    } else {
      state = [...state, tag];
    }
    
    // Logic: If primary becomes empty, we might want to clear secondary?
    // Implementation plan says: "Clearing the Top filtering (Primary) will automatically clear the Related filtering (Secondary)."
    // We can check if state is empty.
    if (state.isEmpty) {
       ref.read(secondarySelectedTagsProvider.notifier).clear();
    }
  }
  
  void clear() {
    state = [];
    ref.read(secondarySelectedTagsProvider.notifier).clear();
  }

  /// Sets the state to a single tag (clears all existing and adds the specified tag)
  void set(String tag) {
    state = [tag];
    ref.read(secondarySelectedTagsProvider.notifier).clear();
  }

  void deselectIfMissing(List<String> availableTags) {
    final newState = state.where((t) => availableTags.contains(t)).toList();
    if (newState.length != state.length) {
      state = newState;
    }
  }
}

@riverpod
class SecondarySelectedTags extends _$SecondarySelectedTags {
  @override
  List<String> build() => [];

  void toggle(String tag) {
    if (state.contains(tag)) {
      state = state.where((t) => t != tag).toList();
    } else {
      state = [...state, tag];
    }
  }
  
  void clear() => state = [];
}

@riverpod
List<String> combinedSelectedTags(Ref ref) {
  final primary = ref.watch(primarySelectedTagsProvider);
  final secondary = ref.watch(secondarySelectedTagsProvider);
  return <String>{...primary, ...secondary}.toList();
}

final filteredVideosProvider = StreamProvider.autoDispose<List<Video>>((ref) {
  final primaryTags = ref.watch(primarySelectedTagsProvider);
  final secondaryTags = ref.watch(secondarySelectedTagsProvider);
  final category = ref.watch(selectedCategoryProvider);
  final sort = ref.watch(selectedSortProvider);
  final direction = ref.watch(selectedSortDirectionProvider);
  final searchQuery = ref.watch(searchQueryProvider);
  final dao = ref.watch(videosDaoProvider);
  
  return dao.searchVideos(
    tagsAny: primaryTags,
    tagsAll: secondaryTags, 
    searchQuery: searchQuery,
    favoritesOnly: category == LibraryCategory.favorites,
    sortBy: sort,
    direction: direction,
    limit: ref.watch(videoLimitProvider), // Use pagination
  );
});

final selectedVideoCountProvider = StreamProvider.autoDispose<int>((ref) {
  final primaryTags = ref.watch(primarySelectedTagsProvider);
  final secondaryTags = ref.watch(secondarySelectedTagsProvider);
  final category = ref.watch(selectedCategoryProvider);
  final searchQuery = ref.watch(searchQueryProvider);
  final dao = ref.watch(videosDaoProvider);
  
  return dao.countVideos(
    tagsAny: primaryTags,
    tagsAll: secondaryTags,
    searchQuery: searchQuery,
    favoritesOnly: category == LibraryCategory.favorites,
  );
});

@riverpod
class VideoLimit extends _$VideoLimit {
  @override
  int build() {
    // Watch all filter providers to auto-reset limit when they change
    ref.watch(primarySelectedTagsProvider);
    ref.watch(secondarySelectedTagsProvider);
    ref.watch(selectedCategoryProvider);
    ref.watch(selectedSortProvider);
    ref.watch(selectedSortDirectionProvider);
    ref.watch(searchQueryProvider);
    
    // Get page size from settings
    final settings = ref.watch(settingsProvider).value;
    return settings?['paginationSize'] ?? 50;
  }
  
  void loadMore() {
    final settings = ref.read(settingsProvider).value;
    final pageSize = settings?['paginationSize'] ?? 50;
    state += pageSize as int;
  }
}

final allTagsProvider = StreamProvider.autoDispose<List<MapEntry<String, int>>>((ref) {
  final selected = ref.watch(primarySelectedTagsProvider);
  final filterQuery = ref.watch(tagFilterQueryProvider).toLowerCase();
  final stream = ref.watch(tagsDaoProvider).watchTagsWithCounts();
  
  return stream.map((tagCounts) {
    var tags = tagCounts.keys.toList();
    
    // Prune selected tags that no longer exist
    Future.microtask(() {
      ref.read(primarySelectedTagsProvider.notifier).deselectIfMissing(tags);
    });

    // Filter by query if present
    if (filterQuery.isNotEmpty) {
      tags = tags.where((t) => t.toLowerCase().contains(filterQuery)).toList();
    }

    final sortedTags = List<String>.from(tags);
    sortedTags.sort((a, b) {
      // 1. By Selection status (selected first)
      final aSelected = selected.contains(a);
      final bSelected = selected.contains(b);
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;

      // 2. By Popularity (count desc)
      final aCount = tagCounts[a] ?? 0;
      final bCount = tagCounts[b] ?? 0;
      if (aCount != bCount) return bCount.compareTo(aCount);

      // 3. Alphabetically
      return a.compareTo(b);
    });

    return sortedTags.map((t) => MapEntry(t, tagCounts[t] ?? 0)).toList();
  });
});

final relatedTagsProvider = FutureProvider.autoDispose<List<MapEntry<String, int>>>((ref) async {
  print('DEBUG: relatedTagsProvider computing...');
  final primarySelected = ref.watch(primarySelectedTagsProvider);
  print('DEBUG: primary selected tags: $primarySelected');
  
  if (primarySelected.isEmpty) {
    print('DEBUG: No tags selected, returning empty related.');
    return [];
  }

  final filteredVideos = await ref.watch(filteredVideosProvider.future);
  print('DEBUG: filteredVideos count: ${filteredVideos.length}');
  
  if (filteredVideos.isEmpty) {
    print('DEBUG: No filtered videos, returning empty related.');
    return [];
  }

  final videoIds = filteredVideos.map((v) => v.id).toList();
  final tagCounts = await ref.read(tagsDaoProvider).getTagsWithCountsForVideos(videoIds);
  print('DEBUG: Raw tag counts from DAO: ${tagCounts.length}');
  
  // Filter out tags that are already selected in PRIMARY.
  // We DO want to show tags selected in Secondary (so they can be unselected).
  final relatedTags = tagCounts.keys.where((t) => !primarySelected.contains(t)).toList();
  print('DEBUG: Related tags after filtering selected: ${relatedTags.length}');

  // Sort by popularity (count desc) then alpha
  relatedTags.sort((a, b) {
    final aCount = tagCounts[a] ?? 0;
    final bCount = tagCounts[b] ?? 0;
    if (aCount != bCount) return bCount.compareTo(aCount);
    return a.compareTo(b);
  });

  return relatedTags.map((t) => MapEntry(t, tagCounts[t] ?? 0)).toList();
});
