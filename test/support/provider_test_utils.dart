import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<T> readAsyncValue<T>(
  ProviderContainer container,
  dynamic provider,
) async {
  final subscription = container.listen<AsyncValue<T>>(provider, (_, _) {});
  try {
    for (var attempt = 0; attempt < 50; attempt++) {
      final asyncValue = container.read<AsyncValue<T>>(provider);
      final value = asyncValue.when<T?>(
        data: (value) => value,
        loading: () => null,
        error: (error, stackTrace) => throw error,
      );
      if (value != null) {
        return value;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('Timed out waiting for provider data.');
  } finally {
    subscription.close();
  }
}
