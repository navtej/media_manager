// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'filter_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SelectedCategory)
final selectedCategoryProvider = SelectedCategoryProvider._();

final class SelectedCategoryProvider
    extends $NotifierProvider<SelectedCategory, LibraryCategory> {
  SelectedCategoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedCategoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedCategoryHash();

  @$internal
  @override
  SelectedCategory create() => SelectedCategory();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryCategory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryCategory>(value),
    );
  }
}

String _$selectedCategoryHash() => r'd174c4b8647a0599f23d85d4b5bd6dd5cf53d83e';

abstract class _$SelectedCategory extends $Notifier<LibraryCategory> {
  LibraryCategory build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<LibraryCategory, LibraryCategory>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LibraryCategory, LibraryCategory>,
              LibraryCategory,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SelectedSort)
final selectedSortProvider = SelectedSortProvider._();

final class SelectedSortProvider
    extends $NotifierProvider<SelectedSort, SortOption> {
  SelectedSortProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedSortProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedSortHash();

  @$internal
  @override
  SelectedSort create() => SelectedSort();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SortOption value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SortOption>(value),
    );
  }
}

String _$selectedSortHash() => r'60f54db6d779b5a74a6613c6c38ff7a0950d73d7';

abstract class _$SelectedSort extends $Notifier<SortOption> {
  SortOption build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SortOption, SortOption>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SortOption, SortOption>,
              SortOption,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SelectedSortDirection)
final selectedSortDirectionProvider = SelectedSortDirectionProvider._();

final class SelectedSortDirectionProvider
    extends $NotifierProvider<SelectedSortDirection, SortDirection> {
  SelectedSortDirectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedSortDirectionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedSortDirectionHash();

  @$internal
  @override
  SelectedSortDirection create() => SelectedSortDirection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SortDirection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SortDirection>(value),
    );
  }
}

String _$selectedSortDirectionHash() =>
    r'bf95bf01c93c25106dceb02e7dbb5f5848e7c093';

abstract class _$SelectedSortDirection extends $Notifier<SortDirection> {
  SortDirection build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SortDirection, SortDirection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SortDirection, SortDirection>,
              SortDirection,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SearchQuery)
final searchQueryProvider = SearchQueryProvider._();

final class SearchQueryProvider extends $NotifierProvider<SearchQuery, String> {
  SearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchQueryHash();

  @$internal
  @override
  SearchQuery create() => SearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$searchQueryHash() => r'2ab221c441fd042c8cbf58b17e7e766363f36b6f';

abstract class _$SearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SelectedTags)
final selectedTagsProvider = SelectedTagsProvider._();

final class SelectedTagsProvider
    extends $NotifierProvider<SelectedTags, List<String>> {
  SelectedTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedTagsHash();

  @$internal
  @override
  SelectedTags create() => SelectedTags();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$selectedTagsHash() => r'2945b05cf7e783625753edf72bacf9985324765a';

abstract class _$SelectedTags extends $Notifier<List<String>> {
  List<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<String>, List<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<String>, List<String>>,
              List<String>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
