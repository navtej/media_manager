// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'whisper_model_catalog_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WhisperModelCatalogController)
final whisperModelCatalogControllerProvider =
    WhisperModelCatalogControllerProvider._();

final class WhisperModelCatalogControllerProvider
    extends
        $NotifierProvider<
          WhisperModelCatalogController,
          WhisperModelCatalogState
        > {
  WhisperModelCatalogControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'whisperModelCatalogControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$whisperModelCatalogControllerHash();

  @$internal
  @override
  WhisperModelCatalogController create() => WhisperModelCatalogController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WhisperModelCatalogState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WhisperModelCatalogState>(value),
    );
  }
}

String _$whisperModelCatalogControllerHash() =>
    r'77e146a63e2d89c56f5252b8dbd6f03e973db906';

abstract class _$WhisperModelCatalogController
    extends $Notifier<WhisperModelCatalogState> {
  WhisperModelCatalogState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<WhisperModelCatalogState, WhisperModelCatalogState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WhisperModelCatalogState, WhisperModelCatalogState>,
              WhisperModelCatalogState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
