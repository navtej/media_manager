import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'status_message_provider.g.dart';

@riverpod
class StatusMessage extends _$StatusMessage {
  Timer? _clearTimer;

  @override
  String? build() {
    ref.onDispose(() => _clearTimer?.cancel());
    return null;
  }

  void set(String message, {Duration duration = const Duration(seconds: 3)}) {
    _clearTimer?.cancel();
    state = message;
    _clearTimer = Timer(duration, () {
      if (state == message) {
        state = null;
      }
    });
  }
}
