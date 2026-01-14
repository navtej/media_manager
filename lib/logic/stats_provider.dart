import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/providers.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

part 'stats_provider.g.dart';

class LibraryStats {
  final int totalCount;
  final int totalDurationSeconds;
  final int totalSizeBytes;

  LibraryStats({
    required this.totalCount,
    required this.totalDurationSeconds,
    required this.totalSizeBytes,
  });

  String get formattedDuration {
    final hours = totalDurationSeconds ~/ 3600;
    final minutes = (totalDurationSeconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }

  String get formattedSize => formatSize(totalSizeBytes);

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

@riverpod
Stream<LibraryStats> libraryStats(Ref ref) {
  final dao = ref.watch(videosDaoProvider);
  return dao.watchAllVideos().map((videos) {
    final count = videos.length;
    final duration = videos.fold<double>(0.0, (prev, v) => prev + v.duration).toInt();
    final size = videos.fold<double>(0.0, (prev, v) => prev + v.size).toInt();
    
    print('DEBUG STATS: Count=$count, Size=$size bytes');
    
    return LibraryStats(
      totalCount: count,
      totalDurationSeconds: duration,
      totalSizeBytes: size,
    );
  });
}

@riverpod
Future<int> dataFolderSize(Ref ref) async {
  final dir = await getApplicationSupportDirectory();
  int totalSize = 0;
  try {
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }
  } catch (e) {
    // ignore
  }
  return totalSize;
}
