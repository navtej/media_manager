// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(libraryStats)
final libraryStatsProvider = LibraryStatsProvider._();

final class LibraryStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<LibraryStats>,
          LibraryStats,
          Stream<LibraryStats>
        >
    with $FutureModifier<LibraryStats>, $StreamProvider<LibraryStats> {
  LibraryStatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryStatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryStatsHash();

  @$internal
  @override
  $StreamProviderElement<LibraryStats> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<LibraryStats> create(Ref ref) {
    return libraryStats(ref);
  }
}

String _$libraryStatsHash() => r'90e77f9633c383af8500672ead864fa987354056';
