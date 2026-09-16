import 'package:flutter/services.dart';

typedef AppTerminationHandler = Future<void> Function();

class AppLifecycleService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.moviemanager/app_lifecycle',
  );

  static AppTerminationHandler? _terminationHandler;

  /// Installs the Dart-side part of the native termination handshake.
  ///
  /// macOS may request termination without going through Flutter's menu, so
  /// this handler is registered by the root widget and is invoked by the
  /// native app delegate before it allows the process to exit.
  static void registerTerminationHandler(AppTerminationHandler handler) {
    _terminationHandler = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'prepareForTermination') {
        throw MissingPluginException(
          'Unsupported app lifecycle method: ${call.method}',
        );
      }

      await prepareForTermination();
    });
  }

  static void unregisterTerminationHandler() {
    _terminationHandler = null;
    _channel.setMethodCallHandler(null);
  }

  /// Runs the currently registered shutdown work.
  static Future<void> prepareForTermination() async {
    final handler = _terminationHandler;
    if (handler == null) {
      throw StateError('App termination handler is not registered.');
    }
    await handler();
  }

  static Future<void> quit() {
    return _channel.invokeMethod<void>('terminateApplication');
  }
}
