import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'status_message_provider.g.dart';

@riverpod
class StatusMessage extends _$StatusMessage {
  @override
  String? build() => null;

  void set(String message, {Duration duration = const Duration(seconds: 3)}) {
    state = message;
    Future.delayed(duration, () {
      if (state == message) {
        state = null;
      }
    });
  }
}
