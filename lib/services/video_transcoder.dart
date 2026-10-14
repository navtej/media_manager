import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/video_version_models.dart';

/// H.264 encoders in the order a conversion tries them. VideoToolbox is the
/// fast hardware path; libx264 is the software fallback.
enum VideoConversionEncoder {
  videoToolbox('Hardware (VideoToolbox)'),
  x264('Software (x264)');

  const VideoConversionEncoder(this.label);

  final String label;
}

/// Audio codecs MP4 can carry unchanged.
const _copyableAudioCodecs = {'aac', 'mp3', 'ac3', 'eac3', 'alac'};

/// Text subtitle codecs that convert to MP4 `mov_text`. Bitmap subtitles
/// (PGS, DVD) cannot, and are left out.
const _textSubtitleCodecs = {
  'subrip',
  'srt',
  'ass',
  'ssa',
  'mov_text',
  'webvtt',
  'text',
};

/// FFmpeg arguments that convert [inputPath] to an MP4 at [outputPath] no
/// larger than [preset]'s 16:9 box (flipped for portrait video).
///
/// Maps the main video stream (never cover art), every audio stream and the
/// text subtitles, keeps metadata and chapters, copies MP4-compatible audio
/// and re-encodes the rest to AAC.
List<String> buildVideoConversionArguments({
  required String inputPath,
  required String outputPath,
  required Map<String, dynamic> sourceMetadata,
  required VideoResolutionPreset preset,
  required VideoConversionEncoder encoder,
}) {
  final videoStream = primaryVideoStream(sourceMetadata);
  final videoIndex = _asInt(videoStream?['index']);
  if (videoStream == null || videoIndex == null) {
    throw const VideoVersionException('The file has no video stream.');
  }

  final streams = videoMetadataStreams(sourceMetadata);
  final audioStreams = [
    for (final stream in streams)
      if (stream['codec_type'] == 'audio' && _asInt(stream['index']) != null)
        stream,
  ];
  final subtitleStreams = [
    for (final stream in streams)
      if (stream['codec_type'] == 'subtitle' &&
          _asInt(stream['index']) != null &&
          _textSubtitleCodecs.contains(stream['codec_name']))
        stream,
  ];

  final long = preset.longSide;
  final short = preset.shortSide;
  // Quoted so the commas inside the expressions survive filtergraph parsing.
  // `iw`/`ih` are the displayed (auto-rotated) dimensions, and `min` keeps a
  // smaller source from being upscaled.
  final scale =
      "scale=w='min(iw,if(gte(iw,ih),$long,$short))'"
      ":h='min(ih,if(gte(iw,ih),$short,$long))'"
      ':force_original_aspect_ratio=decrease:force_divisible_by=2';
  final bitrateKbps = targetVideoBitrateKbps(
    sourceMetadata: sourceMetadata,
    preset: preset,
  );

  return [
    '-hide_banner',
    '-y',
    '-i',
    inputPath,
    '-map',
    '0:$videoIndex',
    for (final stream in audioStreams) ...['-map', '0:${stream['index']}'],
    for (final stream in subtitleStreams) ...['-map', '0:${stream['index']}'],
    '-map_metadata',
    '0',
    '-map_chapters',
    '0',
    '-vf',
    '$scale,format=yuv420p',
    ...switch (encoder) {
      VideoConversionEncoder.videoToolbox => [
        '-c:v',
        'h264_videotoolbox',
        '-b:v',
        '${bitrateKbps}k',
        '-profile:v',
        'high',
        '-allow_sw',
        '1',
      ],
      VideoConversionEncoder.x264 => [
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '23',
        '-maxrate',
        '${(bitrateKbps * 1.5).round()}k',
        '-bufsize',
        '${bitrateKbps * 3}k',
      ],
    },
    for (var i = 0; i < audioStreams.length; i++)
      ..._audioArguments(i, audioStreams[i]),
    if (subtitleStreams.isNotEmpty) ...['-c:s', 'mov_text'],
    '-max_muxing_queue_size',
    '1024',
    '-f',
    'mp4',
    outputPath,
  ];
}

List<String> _audioArguments(int outputIndex, Map<String, dynamic> stream) {
  if (_copyableAudioCodecs.contains(stream['codec_name'])) {
    return ['-c:a:$outputIndex', 'copy'];
  }
  final channels = _asInt(stream['channels']) ?? 2;
  return [
    '-c:a:$outputIndex',
    'aac',
    '-b:a:$outputIndex',
    channels <= 2 ? '160k' : '384k',
    // The AAC encoder's surround support ends at 5.1.
    if (channels > 6) ...['-ac:a:$outputIndex', '6'],
  ];
}

/// The preset's bitrate, capped at 75% of the source video bitrate so a
/// heavily compressed source does not grow.
int targetVideoBitrateKbps({
  required Map<String, dynamic> sourceMetadata,
  required VideoResolutionPreset preset,
}) {
  final sourceBitsPerSecond = _sourceVideoBitsPerSecond(sourceMetadata);
  if (sourceBitsPerSecond == null) return preset.videoBitrateKbps;
  final capped = (sourceBitsPerSecond * 0.75 / 1000).round();
  if (capped < 300) return 300;
  return capped < preset.videoBitrateKbps ? capped : preset.videoBitrateKbps;
}

