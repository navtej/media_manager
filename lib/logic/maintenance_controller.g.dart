// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'maintenance_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MaintenanceController)
final maintenanceControllerProvider = MaintenanceControllerProvider._();

final class MaintenanceControllerProvider
    extends $AsyncNotifierProvider<MaintenanceController, void> {
  MaintenanceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'maintenanceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$maintenanceControllerHash();

  @$internal
  @override
  MaintenanceController create() => MaintenanceController();
}

String _$maintenanceControllerHash() =>
    r'651d0f2942cf57d6802a49e304ff5f8e54749bd6';

abstract class _$MaintenanceController extends $AsyncNotifier<void> {
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
