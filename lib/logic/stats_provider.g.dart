// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dataFolderSize)
final dataFolderSizeProvider = DataFolderSizeProvider._();

final class DataFolderSizeProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  DataFolderSizeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dataFolderSizeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dataFolderSizeHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return dataFolderSize(ref);
  }
}

String _$dataFolderSizeHash() => r'd7eef207e0a63e534df1f057e6d8cab5e81e15fe';
