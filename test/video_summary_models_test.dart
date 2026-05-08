import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/video_summary_models.dart';

void main() {
  group('StructuredVideoSummary', () {
    test('parses and normalizes valid structured summary payloads', () {
      final summary = StructuredVideoSummary.fromJson({
        'synopsis': '  A short synopsis.  ',
        'highlights': [' First point ', 'Second point'],
        'keywords': [' drama ', 'festival '],
      });

      expect(summary.synopsis, 'A short synopsis.');
      expect(summary.highlights, ['First point', 'Second point']);
      expect(summary.keywords, ['drama', 'festival']);
    });

    test('parses and normalizes themed summary sections', () {
      final summary = StructuredVideoSummary.fromJson({
        'synopsis': 'A short synopsis.',
        'themes': [
          {
            'title': ' Setup ',
            'bullets': [' First detail ', 'Second detail', '  '],
          },
          {
            'title': 'Resolution',
            'bullets': ['Final detail'],
          },
        ],
        'highlights': ['Legacy highlight'],
        'keywords': ['drama'],
      });

      expect(summary.themes, [
        const VideoSummaryTheme(
          title: 'Setup',
          bullets: ['First detail', 'Second detail'],
        ),
        const VideoSummaryTheme(title: 'Resolution', bullets: ['Final detail']),
      ]);
      expect(summary.toJson()['themes'], [
        {
          'title': 'Setup',
          'bullets': ['First detail', 'Second detail'],
        },
        {
          'title': 'Resolution',
          'bullets': ['Final detail'],
        },
      ]);
    });

    test('rejects payloads with missing required sections', () {
      expect(
        () => StructuredVideoSummary.fromJson({
          'synopsis': 'Present',
          'highlights': <String>[],
          'keywords': ['tag'],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects theme sections with missing title or bullets', () {
      expect(
        () => StructuredVideoSummary.fromJson({
          'synopsis': 'Present',
          'themes': [
            {'title': 'Theme', 'bullets': <String>[]},
          ],
          'keywords': ['tag'],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('VideoSummaryFreshnessKey', () {
    test(
      'matches only when file metadata and transcript model are unchanged',
      () {
        final generatedAt = DateTime.utc(2026, 5, 5, 10, 30);
        final key = VideoSummaryFreshnessKey(
          sourceVideoSize: 4096,
          sourceVideoModifiedAt: generatedAt,
          transcriptModel: 'ggml-base.en.bin',
        );

        expect(
          key.matches(
            fileSize: 4096,
            fileModifiedAt: generatedAt,
            transcriptModel: 'ggml-base.en.bin',
          ),
          isTrue,
        );

        expect(
          key.matches(
            fileSize: 4097,
            fileModifiedAt: generatedAt,
            transcriptModel: 'ggml-base.en.bin',
          ),
          isFalse,
        );
      },
    );
  });
}
