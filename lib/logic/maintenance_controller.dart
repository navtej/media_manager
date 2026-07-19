import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/providers.dart';
import '../services/media_deletion_service.dart';
import '../services/thumbnail_service.dart';
import 'library_controller.dart' show scanStatusProvider;
import 'managed_library_service.dart';
import 'stats_provider.dart';

part 'maintenance_controller.g.dart';

@Riverpod(keepAlive: true)
class MaintenanceController extends _$MaintenanceController {
  @override
  Future<void> build() async {
    // No init
  }

  Future<void> checkAndMigrateThumbnails() async {
    final videoDao = ref.read(videosDaoProvider);
    final thumbnailService = ref.read(thumbnailServiceProvider);

    try {
      final videosWithBlobs = await videoDao.getVideosWithBlobs();
      if (videosWithBlobs.isEmpty) return;

      print(
        'MIGRATION: Found ${videosWithBlobs.length} videos with blobs. Migrating to disk...',
      );
      ref
          .read(scanStatusProvider.notifier)
          .setStatus('Optimizing database (Moving images to disk)...');

      int count = 0;
      for (final video in videosWithBlobs) {
        if (video.thumbnailBlob != null) {
          final fileName = '${video.id}.jpg';
          final path = await thumbnailService.saveThumbnail(
            fileName,
            video.thumbnailBlob!,
          );
          await videoDao.updateVideoThumbnailPath(video.id, path);
          count++;

          if (count % 10 == 0) {
            ref
                .read(scanStatusProvider.notifier)
                .setStatus('Optimizing: $count/${videosWithBlobs.length}');
          }
        }
      }
      print('MIGRATION: Completed migrating $count thumbnails.');
      ref.read(scanStatusProvider.notifier).setStatus('');
    } catch (e) {
      print('ERROR during thumbnail migration: $e');
    }
  }

  Future<ManagedLibraryRemoveResult> removeFolder(int folderId) async {
    final result = await ref
        .read(managedLibraryServiceProvider)
        .remove(folderId);
    if (result.status == ManagedLibraryRemoveStatus.removed) {
      print(
        'DEBUG: Removed folder $folderId and '
        '${result.removedVideoCount} videos',
      );
      ref.invalidate(libraryStatsProvider);
    }
    return result;
  }

  Future<MediaDeletionResult> deleteVideo(int videoId) async {
    final result = await ref
        .read(mediaDeletionServiceProvider)
        .deleteVideo(videoId);
    if (result.isDeleted) {
      ref.invalidate(libraryStatsProvider);
    }
    return result;
  }

  Future<MediaDeletionBatchResult> deleteVideos(List<int> videoIds) async {
    final result = await ref
        .read(mediaDeletionServiceProvider)
        .deleteVideos(videoIds);
    if (result.deletedVideoIds.isNotEmpty) {
      ref.invalidate(libraryStatsProvider);
    }
    return result;
  }
}
