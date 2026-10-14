import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/video_version_models.dart';
import 'package:movie_manager/services/video_transcoder.dart';

Map<String, dynamic> _metadata({
  List<Map<String, dynamic>>? streams,
  String? bitrate,
}) {
  return {
    'duration': 60.0,
    'bitrate': ?bitrate,
    'raw': {
      'streams':
          streams ??
          [
            {
              'index': 0,
              'codec_type': 'video',
              'codec_name': 'h264',
              'width': 1920,
              'height': 1080,
            },
            {
              'index': 1,
              'codec_type': 'audio',
              'codec_name': 'aac',
              'channels': 2,
            },
          ],
    },
  };
}

List<String> _build(
  Map<String, dynamic> metadata, {
  VideoResolutionPreset preset = VideoResolutionPreset.hd720,
  VideoConversionEncoder encoder = VideoConversionEncoder.videoToolbox,
}) {
  return buildVideoConversionArguments(
    inputPath: '/Volumes/Media/In Movie.mkv',
    outputPath: '/Volumes/Media/In Movie [720p].mp4.part',
    sourceMetadata: metadata,
    preset: preset,
    encoder: encoder,
  );
}

/// Values following each occurrence of [flag].
List<String> _valuesOf(List<String> args, String flag) => [
  for (var i = 0; i < args.length - 1; i++)
    if (args[i] == flag) args[i + 1],
];

