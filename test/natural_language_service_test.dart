import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    'summarizeTranscript posts OpenAI-compatible request and parses assistant JSON',
    () async {
      final transport = _FakeSummaryTransport(
        response: SummaryHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'synopsis': 'A useful synopsis.',
                    'themes': [
                      {
                        'title': 'Main Idea',
                        'bullets': ['First point', 'Second point'],
                      },
                    ],
                    'highlights': ['First point'],
                    'keywords': ['local', 'summary'],
                  }),
                },
              },
            ],
          }),
        ),
      );

      final summary =
          await NaturalLanguageService(
            summaryHttpPost: transport.post,
          ).summarizeTranscript(
            title: 'Consumer AI Has a Problem',
            metadataJson: '{}',
            transcript:
                'Consumer AI products are still reactive. '
                'People need proactive assistants that reduce work. '
                'The video explains permission ladders and product design tradeoffs.',
            apiUrl: 'https://summary.example.test/v1/chat/completions',
            apiKey: 'sk-test',
          );

      expect(summary.synopsis, 'A useful synopsis.');
      expect(summary.themes.single.title, 'Main Idea');
      expect(transport.requests, hasLength(1));
      final request = transport.requests.single;
      expect(
        request.url.toString(),
        'https://summary.example.test/v1/chat/completions',
      );
      expect(request.headers['Content-Type'], 'application/json');
      expect(request.headers['Authorization'], 'Bearer sk-test');
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['messages'], isA<List<dynamic>>());
      expect(jsonEncode(payload), contains('Consumer AI Has a Problem'));
      expect(jsonEncode(payload), contains('Consumer AI products'));
    },
  );

  test(
    'summarizeTranscript omits authorization when API key is empty',
    () async {
      final transport = _FakeSummaryTransport(
        response: SummaryHttpResponse(
          statusCode: 200,
          body: jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'synopsis': 'Synopsis',
                    'highlights': ['Highlight'],
                    'keywords': ['keyword'],
                  }),
                },
              },
            ],
          }),
        ),
      );

      await NaturalLanguageService(
        summaryHttpPost: transport.post,
      ).summarizeTranscript(
        title: 'Local video',
        metadataJson: '{}',
        transcript:
            'The transcript explains how the local library is organized. '
            'It covers captions, metadata, and summary generation.',
        apiUrl: 'http://localhost:11434/v1/chat/completions',
        apiKey: '',
      );

      expect(
        transport.requests.single.headers,
        isNot(contains('Authorization')),
      );
    },
  );

  test('summarizeTranscript requires a configured URL', () async {
    final transport = _FakeSummaryTransport(
      response: const SummaryHttpResponse(statusCode: 200, body: '{}'),
    );

    await expectLater(
      () => NaturalLanguageService(summaryHttpPost: transport.post)
          .summarizeTranscript(
            title: 'Local video',
            metadataJson: '{}',
            transcript: 'Transcript text.',
            apiUrl: ' ',
            apiKey: '',
          ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Summarization API URL is not configured.',
        ),
      ),
    );
    expect(transport.requests, isEmpty);
  });

  test(
    'summarizeTranscript falls back when assistant JSON is malformed',
    () async {
      final transport = _FakeSummaryTransport(
        response: jsonEncode({
          'choices': [
            {
              'message': {'content': 'not json'},
            },
          ],
        }),
      );

      final summary =
          await NaturalLanguageService(
            summaryHttpPost: transport.post,
          ).summarizeTranscript(
            title: 'Local video',
            metadataJson: '{}',
            transcript:
                'The transcript explains how the local library is organized. '
                'It covers captions, metadata, and summary generation.',
            apiUrl: 'https://summary.example.test/v1/chat/completions',
            apiKey: '',
          );

      expect(summary.synopsis, contains('local library'));
      expect(summary.highlights, isNotEmpty);
    },
  );

  test('playVideo delegates opening the path to native playback', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return null;
        });

    await NaturalLanguageService().playVideo(
      '/Volumes/Media/Library/movie.mp4',
    );

    expect(receivedCall?.method, 'playVideo');
    expect(receivedCall?.arguments, {
      'path': '/Volumes/Media/Library/movie.mp4',
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
    );

    expect(opened, isFalse);
  });
}

class _SummaryRequest {
  const _SummaryRequest({
    required this.url,
    required this.headers,
    required this.body,
  });

  final Uri url;
  final Map<String, String> headers;
  final String body;
}

class _FakeSummaryTransport {
  _FakeSummaryTransport({required Object response})
    : _response = response is SummaryHttpResponse
          ? response
          : SummaryHttpResponse(statusCode: 200, body: response.toString());

  final SummaryHttpResponse _response;
  final requests = <_SummaryRequest>[];

  Future<SummaryHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    requests.add(_SummaryRequest(url: url, headers: headers, body: body));
    return _response;
  }
}
