import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path/path.dart' as p;
import '../data/database.dart';
import '../data/providers.dart';
import '../services/scanner_service.dart';
import '../services/media_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/natural_language_service.dart';
import 'stats_provider.dart';
import 'settings_provider.dart';
import '../services/thumbnail_service.dart';
import 'ai_controller.dart';
import 'maintenance_controller.dart';

part 'library_controller.g.dart';

@Riverpod(keepAlive: true)
class ScanStatus extends _$ScanStatus {
  @override
  String build() => ''; // Empty string = Idle
  
  void setStatus(String status) => state = status;
}

// AIStatus moved to ai_controller.dart

@Riverpod(keepAlive: true)
class LibraryController extends _$LibraryController {
  bool _isScanning = false;
  Timer? _periodicTimer;

  @override
  Future<void> build() async {
    print('DEBUG: LibraryController.build starting');
    
    // Get initial settings and setup timer
    final settings = await ref.read(settingsProvider.future);
    final initialInterval = settings['scanInterval'] ?? 5;
    _setupTimer(initialInterval);

    // Listen for settings changes to update the timer
    ref.listen(settingsProvider, (previous, next) {
      final oldInterval = previous?.value?['scanInterval'];
      final newInterval = next.value?['scanInterval'];
      
      if (newInterval != null && oldInterval != newInterval) {
        print('DEBUG: Scan interval changed from $oldInterval to $newInterval. Updating timer.');
        _setupTimer(newInterval);
      }
    });

    ref.onDispose(() {
      print('DEBUG: Disposing LibraryController');
      _periodicTimer?.cancel();
    });

    // Trigger startup scan in the background
    Future.microtask(() async {
      print('DEBUG: LibraryController microtask triggering syncAll');
      await ref.read(maintenanceControllerProvider.notifier).checkAndMigrateThumbnails();
      syncAll();
    });
  }

  // _checkAndMigrateThumbnails moved to maintenance_controller.dart
  
