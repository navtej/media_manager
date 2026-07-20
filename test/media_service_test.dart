import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/media_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MediaService candidate validation', () {
    final service = MediaService();

    test('accepts MPEG transport stream files with a video stream', () {
      final metadata = {
        'raw': {
          'streams': [
            {'codec_type': 'audio', 'codec_name': 'aac'},
            {'codec_type': 'video', 'codec_name': 'mpeg2video'},
          ],
        },
      };

      expect(service.hasVideoStream(metadata), isTrue);
      expect(
        service.shouldAcceptCandidateVideo('/media/clip.ts', metadata),
        isTrue,
      );
    });

    test('rejects MPEG transport stream files without a video stream', () {
      final audioOnlyMetadata = {
        'raw': {
          'streams': [
            {'codec_type': 'audio', 'codec_name': 'aac'},
          ],
        },
      };

      expect(service.hasVideoStream(audioOnlyMetadata), isFalse);
      expect(
        service.shouldAcceptCandidateVideo(
          '/media/audio-only.ts',
          audioOnlyMetadata,
        ),
        isFalse,
      );
      expect(
        service.shouldAcceptCandidateVideo('/media/empty.ts', const {}),
        isFalse,
      );
      expect(
        service.shouldAcceptCandidateVideo('/media/malformed.ts', const {
          'raw': {'streams': 'not-a-list'},
        }),
        isFalse,
      );
    });

    test('preserves existing extension behavior for non-ts videos', () {
      expect(
        service.shouldAcceptCandidateVideo('/media/movie.mp4', const {}),
        isTrue,
      );
    });
  });

  test('deletes partial transcription audio when extraction throws', () async {
    final root = await Directory.systemTemp.createTemp(
      'media-service-audio-cleanup-test',
    );
    addTearDown(() => root.delete(recursive: true));
    File? partialAudio;
    final service = MediaService(
      temporaryDirectory: () async => root,
      transcriptionAudioExtractor:
          ({required inputPath, required outputPath}) async {
            partialAudio = File(outputPath);
            await partialAudio!.writeAsBytes(const [1, 2, 3]);
            throw StateError('FFmpeg failed after creating output.');
          },
    );

    await expectLater(
      service.extractTranscriptionAudio(p.join(root.path, 'video.mp4')),
      throwsA(isA<StateError>()),
    );

    expect(partialAudio, isNotNull);
    expect(await partialAudio!.exists(), isFalse);
  });
}
