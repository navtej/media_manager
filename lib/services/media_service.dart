import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

typedef TranscriptionAudioExtractor =
    Future<bool> Function({
      required String inputPath,
      required String outputPath,
    });

class MediaService {
  MediaService({
    Future<Directory> Function()? temporaryDirectory,
    TranscriptionAudioExtractor? transcriptionAudioExtractor,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _transcriptionAudioExtractor =
           transcriptionAudioExtractor ?? _extractTranscriptionAudio;

  final Future<Directory> Function() _temporaryDirectory;
  final TranscriptionAudioExtractor _transcriptionAudioExtractor;

  bool hasVideoStream(Map<String, dynamic> metadata) {
    final raw = metadata['raw'];
    if (raw is! Map) return false;

    final streams = raw['streams'];
    if (streams is! List) return false;

    return streams.any((stream) {
      if (stream is! Map) return false;
      return stream['codec_type'] == 'video';
    });
  }

  bool shouldAcceptCandidateVideo(String path, Map<String, dynamic> metadata) {
    final extension = p.extension(path).toLowerCase();
    if (extension != '.ts') return true;

    return hasVideoStream(metadata);
  }

  Future<Map<String, dynamic>> getMetadata(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();

    if (info == null) return {};

    final props = info.getAllProperties();
    // Return specific props or raw json
    // Flattening some useful bits
    final durationStr = info.getDuration() ?? "0";
    final duration = double.tryParse(durationStr) ?? 0.0;

    return {'duration': duration, 'bitrate': info.getBitrate(), 'raw': props};
  }

  Future<Uint8List?> generateThumbnail(
    String path,
    double durationSeconds,
  ) async {
    final tempDir = await _temporaryDirectory();
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    final tempPath = p.join(
      tempDir.path,
      'thumb_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );

    // 10% mark
    final timestamp = durationSeconds * 0.10;
    final file = File(tempPath);

    try {
      // Pass arguments directly so spaces, Unicode, and quote characters in a
      // library path cannot be misinterpreted by FFmpegKit's command parser.
      // Overwrite is explicit because a previous interrupted attempt may have
      // left the same temporary file behind.
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-ss',
        timestamp.toString(),
        '-i',
        path,
        '-frames:v',
        '1',
        '-vf',
        'scale=480:-1',
        '-q:v',
        '2',
        tempPath,
      ]);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode) &&
          await file.exists() &&
          await file.length() > 0) {
        return await file.readAsBytes();
      }

      print(
        'Failed to generate thumbnail for $path '
        '(return code: ${returnCode?.getValue()}): '
        '${await session.getOutput()}',
      );
      return null;
    } finally {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException catch (error) {
        debugPrint('Failed to delete temporary thumbnail: $error');
      }
    }
  }

  Future<String?> extractTranscriptionAudio(String path) async {
    final tempDir = await _temporaryDirectory();
    final tempPath = p.join(
      tempDir.path,
      'summary_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    final file = File(tempPath);
    var keepFile = false;

    try {
      final succeeded = await _transcriptionAudioExtractor(
        inputPath: path,
        outputPath: tempPath,
      );
      if (succeeded && await file.exists() && await file.length() > 0) {
        keepFile = true;
        return tempPath;
      }
      return null;
    } finally {
      if (!keepFile) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } on FileSystemException catch (error) {
          debugPrint('Failed to delete temporary summary audio: $error');
        }
      }
    }
  }

  static Future<bool> _extractTranscriptionAudio({
    required String inputPath,
    required String outputPath,
  }) async {
    final command =
        '-y -i "$inputPath" -vn -acodec pcm_s16le -ac 1 -ar 16000 "$outputPath"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      return true;
    }
    print(
      'Failed to extract transcription audio for $inputPath: '
      '${await session.getOutput()}',
    );
    return false;
  }
}

final mediaServiceProvider = Provider((ref) => MediaService());
