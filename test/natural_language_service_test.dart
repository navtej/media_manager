import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/video_summary_models.dart';
import 'package:movie_manager/services/natural_language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.example.moviemanager/natural_language');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'transcribeAudio surfaces native transcription failure message',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'TRANSCRIPTION_ERROR',
              message: 'whisper failed to load model',
            );
          });

      expect(
        () => NaturalLanguageService().transcribeAudio(
          audioPath: '/tmp/audio.wav',
          modelPath: '/tmp/model.bin',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Transcription failed: whisper failed to load model',
          ),
        ),
      );
    },
  );

  test(
    'summarizeTranscript falls back when native summary is blocked as unsafe',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'SUMMARY_ERROR',
              message: 'Detected content likely to be unsafe',
            );
          });

      final summary = await NaturalLanguageService().summarizeTranscript(
        title: 'Consumer AI Has a Problem',
        metadataJson: '{}',
        transcript:
            'Consumer AI products are still reactive. '
            'People need proactive assistants that reduce work. '
            'The video explains permission ladders and product design tradeoffs.',
      );

      expect(summary, isA<StructuredVideoSummary>());
      expect(summary.synopsis, contains('Consumer AI products'));
      expect(summary.highlights, isNotEmpty);
      expect(summary.themes, isNotEmpty);
      expect(summary.themes.first.title, 'Key Themes');
      expect(summary.themes.first.bullets, hasLength(3));
      expect(summary.keywords, contains('Consumer'));
    },
  );

  test(
    'summarizeTranscript falls back when native summary payload is malformed',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'SUMMARY_ERROR',
              message:
                  "The data couldn't be read because it isn't in the correct format.",
            );
          });

      final summary = await NaturalLanguageService().summarizeTranscript(
        title: 'Local video',
        metadataJson: '{}',
        transcript:
            'The transcript explains how the local library is organized. '
            'It covers captions, metadata, and summary generation.',
      );

      expect(summary.synopsis, contains('local library'));
      expect(summary.highlights, isNotEmpty);
    },
  );

  test('playVideo passes folder bookmark context to native playback', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });

    await NaturalLanguageService().playVideo(
      '/Volumes/Media/Library/movie.mp4',
      folderPath: '/Volumes/Media/Library',
      folderBookmark: 'bookmark-data',
    );

    expect(receivedCall?.method, 'playVideo');
    expect(receivedCall?.arguments, {
      'path': '/Volumes/Media/Library/movie.mp4',
      'folderPath': '/Volumes/Media/Library',
      'folderBookmark': 'bookmark-data',
    });
  });

  test('playVideo reports false when native playback fails', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'BOOKMARK_ERROR',
            message: 'Folder access needs repair.',
          );
        });

    final opened = await NaturalLanguageService().playVideo(
      '/Volumes/Media/Library/movie.mp4',
      folderPath: '/Volumes/Media/Library',
      folderBookmark: 'stale-bookmark',
    );

    expect(opened, isFalse);
  });
}
