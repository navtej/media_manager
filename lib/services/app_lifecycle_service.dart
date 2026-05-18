import 'package:flutter/services.dart';

class AppLifecycleService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.moviemanager/app_lifecycle',
  );

  static Future<void> quit() {
    return _channel.invokeMethod<void>('terminateApplication');
  }
}
