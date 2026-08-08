// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(database)
final databaseProvider = DatabaseProvider._();

final class DatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  DatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return database(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$databaseHash() => r'7a4761867a2456e635b79bf242c57e14abd4d7e2';

@ProviderFor(foldersDao)
final foldersDaoProvider = FoldersDaoProvider._();

final class FoldersDaoProvider
    extends $FunctionalProvider<FoldersDao, FoldersDao, FoldersDao>
    with $Provider<FoldersDao> {
  FoldersDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'foldersDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$foldersDaoHash();

  @$internal
  @override
  $ProviderElement<FoldersDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FoldersDao create(Ref ref) {
    return foldersDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FoldersDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FoldersDao>(value),
    );
  }
}

String _$foldersDaoHash() => r'e04711ac611ae61f1583122aa082661c4f7955d5';

@ProviderFor(libraryGroupsDao)
final libraryGroupsDaoProvider = LibraryGroupsDaoProvider._();

final class LibraryGroupsDaoProvider
    extends
        $FunctionalProvider<
          LibraryGroupsDao,
          LibraryGroupsDao,
          LibraryGroupsDao
        >
    with $Provider<LibraryGroupsDao> {
  LibraryGroupsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryGroupsDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryGroupsDaoHash();

  @$internal
  @override
  $ProviderElement<LibraryGroupsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LibraryGroupsDao create(Ref ref) {
    return libraryGroupsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryGroupsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryGroupsDao>(value),
    );
  }
}

String _$libraryGroupsDaoHash() => r'8b4ee35070d897262370e6e577638bea8f9a7a89';

@ProviderFor(videosDao)
final videosDaoProvider = VideosDaoProvider._();

final class VideosDaoProvider
    extends $FunctionalProvider<VideosDao, VideosDao, VideosDao>
    with $Provider<VideosDao> {
  VideosDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videosDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videosDaoHash();

  @$internal
  @override
  $ProviderElement<VideosDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VideosDao create(Ref ref) {
    return videosDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideosDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideosDao>(value),
    );
  }
}

String _$videosDaoHash() => r'b6df8201670549e0d4355ce80efd63d9197a7c94';

@ProviderFor(tagsDao)
final tagsDaoProvider = TagsDaoProvider._();

final class TagsDaoProvider
    extends $FunctionalProvider<TagsDao, TagsDao, TagsDao>
    with $Provider<TagsDao> {
  TagsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tagsDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tagsDaoHash();

  @$internal
  @override
  $ProviderElement<TagsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TagsDao create(Ref ref) {
    return tagsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TagsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TagsDao>(value),
    );
  }
}

String _$tagsDaoHash() => r'de4ac29767040e0decf830b84549fbe1d513f411';

@ProviderFor(videoSummariesDao)
final videoSummariesDaoProvider = VideoSummariesDaoProvider._();

final class VideoSummariesDaoProvider
    extends
        $FunctionalProvider<
          VideoSummariesDao,
          VideoSummariesDao,
          VideoSummariesDao
        >
    with $Provider<VideoSummariesDao> {
  VideoSummariesDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'videoSummariesDaoProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$videoSummariesDaoHash();

  @$internal
  @override
  $ProviderElement<VideoSummariesDao> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  VideoSummariesDao create(Ref ref) {
    return videoSummariesDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VideoSummariesDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VideoSummariesDao>(value),
    );
  }
}

String _$videoSummariesDaoHash() => r'ee9a876602283d04ed6194466cdf78d6dc326939';

@ProviderFor(allUniqueTags)
final allUniqueTagsProvider = AllUniqueTagsProvider._();

final class AllUniqueTagsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          Stream<List<String>>
        >
    with $FutureModifier<List<String>>, $StreamProvider<List<String>> {
  AllUniqueTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allUniqueTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allUniqueTagsHash();

  @$internal
  @override
  $StreamProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<String>> create(Ref ref) {
    return allUniqueTags(ref);
  }
}

String _$allUniqueTagsHash() => r'0926d5f694824477a05333d247fee659bbd93b72';
