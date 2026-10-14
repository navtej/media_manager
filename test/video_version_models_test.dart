import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/video_version_models.dart';

void main() {
  group('VideoDimensions.qualityClass', () {
    test('uses the 16:9 frame that contains the video', () {
      expect(const VideoDimensions(1920, 1080).qualityLabel, '1080p');
      expect(const VideoDimensions(1920, 800).qualityLabel, '1080p');
      expect(const VideoDimensions(1440, 1080).qualityLabel, '1080p');
      expect(const VideoDimensions(1280, 534).qualityLabel, '720p');
      expect(const VideoDimensions(960, 720).qualityLabel, '720p');
      expect(const VideoDimensions(854, 480).qualityLabel, '480p');
      expect(const VideoDimensions(720, 480).qualityLabel, '480p');
      expect(const VideoDimensions(3840, 1600).qualityLabel, '2160p');
    });

    test('is orientation independent', () {
      expect(const VideoDimensions(1080, 1920).qualityClass, 1080);
      expect(const VideoDimensions(720, 1280).qualityClass, 720);
    });

    test('snaps near-standard sizes and keeps unusual ones', () {
      expect(const VideoDimensions(1916, 1076).qualityClass, 1080);
      expect(const VideoDimensions(320, 180).qualityClass, 180);
    });
  });

  group('VideoResolutionPreset.below', () {
    test('offers only strictly lower resolution classes', () {
      expect(VideoResolutionPreset.below(const VideoDimensions(1920, 1080)), [
        VideoResolutionPreset.hd720,
        VideoResolutionPreset.sd480,
        VideoResolutionPreset.sd360,
      ]);
      expect(VideoResolutionPreset.below(const VideoDimensions(1920, 800)), [
        VideoResolutionPreset.hd720,
        VideoResolutionPreset.sd480,
        VideoResolutionPreset.sd360,
      ]);
      expect(
        VideoResolutionPreset.below(const VideoDimensions(640, 360)),
        isEmpty,
      );
    });

    test('offers every preset when the source size is unknown', () {
      expect(VideoResolutionPreset.below(null), VideoResolutionPreset.values);
    });

    test('round-trips preset names', () {
      for (final preset in VideoResolutionPreset.values) {
        expect(VideoResolutionPreset.fromName(preset.name), preset);
      }
      expect(VideoResolutionPreset.fromName('nope'), isNull);
      expect(VideoResolutionPreset.fromName(null), isNull);
    });
  });

  group('metadata helpers', () {
    final metadata = <String, dynamic>{
      'duration': 125.4,
      'bitrate': '4000000',
      'raw': {
        'streams': [
          {
            'index': 0,
            'codec_type': 'video',
            'codec_name': 'mjpeg',
            'width': 600,
            'height': 600,
            'disposition': {'attached_pic': 1},
          },
          {
            'index': 1,
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 1920,
            'height': 1080,
            'disposition': {'attached_pic': 0},
          },
          {'index': 2, 'codec_type': 'audio', 'codec_name': 'aac'},
        ],
      },
    };

    test('skips cover art when finding the main video stream', () {
      expect(primaryVideoStream(metadata)?['index'], 1);
      expect(
        videoDimensionsFromMetadata(metadata),
        const VideoDimensions(1920, 1080),
      );
      expect(videoCodecFromMetadata(metadata), 'h264');
    });

    test('reads stored metadata JSON and duration', () {
      expect(
        videoDimensionsFromMetadataJson(jsonEncode(metadata)),
        const VideoDimensions(1920, 1080),
      );
      expect(videoDurationFromMetadata(metadata), 125.4);
      expect(videoDurationFromMetadata({'duration': '12.5'}), 12.5);
      expect(videoDurationFromMetadata({'duration': 0}), isNull);
    });

    test('tolerates missing or malformed metadata', () {
      expect(videoDimensionsFromMetadataJson('{}'), isNull);
      expect(videoDimensionsFromMetadataJson('not json'), isNull);
      expect(videoDimensionsFromMetadataJson('[]'), isNull);
      expect(
        videoDimensionsFromMetadata({
          'raw': {
            'streams': [
              {'codec_type': 'video', 'width': 0, 'height': 0},
            ],
          },
        }),
        isNull,
      );
    });
  });

  test('deletion result summarizes successes and failures', () {
    expect(
      const VideoVersionDeletionResult(deletedPaths: ['/a.mp4']).userMessage,
      'Deleted 1 version.',
    );
    expect(
      const VideoVersionDeletionResult(
        deletedPaths: ['/a.mp4', '/b.mp4'],
        failures: {'/c.mp4': 'Locked.'},
      ).userMessage,
      'Deleted 2 versions; 1 not deleted. Locked.',
    );
    expect(
      const VideoVersionDeletionResult(
        deletedPaths: [],
        failures: {'/c.mp4': 'Locked.'},
      ).userMessage,
      'No versions were deleted. Locked.',
    );
  });
}
