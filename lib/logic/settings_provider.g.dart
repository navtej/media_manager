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
    extends $AsyncNotifierProvider<Settings, AppSettings> {
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

String _$settingsHash() => r'02048990f0a7ac6857085d23d3657390c189f348';

abstract class _$Settings extends $AsyncNotifier<AppSettings> {
  FutureOr<AppSettings> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AppSettings>, AppSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AppSettings>, AppSettings>,
              AsyncValue<AppSettings>,
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
    r'10611118dcd95925265f8e5135d7e335b806a2ce';
