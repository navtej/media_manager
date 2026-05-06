// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Settings)
final settingsProvider = SettingsProvider._();

final class SettingsProvider
    extends $AsyncNotifierProvider<Settings, Map<String, dynamic>> {
  SettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsHash();

  @$internal
  @override
  Settings create() => Settings();
}

String _$settingsHash() => r'269e64f7ba64b9a9b916c4b9fd623ee98e1f68fe';

abstract class _$Settings extends $AsyncNotifier<Map<String, dynamic>> {
  FutureOr<Map<String, dynamic>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<Map<String, dynamic>>, Map<String, dynamic>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<Map<String, dynamic>>,
                Map<String, dynamic>
              >,
              AsyncValue<Map<String, dynamic>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(summaryModelValidation)
final summaryModelValidationProvider = SummaryModelValidationProvider._();

final class SummaryModelValidationProvider
    extends
        $FunctionalProvider<
          AsyncValue<SummaryModelValidationResult>,
          SummaryModelValidationResult,
          FutureOr<SummaryModelValidationResult>
        >
    with
        $FutureModifier<SummaryModelValidationResult>,
        $FutureProvider<SummaryModelValidationResult> {
  SummaryModelValidationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'summaryModelValidationProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$summaryModelValidationHash();

  @$internal
  @override
  $FutureProviderElement<SummaryModelValidationResult> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SummaryModelValidationResult> create(Ref ref) {
    return summaryModelValidation(ref);
  }
}

String _$summaryModelValidationHash() =>
    r'd102e2fa65ff55c70468a05314d6d520535e1026';
