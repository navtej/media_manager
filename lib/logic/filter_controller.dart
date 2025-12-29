import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import '../data/providers.dart';

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
  SortOption build() => SortOption.title;
  
  void set(SortOption sort) => state = sort;
}

@riverpod
class SelectedSortDirection extends _$SelectedSortDirection {
  @override
  SortDirection build() => SortDirection.asc;
  
  void toggle() => state = state == SortDirection.asc ? SortDirection.desc : SortDirection.asc;
}

@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void set(String query) => state = query;
}

@riverpod
class SelectedTags extends _$SelectedTags {
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

  void deselectIfMissing(List<String> availableTags) {
    final newState = state.where((t) => availableTags.contains(t)).toList();
    if (newState.length != state.length) {
      state = newState;
    }
  }
}

final filteredVideosProvider = StreamProvider.autoDispose<List<Video>>((ref) {
  final tags = ref.watch(selectedTagsProvider);
  final category = ref.watch(selectedCategoryProvider);
  final sort = ref.watch(selectedSortProvider);
  final direction = ref.watch(selectedSortDirectionProvider);
  final searchQuery = ref.watch(searchQueryProvider);
  final dao = ref.watch(videosDaoProvider);
  
  return dao.searchVideos(
    tags, 
    searchQuery: searchQuery,
    favoritesOnly: category == LibraryCategory.favorites,
    sortBy: sort,
    direction: direction,
  );
});

final allTagsProvider = StreamProvider.autoDispose<List<String>>((ref) {
  final selected = ref.watch(selectedTagsProvider);
  final stream = ref.watch(tagsDaoProvider).watchTagsWithCounts();
  
  return stream.map((tagCounts) {
    final tags = tagCounts.keys.toList();
    
    // Prune selected tags that no longer exist
    Future.microtask(() {
      ref.read(selectedTagsProvider.notifier).deselectIfMissing(tags);
    });

    final sorted = List<String>.from(tags);
    sorted.sort((a, b) {
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
    return sorted;
  });
});
