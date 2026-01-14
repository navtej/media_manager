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

String _$selectedSortHash() => r'1da1b43d614fb59e45ae9044526a111e0cb1fdcd';

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
    r'97001b6c3df6c5e2ddb80b6faaadccbbacc83283';

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

@ProviderFor(TagFilterQuery)
final tagFilterQueryProvider = TagFilterQueryProvider._();

final class TagFilterQueryProvider
    extends $NotifierProvider<TagFilterQuery, String> {
  TagFilterQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tagFilterQueryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tagFilterQueryHash();

  @$internal
  @override
  TagFilterQuery create() => TagFilterQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$tagFilterQueryHash() => r'e4e0daa9ee6fc4ba18726eff0c036c5cbdbe7cdd';

abstract class _$TagFilterQuery extends $Notifier<String> {
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

@ProviderFor(PrimarySelectedTags)
final primarySelectedTagsProvider = PrimarySelectedTagsProvider._();

final class PrimarySelectedTagsProvider
    extends $NotifierProvider<PrimarySelectedTags, List<String>> {
  PrimarySelectedTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'primarySelectedTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$primarySelectedTagsHash();

  @$internal
  @override
  PrimarySelectedTags create() => PrimarySelectedTags();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$primarySelectedTagsHash() =>
    r'68a44904eac559fd65961e1cd4a90d0f385d38b5';

abstract class _$PrimarySelectedTags extends $Notifier<List<String>> {
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

@ProviderFor(SecondarySelectedTags)
final secondarySelectedTagsProvider = SecondarySelectedTagsProvider._();

final class SecondarySelectedTagsProvider
    extends $NotifierProvider<SecondarySelectedTags, List<String>> {
  SecondarySelectedTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'secondarySelectedTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$secondarySelectedTagsHash();

  @$internal
  @override
  SecondarySelectedTags create() => SecondarySelectedTags();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$secondarySelectedTagsHash() =>
    r'a27d4683c7e1684e57f8f9ac6736f7be11a4d0e4';

abstract class _$SecondarySelectedTags extends $Notifier<List<String>> {
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

@ProviderFor(combinedSelectedTags)
final combinedSelectedTagsProvider = CombinedSelectedTagsProvider._();

final class CombinedSelectedTagsProvider
    extends $FunctionalProvider<List<String>, List<String>, List<String>>
    with $Provider<List<String>> {
  CombinedSelectedTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'combinedSelectedTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$combinedSelectedTagsHash();

  @$internal
  @override
  $ProviderElement<List<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<String> create(Ref ref) {
    return combinedSelectedTags(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$combinedSelectedTagsHash() =>
    r'2a88e91bb2bbc918f15d0a5e1adaf83604efde4b';

@ProviderFor(VideoLimit)
final videoLimitProvider = VideoLimitProvider._();

final class VideoLimitProvider extends $NotifierProvider<VideoLimit, int> {
  VideoLimitProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoLimitProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videoLimitHash();

  @$internal
  @override
  VideoLimit create() => VideoLimit();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$videoLimitHash() => r'10e99d7906e6e3541efb257f11c8a4deb615bfe6';

abstract class _$VideoLimit extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
