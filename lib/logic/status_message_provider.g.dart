// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_message_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StatusMessage)
final statusMessageProvider = StatusMessageProvider._();

final class StatusMessageProvider
    extends $NotifierProvider<StatusMessage, String?> {
  StatusMessageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statusMessageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statusMessageHash();

  @$internal
  @override
  StatusMessage create() => StatusMessage();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$statusMessageHash() => r'e1978a641ba97752dd125b61ded3b297bb9e4711';

abstract class _$StatusMessage extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
