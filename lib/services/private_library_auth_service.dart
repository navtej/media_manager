import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrivateLibraryAuthService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.moviemanager/private_library_auth',
  );

  Future<bool> authenticate() async {
    if (!Platform.isMacOS) {
      return true;
    }

    try {
      return await _channel.invokeMethod<bool>('authenticatePrivateLibrary') ??
          false;
    } on PlatformException catch (e) {
      debugPrint("Private library authentication failed: '${e.message}'.");
      return false;
    }
  }
}

final privateLibraryAuthServiceProvider = Provider(
  (ref) => PrivateLibraryAuthService(),
);