int? _sourceVideoBitsPerSecond(Map<String, dynamic> metadata) {
  final streamBitrate = _asInt(primaryVideoStream(metadata)?['bit_rate']);
  if (streamBitrate != null && streamBitrate > 0) return streamBitrate;
  // Matroska rarely reports per-stream bitrates; leave room for audio.
  final totalBitrate = _asInt(metadata['bitrate']);
  if (totalBitrate != null && totalBitrate > 0) {
    return (totalBitrate * 0.9).round();
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

enum VideoTranscodeStatus { succeeded, failed, cancelled }

class VideoTranscodeResult {
  const VideoTranscodeResult(this.status, {this.errorMessage});

  final VideoTranscodeStatus status;
  final String? errorMessage;
}

/// A running transcode.
abstract interface class VideoTranscodeTask {
  Future<VideoTranscodeResult> get result;

  /// Stops the transcode; [result] then completes as cancelled.
  Future<void> cancel();
}

abstract interface class VideoTranscoder {
  /// Starts FFmpeg with [arguments] in the background. [onProgress] receives
  /// how much of the input has been processed.
  VideoTranscodeTask start(
    List<String> arguments, {
    void Function(Duration processed)? onProgress,
  });
}

class FFmpegKitVideoTranscoder implements VideoTranscoder {
  const FFmpegKitVideoTranscoder();

  @override
  VideoTranscodeTask start(
    List<String> arguments, {
    void Function(Duration processed)? onProgress,
  }) {
    final task = _FFmpegKitTranscodeTask();
    unawaited(task._start(arguments, onProgress));
    return task;
  }
}

/// FFmpegKit keeps only the most recent sessions (10 by default) and finds a
/// session's completion callback, return code and logs through that history.
/// Library scans start many short probe and thumbnail sessions, which can
/// evict a long conversion before it ends. A larger history keeps the return
/// code available in practice; completion itself never depends on it.
const _ffmpegSessionHistorySize = 200;

class _FFmpegKitTranscodeTask implements VideoTranscodeTask {
  static Future<void>? _historySizeConfigured;

  final _completer = Completer<VideoTranscodeResult>();
  int? _sessionId;
  bool _cancelRequested = false;

  @override
  Future<VideoTranscodeResult> get result => _completer.future;

  Future<void> _start(
    List<String> arguments,
    void Function(Duration processed)? onProgress,
  ) async {
    try {
      await (_historySizeConfigured ??=
          FFmpegKitConfig.setSessionHistorySize(
            _ffmpegSessionHistorySize,
          ).catchError((Object error) {
            debugPrint('Could not raise FFmpegKit session history: $error');
          }));
      final session = await FFmpegSession.create(
        arguments,
        null,
        null,
        onProgress == null
            ? null
            : (statistics) =>
                  onProgress(Duration(milliseconds: statistics.getTime())),
      );
      _sessionId = session.getSessionId();
      if (_cancelRequested) {
        _complete(const VideoTranscodeResult(VideoTranscodeStatus.cancelled));
        return;
      }
      // Completes when FFmpeg exits, independent of the session history.
      await FFmpegKitConfig.ffmpegExecute(session);
      await _finish(session);
    } catch (error) {
      _complete(
        _cancelRequested
            ? const VideoTranscodeResult(VideoTranscodeStatus.cancelled)
            : VideoTranscodeResult(
                VideoTranscodeStatus.failed,
                errorMessage: 'FFmpeg could not run: $error',
              ),
      );
    }
  }

  Future<void> _finish(FFmpegSession session) async {
    if (_cancelRequested) {
      _complete(const VideoTranscodeResult(VideoTranscodeStatus.cancelled));
      return;
    }
    final ReturnCode? returnCode;
    try {
      returnCode = await session.getReturnCode();
    } catch (error) {
      // The session already left FFmpegKit's history. FFmpeg has exited, so
      // report success and let finalization verify the output (video stream,
      // resolution and duration) before anything is saved.
      debugPrint('FFmpeg return code unavailable ($error); verifying output.');
      _complete(const VideoTranscodeResult(VideoTranscodeStatus.succeeded));
      return;
    }
    if (ReturnCode.isSuccess(returnCode)) {
      _complete(const VideoTranscodeResult(VideoTranscodeStatus.succeeded));
      return;
    }
    if (ReturnCode.isCancel(returnCode)) {
      _complete(const VideoTranscodeResult(VideoTranscodeStatus.cancelled));
      return;
    }
    String? logs;
    try {
      logs = await session.getAllLogsAsString();
    } catch (_) {
      logs = null;
    }
    _complete(
      VideoTranscodeResult(
        VideoTranscodeStatus.failed,
        errorMessage: summarizeFfmpegFailure(
          logs,
          returnCode: returnCode?.getValue(),
        ),
      ),
    );
  }

  void _complete(VideoTranscodeResult result) {
    if (!_completer.isCompleted) {
      _completer.complete(result);
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    final sessionId = _sessionId;
    if (sessionId == null) return;
    try {
      await FFmpegKit.cancel(sessionId);
    } catch (error) {
      debugPrint('Could not cancel FFmpeg session $sessionId: $error');
    }
  }
}

/// The last meaningful lines of an FFmpeg log, without progress lines.
String summarizeFfmpegFailure(String? logs, {int? returnCode}) {
  final lines = (logs ?? '')
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where(
        (line) =>
            line.isNotEmpty &&
            !line.startsWith('frame=') &&
            !line.startsWith('size=') &&
            !line.contains('speed='),
      )
      .toList(growable: false);
  if (lines.isEmpty) {
    return returnCode == null
        ? 'FFmpeg failed.'
        : 'FFmpeg failed (exit code $returnCode).';
  }
  final summary = lines.skip(lines.length > 3 ? lines.length - 3 : 0).join(' ');
  return summary.length > 400 ? '${summary.substring(0, 400)}…' : summary;
}

final videoTranscoderProvider = Provider<VideoTranscoder>(
  (ref) => const FFmpegKitVideoTranscoder(),
);
