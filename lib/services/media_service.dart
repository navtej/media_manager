import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class MediaService {
  Future<Map<String, dynamic>> getMetadata(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    
    if (info == null) return {};

    final props = info.getAllProperties();
    // Return specific props or raw json
    // Flattening some useful bits
    final durationStr = info.getDuration() ?? "0";
    final duration = double.tryParse(durationStr) ?? 0.0;
    
    return {
      'duration': duration,
      'bitrate': info.getBitrate(),
      'raw': props,
    };
  }

  Future<Uint8List?> generateThumbnail(String path, double durationSeconds) async {
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
    
    // 10% mark
    final timestamp = durationSeconds * 0.10;
    // Format timestamp HH:MM:SS or just seconds might work for -ss depending on version, 
    // but typically seconds works.
    
    final command = '-ss $timestamp -i "$path" -vframes 1 -vf scale=480:-1 -q:v 2 "$tempPath"';
    
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      final file = File(tempPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await file.delete();
        return bytes;
      }
    } else {
      print('Failed to generate thumbnail for $path: ${await session.getOutput()}');
    }
    return null;
  }
}

final mediaServiceProvider = Provider((ref) => MediaService());
