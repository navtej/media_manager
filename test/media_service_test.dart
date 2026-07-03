import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/media_service.dart';

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
}
