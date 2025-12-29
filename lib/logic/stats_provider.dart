import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/providers.dart';
import '../data/database.dart';

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

  String get formattedSize {
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    if (totalSizeBytes < 1024 * 1024 * 1024) return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