  Future<void> syncAll() async {
    if (_isScanning) {
      print('DEBUG: syncAll ignored, scan already in progress');
      // Set status briefly to inform user why it was ignored if they clicked button
      ref.read(scanStatusProvider.notifier).setStatus('Scan already in progress');
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isScanning) ref.read(scanStatusProvider.notifier).setStatus('');
      });
      return;
    }

    try {
      _isScanning = true;
      ref.read(scanStatusProvider.notifier).setStatus('Checking for updates...');
      
      print('DEBUG: syncAll starting...');
      final folderDao = ref.read(foldersDaoProvider);
      final videoDao = ref.read(videosDaoProvider);
      final tagDao = ref.read(tagsDaoProvider);
      final db = ref.read(databaseProvider);
      
      final folders = await folderDao.getAllFolders();
      print('DEBUG: syncAll found ${folders.length} folders');
      
      final toDelete = <int>[];
      final toMarkOffline = <int>[];
      final toMarkOnline = <int>[];
      final toUpdateSize = <int, int>{};
      final toUpdateDate = <int, DateTime>{};

      for (final f in folders) {
        final folderDir = Directory(f.path);
        final folderExists = await folderDir.exists();
        
        final folderVideos = await videoDao.getVideosByFolder(f.id);

        if (!folderExists) {
          print('DEBUG: Folder ${f.path} is offline');
          for (final v in folderVideos) {
            if (!v.isOffline) toMarkOffline.add(v.id);
          }
          continue; // Skip scanning and individual file checks for offline folders
        }

        // Folder exists - mark all as online (if they were offline)
        print('DEBUG: Folder ${f.path} is online');
        for (final v in folderVideos) {
          if (v.isOffline) toMarkOnline.add(v.id);
          
          final file = File(v.absolutePath);
          final fileExists = await file.exists();
          
          if (!fileExists) {
            toDelete.add(v.id);
            continue;
          }

          if (v.size == 0) {
            final size = await file.length();
            toUpdateSize[v.id] = size;
          }

          if (v.fileCreatedAt == null) {
            final stat = await file.stat();
            toUpdateDate[v.id] = stat.modified;
          }
        }

        // Scan for new files only if folder is online
        await scanFolder(f.path, f.id);
      }

      if (toDelete.isNotEmpty || toMarkOffline.isNotEmpty || toMarkOnline.isNotEmpty || 
          toUpdateSize.isNotEmpty || toUpdateDate.isNotEmpty) {
        print('DEBUG: Starting transactional maintenance (Delete: ${toDelete.length}, Offline: ${toMarkOffline.length}, Online: ${toMarkOnline.length}, Size: ${toUpdateSize.length}, Date: ${toUpdateDate.length})');
        
        await db.transaction(() async {
          if (toDelete.isNotEmpty) {
            await videoDao.deleteVideosByIds(toDelete);
          }
          if (toMarkOffline.isNotEmpty) {
            await videoDao.updateVideosOfflineStatusBatch(toMarkOffline, true);
          }
          if (toMarkOnline.isNotEmpty) {
            await videoDao.updateVideosOfflineStatusBatch(toMarkOnline, false);
          }
          for (final entry in toUpdateSize.entries) {
            await videoDao.updateVideoSize(entry.key, entry.value);
          }
          for (final entry in toUpdateDate.entries) {
            await videoDao.updateVideoCreationDate(entry.key, entry.value);
          }
        });
        
        print('DEBUG: Transactional maintenance completed');
      }

      await tagDao.pruneEmptyTags();
      print('DEBUG: syncAll completed successfully');
      
      // Ensure AI worker is running if there are pending videos
      ref.read(aIControllerProvider.notifier).startWorker();
    } catch (e, stack) {
      print('ERROR in syncAll: $e');
      print(stack);
    } finally {
      _isScanning = false;
      ref.read(scanStatusProvider.notifier).setStatus('');
    }
  }

  void _setupTimer(int interval) {
    if (_periodicTimer != null) {
      print('DEBUG: Cancelling existing refresh timer');
      _periodicTimer?.cancel();
    }
    
    print('DEBUG: Creating new periodic scan timer with interval: $interval minutes');
    _periodicTimer = Timer.periodic(Duration(minutes: interval), (_) {
      print('DEBUG: Periodic scan timer triggered');
      syncAll();
    });
  }

  Future<void> addFolder(String path) async {
    if (_isScanning) {
      print('DEBUG: addFolder ignored, scan already in progress');
      ref.read(scanStatusProvider.notifier).setStatus('Scan already in progress');
      return;
    }
    print('DEBUG: addFolder called with $path');
    final dao = ref.read(foldersDaoProvider);
    
    // Check if exists first to get ID
    final folders = await dao.getAllFolders();
    final existing = folders.where((f) => f.path == path).toList();
    
    int id;
    if (existing.isNotEmpty) {
      id = existing.first.id;
      print('DEBUG: Folder already exists with ID: $id');
    } else {
      id = await dao.insertFolder(FoldersCompanion(
        path: drift.Value(path),
        alias: drift.Value(p.basename(path)),
      ));
      if (id == 0) {
         // Should not happen with the check above, but for safety:
         final refetched = await dao.getAllFolders();
         id = refetched.firstWhere((f) => f.path == path).id;
      }
      print('DEBUG: Folder inserted with ID: $id');
    }
    
    // Start scan
    scanFolder(path, id);
  }

  // removeFolder moved to maintenance_controller.dart
  // deleteVideo moved to maintenance_controller.dart

  Future<void> rebuildLibrary() async {
    if (_isScanning) {
      print('DEBUG: rebuildLibrary ignored, scan in progress');
      ref.read(scanStatusProvider.notifier).setStatus('Scan already in progress');
      return;
    }
    
    try {
      _isScanning = true;
      ref.read(scanStatusProvider.notifier).setStatus('Rebuilding library...');
      
      final db = ref.read(databaseProvider);
      await db.clearAllData();
      
      print('DEBUG: Library cleared, starting full sync...');
      
      // Perform sync logic directly here to keep _isScanning = true
      final folderDao = ref.read(foldersDaoProvider);
      final folders = await folderDao.getAllFolders();
      for (final f in folders) {
        await scanFolder(f.path, f.id);
      }
      
      print('DEBUG: Rebuild completed successfully');
    } catch (e) {
      print('ERROR rebuilding library: $e');
      ref.read(scanStatusProvider.notifier).setStatus('Rebuild failed');
    } finally {
      _isScanning = false;
      ref.read(scanStatusProvider.notifier).setStatus('');
    }
  }
  
  Future<void> scanFolder(String rootPath, int folderId) async {
    print('DEBUG: scanFolder called for $rootPath');
    ref.read(scanStatusProvider.notifier).setStatus('Scanning $rootPath...');
    
    final scanner = ref.read(scannerServiceProvider);
    final videoDao = ref.read(videosDaoProvider);
    
    // 1. Get existing videos for this folder to skip them (Set for O(1) lookup)
    final existingVideos = await videoDao.getVideosByFolder(folderId);
    final existingPaths = existingVideos.map((v) => v.absolutePath).toSet();
    
    int processedCount = 0;
    final List<VideosCompanion> batchCompanions = [];
    final settings = await ref.read(settingsProvider.future);
    final dbBatchSize = settings['batchSize'] ?? 4;

    try {
      // 2. Consume Stream
      await for (final pathBatch in scanner.scanPaths([rootPath])) {
        // Filter new files immediately
        final newPaths = pathBatch.where((p) => !existingPaths.contains(p)).toList();
        
        if (newPaths.isEmpty) continue;
        
        ref.read(scanStatusProvider.notifier).setStatus('Processing ${newPaths.length} new files...');
        
        for (final filePath in newPaths) {
          final fileName = p.basename(filePath);
          processedCount++;
          ref.read(scanStatusProvider.notifier).setStatus('Adding: $fileName');
          
          final companion = await _prepareVideoCompanion(filePath, folderId);
          if (companion != null) {
            batchCompanions.add(companion);
          }

          // Commit to DB when batch is full
          if (batchCompanions.length >= dbBatchSize) {
             await videoDao.insertVideosBatch(batchCompanions);
             batchCompanions.clear();
             // Trigger AI worker to run in background while we continue scanning
             ref.read(aIControllerProvider.notifier).startWorker();
          }
        }
      }
      
      // 3. Commit remaining
      if (batchCompanions.isNotEmpty) {
        await videoDao.insertVideosBatch(batchCompanions);
        batchCompanions.clear();
        ref.read(aIControllerProvider.notifier).startWorker();
      }
      
      print('DEBUG: Scan complete for $rootPath. Processed $processedCount new videos.');
      
    } catch (e) {
      print('ERROR during scan of $rootPath: $e');
    } finally {
      ref.read(scanStatusProvider.notifier).setStatus('');
    }
  }

  Future<VideosCompanion?> _prepareVideoCompanion(String filePath, int folderId) async {
    final mediaService = ref.read(mediaServiceProvider);
    final thumbnailService = ref.read(thumbnailServiceProvider);
    
    try {
      final file = File(filePath);
      final size = file.lengthSync();
      final stat = file.statSync();
      
      // 1. Metadata
      final meta = await mediaService.getMetadata(filePath);
      final duration = (meta['duration'] as num?)?.toInt() ?? 0;
      
      // 2. Thumbnail
      String? thumbPath;
      final thumbBytes = await mediaService.generateThumbnail(filePath, duration.toDouble());
      
      if (thumbBytes != null) {
        final fileName = thumbnailService.generateFileName();
        thumbPath = await thumbnailService.saveThumbnail(fileName, thumbBytes);
      }
      
      // 3. Prepare Companion
      return VideosCompanion(
        folderId: drift.Value(folderId),
        absolutePath: drift.Value(filePath),
        title: drift.Value(p.basenameWithoutExtension(filePath)),
        duration: drift.Value(duration),
        size: drift.Value(size),
        fileCreatedAt: drift.Value(stat.modified),
        thumbnailBlob: const drift.Value(null), // No more blobs
        thumbnailPath: drift.Value(thumbPath),
        metadataJson: drift.Value(jsonEncode(meta)),
        aiProcessed: const drift.Value(false),
      );
      
    } catch (e) {
      print('Error preparing $filePath: $e');
      return null;
    }
  }

  // AI Logic moved to ai_controller.dart
}

