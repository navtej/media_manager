import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/playback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.moviemanager/natural_language');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('plays one video through native playback', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });

    expect(
      await PlaybackService().playVideo('/Volumes/Media/Library/movie.mp4'),
      isTrue,
    );
    expect(receivedCall?.method, 'playVideo');
    expect(receivedCall?.arguments, {
      'path': '/Volumes/Media/Library/movie.mp4',
    });
  });

  test('opens selected videos through native playlist playback', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });

    expect(
      await PlaybackService().playPlaylist([
        '/Volumes/Media/Library/first.mp4',
        '/Volumes/Media/Library/second.mp4',
      ]),
      isTrue,
    );
    expect(receivedCall?.method, 'playPlaylist');
    expect(receivedCall?.arguments, {
      'paths': [
        '/Volumes/Media/Library/first.mp4',
        '/Volumes/Media/Library/second.mp4',
      ],
    });
  });

  test('returns false when native playback fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'PLAYBACK_ERROR');
        });

    expect(
      await PlaybackService().playVideo('/Volumes/Media/Library/movie.mp4'),
      isFalse,
    );
  });
}
