// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ScanStatus)
final scanStatusProvider = ScanStatusProvider._();

final class ScanStatusProvider extends $NotifierProvider<ScanStatus, String> {
  ScanStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scanStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scanStatusHash();

  @$internal
  @override
  ScanStatus create() => ScanStatus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$scanStatusHash() => r'0bf66352aed9e150d53e3010c1a7623c8cf3caa2';

abstract class _$ScanStatus extends $Notifier<String> {
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

@ProviderFor(AIStatus)
final aIStatusProvider = AIStatusProvider._();

final class AIStatusProvider extends $NotifierProvider<AIStatus, String> {
  AIStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aIStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aIStatusHash();

  @$internal
  @override
  AIStatus create() => AIStatus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$aIStatusHash() => r'c5846ef1c01686f185934f447a466e55a9a48cb8';

abstract class _$AIStatus extends $Notifier<String> {
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

@ProviderFor(LibraryController)
final libraryControllerProvider = LibraryControllerProvider._();

final class LibraryControllerProvider
    extends $AsyncNotifierProvider<LibraryController, void> {
  LibraryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryControllerHash();

  @$internal
  @override
  LibraryController create() => LibraryController();
}

String _$libraryControllerHash() => r'e084f7671970f327f08b711b8a068c6ddf4cc99f';

abstract class _$LibraryController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
