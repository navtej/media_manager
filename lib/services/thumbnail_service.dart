import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service to handle persistent storage of thumbnails
class ThumbnailService {
  Directory? _thumbnailsDir;

  Future<void> init() async {
    if (_thumbnailsDir != null) return;
    
    final appDir = await getApplicationSupportDirectory();
    _thumbnailsDir = Directory(p.join(appDir.path, 'thumbnails'));
    
    if (!await _thumbnailsDir!.exists()) {
      await _thumbnailsDir!.create(recursive: true);
    }
  }

  Future<String> _ensureInit() async {
    await init();
    return _thumbnailsDir!.path;
  }

  /// Generates a unique filename for a new thumbnail.
  String generateFileName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return 'thumb_${timestamp}_$random.jpg';
  }

  /// Saves bytes to disk with the specific filename.
  /// Returns the absolute path.
  Future<String> saveThumbnail(String fileName, List<int> bytes) async {
    final dir = await _ensureInit();
    final path = p.join(dir, fileName);
    final file = File(path);
    await file.writeAsBytes(bytes);
    return path;
  }

  /// Deletes the file at the given absolute path.
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

final thumbnailServiceProvider = Provider((ref) => ThumbnailService());
