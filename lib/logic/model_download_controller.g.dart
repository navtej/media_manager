// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_download_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ModelDownloadController)
final modelDownloadControllerProvider = ModelDownloadControllerProvider._();

final class ModelDownloadControllerProvider
    extends $NotifierProvider<ModelDownloadController, ModelDownloadState> {
  ModelDownloadControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'modelDownloadControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$modelDownloadControllerHash();

  @$internal
  @override
  ModelDownloadController create() => ModelDownloadController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ModelDownloadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ModelDownloadState>(value),
    );
  }
}

String _$modelDownloadControllerHash() =>
    r'de8e288555e0d993316cdf93eef9ed4a31ca11d1';

abstract class _$ModelDownloadController extends $Notifier<ModelDownloadState> {
  ModelDownloadState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ModelDownloadState, ModelDownloadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ModelDownloadState, ModelDownloadState>,
              ModelDownloadState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