void main() {
  test('passes paths as single arguments and forces the MP4 muxer', () {
    final args = _build(_metadata());

    expect(args.first, '-hide_banner');
    expect(_valuesOf(args, '-i'), ['/Volumes/Media/In Movie.mkv']);
    expect(args.last, '/Volumes/Media/In Movie [720p].mp4.part');
    expect(_valuesOf(args, '-f'), ['mp4']);
    expect(args, contains('-y'));
    expect(_valuesOf(args, '-map_metadata'), ['0']);
    expect(_valuesOf(args, '-map_chapters'), ['0']);
  });

  test(
    'scales into the preset box for either orientation without upscaling',
    () {
      final filter = _valuesOf(_build(_metadata()), '-vf').single;

      expect(
        filter,
        "scale=w='min(iw,if(gte(iw,ih),1280,720))'"
        ":h='min(ih,if(gte(iw,ih),720,1280))'"
        ':force_original_aspect_ratio=decrease:force_divisible_by=2'
        ',format=yuv420p',
      );
    },
  );

  test('maps the main video stream, never cover art', () {
    final args = _build(
      _metadata(
        streams: [
          {
            'index': 0,
            'codec_type': 'video',
            'codec_name': 'mjpeg',
            'width': 500,
            'height': 500,
            'disposition': {'attached_pic': 1},
          },
          {
            'index': 1,
            'codec_type': 'video',
            'codec_name': 'hevc',
            'width': 3840,
            'height': 2160,
          },
          {'index': 2, 'codec_type': 'audio', 'codec_name': 'aac'},
        ],
      ),
    );

    expect(_valuesOf(args, '-map'), ['0:1', '0:2']);
  });

  test('copies MP4-compatible audio and re-encodes the rest to AAC', () {
    final args = _build(
      _metadata(
        streams: [
          {
            'index': 0,
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 1920,
            'height': 1080,
          },
          {
            'index': 1,
            'codec_type': 'audio',
            'codec_name': 'ac3',
            'channels': 6,
          },
          {
            'index': 2,
            'codec_type': 'audio',
            'codec_name': 'opus',
            'channels': 2,
          },
          {
            'index': 3,
            'codec_type': 'audio',
            'codec_name': 'truehd',
            'channels': 8,
          },
        ],
      ),
    );

    expect(_valuesOf(args, '-map'), ['0:0', '0:1', '0:2', '0:3']);
    expect(_valuesOf(args, '-c:a:0'), ['copy']);
    expect(_valuesOf(args, '-c:a:1'), ['aac']);
    expect(_valuesOf(args, '-b:a:1'), ['160k']);
    expect(_valuesOf(args, '-c:a:2'), ['aac']);
    expect(_valuesOf(args, '-b:a:2'), ['384k']);
    expect(_valuesOf(args, '-ac:a:2'), ['6']);
    expect(_valuesOf(args, '-ac:a:1'), isEmpty);
  });

  test('keeps text subtitles as mov_text and drops bitmap subtitles', () {
    final args = _build(
      _metadata(
        streams: [
          {
            'index': 0,
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 1920,
            'height': 800,
          },
          {'index': 1, 'codec_type': 'subtitle', 'codec_name': 'subrip'},
          {
            'index': 2,
            'codec_type': 'subtitle',
            'codec_name': 'hdmv_pgs_subtitle',
          },
          {'index': 3, 'codec_type': 'subtitle', 'codec_name': 'ass'},
        ],
      ),
    );

    expect(_valuesOf(args, '-map'), ['0:0', '0:1', '0:3']);
    expect(_valuesOf(args, '-c:s'), ['mov_text']);
    expect(args.where((arg) => arg.startsWith('-c:a')), isEmpty);
  });

  test('omits subtitle and audio codecs when there are none', () {
    final args = _build(
      _metadata(
        streams: [
          {
            'index': 0,
            'codec_type': 'video',
            'codec_name': 'h264',
            'width': 1920,
            'height': 1080,
          },
        ],
      ),
    );

    expect(_valuesOf(args, '-map'), ['0:0']);
    expect(_valuesOf(args, '-c:s'), isEmpty);
  });

  test('uses VideoToolbox with a bitrate, or x264 with CRF and a cap', () {
    final hardware = _build(_metadata());
    expect(_valuesOf(hardware, '-c:v'), ['h264_videotoolbox']);
    expect(_valuesOf(hardware, '-b:v'), ['2500k']);
    expect(_valuesOf(hardware, '-allow_sw'), ['1']);

    final software = _build(_metadata(), encoder: VideoConversionEncoder.x264);
    expect(_valuesOf(software, '-c:v'), ['libx264']);
    expect(_valuesOf(software, '-crf'), ['23']);
    expect(_valuesOf(software, '-maxrate'), ['3750k']);
    expect(_valuesOf(software, '-bufsize'), ['7500k']);
    expect(_valuesOf(software, '-b:v'), isEmpty);
  });

  test('rejects a file without a usable video stream', () {
    expect(
      () => _build(
        _metadata(
          streams: [
            {'index': 0, 'codec_type': 'audio', 'codec_name': 'aac'},
          ],
        ),
      ),
      throwsA(isA<VideoVersionException>()),
    );
  });

  group('targetVideoBitrateKbps', () {
    test('uses the preset when the source bitrate is unknown', () {
      expect(
        targetVideoBitrateKbps(
          sourceMetadata: _metadata(),
          preset: VideoResolutionPreset.fhd1080,
        ),
        5000,
      );
    });

    test('caps at 75% of the source video bitrate with a floor', () {
      final streamBitrate = _metadata(
        streams: [
          {
            'index': 0,
            'codec_type': 'video',
            'width': 1920,
            'height': 1080,
            'bit_rate': '2000000',
          },
        ],
      );
      expect(
        targetVideoBitrateKbps(
          sourceMetadata: streamBitrate,
          preset: VideoResolutionPreset.hd720,
        ),
        1500,
      );
      // Container bitrate only: 90% is treated as video.
      expect(
        targetVideoBitrateKbps(
          sourceMetadata: _metadata(bitrate: '1000000'),
          preset: VideoResolutionPreset.hd720,
        ),
        675,
      );
      expect(
        targetVideoBitrateKbps(
          sourceMetadata: _metadata(bitrate: '200000'),
          preset: VideoResolutionPreset.sd360,
        ),
        300,
      );
      expect(
        targetVideoBitrateKbps(
          sourceMetadata: _metadata(bitrate: '40000000'),
          preset: VideoResolutionPreset.hd720,
        ),
        2500,
      );
    });
  });

  test('summarizes FFmpeg failures from the last log lines', () {
    expect(
      summarizeFfmpegFailure(null, returnCode: 1),
      'FFmpeg failed (exit code 1).',
    );
    expect(
      summarizeFfmpegFailure(
        'Input #0, matroska\n'
        'frame=  100 fps= 50 q=-1.0 size=     256KiB time=00:00:04 speed=2x\r'
        'Error while opening encoder\n'
        'Conversion failed!\n',
      ),
      'Input #0, matroska Error while opening encoder Conversion failed!',
    );
  });
}
