import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path/path.dart' as p;
import '../data/database.dart';
import '../data/providers.dart';
import '../services/thumbnail_service.dart';
import 'library_controller.dart' show scanStatusProvider;
import 'stats_provider.dart';
import 'library_controller.dart'; // Circular dependency risk? We need LibraryController for scanFolder. 
// Solution: We should NOT import LibraryController here. 
// Instead, MaintenanceController should expose methods that might trigger a scan, 
// or the caller should handle the re-scan.
// Ideally, `rebuildLibrary` calls `scanFolder`. So LibraryController should likely keep `rebuildLibrary` OR MaintenanceController needs a way to call `scanFolder`.
// Let's keep `rebuildLibrary` in LibraryController for now as it orchestrates everything? 
// OR simpler: LibraryController ref holds MaintenanceController ref? 
// No, Riverpod: ref.read(libraryControllerProvider) to trigger scan.

// Let's proceed with MaintenanceController handling pure maintenance (delete, clean),
// and LibraryController handling the high level "Rebuild" which is Delete All + Scan All.
// Actually, `rebuildLibrary` clears DB then Re-Scans.
// So `rebuildLibrary` belongs in LibraryController (Orchestrator).
// `deleteVideo` and `removeFolder` are maintenance actions.

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

      print('MIGRATION: Found ${videosWithBlobs.length} videos with blobs. Migrating to disk...');
      ref.read(scanStatusProvider.notifier).setStatus('Optimizing database (Moving images to disk)...');

      int count = 0;
      for (final video in videosWithBlobs) {
        if (video.thumbnailBlob != null) {
          final fileName = '${video.id}.jpg';
          final path = await thumbnailService.saveThumbnail(fileName, video.thumbnailBlob!);
          await videoDao.updateVideoThumbnailPath(video.id, path);
          count++;
          
          if (count % 10 == 0) {
             ref.read(scanStatusProvider.notifier).setStatus('Optimizing: $count/${videosWithBlobs.length}');
          }
        }
      }
      print('MIGRATION: Completed migrating $count thumbnails.');
      ref.read(scanStatusProvider.notifier).setStatus('');
    } catch (e) {
      print('ERROR during thumbnail migration: $e');
    }
  }

  Future<void> removeFolder(int folderId) async {
    final folderDao = ref.read(foldersDaoProvider);
    final videoDao = ref.read(videosDaoProvider);
    
    try {
      // Delete all videos in this folder from DB (cascade should handle tags)
      final videos = await videoDao.getVideosByFolder(folderId);
      for (final v in videos) {
        // Only delete from DB, keep files
        await videoDao.deleteVideo(v.id, deleteFile: false);
      }
      
      // Delete the folder entry
      await folderDao.deleteFolder(folderId);
      
      print('DEBUG: Removed folder $folderId and ${videos.length} videos');
      
      // Update stats
      ref.refresh(libraryStatsProvider);
    } catch (e) {
      print('ERROR in removeFolder: $e');
    }
  }

  Future<void> deleteVideo(int videoId) async {
    final videoDao = ref.read(videosDaoProvider);
    
    try {
      final video = await videoDao.getVideoById(videoId);
      if (video == null) return;
      
      final file = File(video.absolutePath);
      if (await file.exists()) {
        try {
          await file.delete();
          print('DEBUG: Deleted video file: ${video.absolutePath}');
          
          // Delete subtitle files with same basename
          final dir = file.parent;
          final basename = p.basenameWithoutExtension(video.absolutePath);
          final extensionsToCheck = ['.vtt', '.srt', '.VTT', '.SRT'];
          
          if (await dir.exists()) {
             await for (final entity in dir.list(followLinks: false)) {
               if (entity is File) {
                 final entityName = p.basename(entity.path);
                 if (entityName.startsWith(basename) && extensionsToCheck.contains(p.extension(entity.path))) {
                   try {
                     await entity.delete();
                     print('DEBUG: Deleted associated subtitle: ${entity.path}');
                   } catch (e) {
                     print('WARN: Failed to delete subtitle ${entity.path}: $e');
                   }
                 }
               }
             }
          }
        } catch (e) {
          print('ERROR: Failed to delete video file on disk: $e');
          // Proceed to delete from DB anyway so UI is consistent
        }
      }
      
      await videoDao.deleteVideo(videoId, deleteFile: false);
      print('DEBUG: Deleted video from DB');
      
      // Update stats immediately
      ref.refresh(libraryStatsProvider);
      
    } catch (e) {
      print('ERROR in deleteVideo: $e');
    }
  }
}
