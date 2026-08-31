import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlaybackService {
  PlaybackService({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _defaultChannel = MethodChannel(
    'com.example.moviemanager/natural_language',
  );

  final MethodChannel _channel;

  Future<bool> playVideo(String path) => _play('playVideo', {'path': path});

  Future<bool> playPlaylist(List<String> paths) =>
      _play('playPlaylist', {'paths': paths});

  Future<bool> _play(String method, Map<String, Object> arguments) async {
    try {
      await _channel.invokeMethod(method, arguments);
      return true;
    } on PlatformException {
      return false;
    }
  }
}

final playbackServiceProvider = Provider((ref) => PlaybackService());
