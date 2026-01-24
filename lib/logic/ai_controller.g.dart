// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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

@ProviderFor(AIController)
final aIControllerProvider = AIControllerProvider._();

final class AIControllerProvider
    extends $AsyncNotifierProvider<AIController, void> {
  AIControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aIControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aIControllerHash();

  @$internal
  @override
  AIController create() => AIController();
}

String _$aIControllerHash() => r'6157410cc70bebbcd1e547fd7ddcae0cb47b674b';

abstract class _$AIController extends $AsyncNotifier<void> {
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
