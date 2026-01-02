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

part 'library_controller.g.dart';

@Riverpod(keepAlive: true)
class ScanStatus extends _$ScanStatus {
  @override
  String build() => ''; // Empty string = Idle
  
  void setStatus(String status) => state = status;
}

@Riverpod(keepAlive: true)
class AIStatus extends _$AIStatus {
  @override
  String build() => '';
  
  void setStatus(String status) => state = status;
}

@Riverpod(keepAlive: true)
class LibraryController extends _$LibraryController {
  bool _isScanning = false;
  bool _isAIWorkerRunning = false;
  Timer? _periodicTimer;

  @override
  Future<void> build() async {
    print('DEBUG: LibraryController.build starting');
    // Trigger startup scan
    Future.microtask(() {
      print('DEBUG: LibraryController microtask triggering syncAll');
      syncAll();
    });
  }
  
  Future<void> syncAll() async {
    if (_isScanning) {
      print('DEBUG: syncAll ignored, scan already in progress');
      return;
    }

    try {
      _isScanning = true;
      await _resetTimer();
      print('DEBUG: syncAll starting...');
      final folderDao = ref.read(foldersDaoProvider);
      final videoDao = ref.read(videosDaoProvider);
      final tagDao = ref.read(tagsDaoProvider);
      final db = ref.read(databaseProvider);
      
      final folders = await folderDao.getAllFolders();
      print('DEBUG: syncAll found ${folders.length} folders');
      for (final f in folders) {
        await scanFolder(f.path, f.id);
      }

      // Collect all maintenance tasks
      final videos = await videoDao.getAllVideos();
      final toDelete = <int>[];
      final toUpdateSize = <int, int>{};
      final toUpdateDate = <int, DateTime>{};

      for (final v in videos) {
        final file = File(v.absolutePath);
        final exists = await file.exists();
        
        if (!exists) {
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

      if (toDelete.isNotEmpty || toUpdateSize.isNotEmpty || toUpdateDate.isNotEmpty) {
        print('DEBUG: Starting transactional maintenance (Delete: ${toDelete.length}, Size: ${toUpdateSize.length}, Date: ${toUpdateDate.length})');
        
        await db.transaction(() async {
          if (toDelete.isNotEmpty) {
            await videoDao.deleteVideosByIds(toDelete);
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
      _startAIWorker();
    } catch (e, stack) {
      print('ERROR in syncAll: $e');
      print(stack);
    } finally {
      _isScanning = false;
    }
  }

  Future<void> _resetTimer() async {
    _periodicTimer?.cancel();
    final settings = await ref.read(settingsProvider.future);
    final interval = settings['scanInterval'] ?? 5;
    
    print('DEBUG: Starting periodic scan with interval: $interval minutes');
    _periodicTimer = Timer.periodic(Duration(minutes: interval), (_) {
      syncAll();
    });
  }

  Future<void> addFolder(String path) async {
    if (_isScanning) {
      print('DEBUG: addFolder ignored, scan already in progress');
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

  Future<void> rebuildLibrary() async {
    if (_isScanning) {
      print('DEBUG: rebuildLibrary ignored, scan in progress');
      return;
    }
    
    try {
      _isScanning = true;
      ref.read(scanStatusProvider.notifier).setStatus('Rebuilding library...');
      
      final db = ref.read(databaseProvider);
      await db.clearAllData();
      
      print('DEBUG: Library cleared, restarting syncAll...');
      // Reset scanning flag to allow syncAll to proceed
      _isScanning = false; 
      await syncAll();
    } catch (e) {
      print('ERROR rebuilding library: $e');
      _isScanning = false;
      ref.read(scanStatusProvider.notifier).setStatus('Rebuild failed');
    }
  }
  
  Future<void> scanFolder(String rootPath, int folderId) async {
    print('DEBUG: scanFolder called for $rootPath');
    ref.read(scanStatusProvider.notifier).setStatus('Finding files in $rootPath...');
    
    final scanner = ref.read(scannerServiceProvider);
    final videoDao = ref.read(videosDaoProvider);
    
    final files = <String>[];
    await scanner.scanFolders([rootPath], (filePath) {
      files.add(filePath);
    });
    
    print('DEBUG: Total files discovered on disk: ${files.length}');
    
    // Get existing videos for this folder to skip them
    final existingVideos = await videoDao.getVideosByFolder(folderId);
    final existingPaths = existingVideos.map((v) => v.absolutePath).toSet();
    
    final newFiles = files.where((f) => !existingPaths.contains(f)).toList();
    
    if (newFiles.isEmpty) {
      print('DEBUG: No new files to process in $rootPath');
      ref.read(scanStatusProvider.notifier).setStatus('');
      return;
    }

    print('DEBUG: Found ${newFiles.length} new videos to process');
    ref.read(scanStatusProvider.notifier).setStatus('Processing ${newFiles.length} new videos...');
    
    final List<VideosCompanion> batchCompanions = [];
    final settings = await ref.read(settingsProvider.future);
    final batchSize = settings['batchSize'] ?? 4;

    for (int i = 0; i < newFiles.length; i++) {
      final filePath = newFiles[i];
      final fileName = p.basename(filePath);
      ref.read(scanStatusProvider.notifier).setStatus('Adding ${i + 1}/${newFiles.length}: $fileName');
      
      final companion = await _prepareVideoCompanion(filePath, folderId);
      if (companion != null) {
        batchCompanions.add(companion);
      }

      // Commit batch
      if (batchCompanions.length >= batchSize || (i == newFiles.length - 1 && batchCompanions.isNotEmpty)) {
        await videoDao.insertVideosBatch(batchCompanions);
        batchCompanions.clear();
        
        // Trigger AI worker IMMEDIATELY after each batch insertion to run in parallel with remaining scanning
        _startAIWorker();
      }
    }
    
    ref.read(scanStatusProvider.notifier).setStatus('');
  }
  
  Future<VideosCompanion?> _prepareVideoCompanion(String filePath, int folderId) async {
    final mediaService = ref.read(mediaServiceProvider);
    
    try {
      final file = File(filePath);
      final size = file.lengthSync();
      final stat = file.statSync();
      
      // 1. Metadata
      final meta = await mediaService.getMetadata(filePath);
      final duration = (meta['duration'] as num?)?.toInt() ?? 0;
      
      // 2. Thumbnail
      final thumbBytes = await mediaService.generateThumbnail(filePath, duration.toDouble());
      
      // 3. Prepare Companion
      return VideosCompanion(
        folderId: drift.Value(folderId),
        absolutePath: drift.Value(filePath),
        title: drift.Value(p.basenameWithoutExtension(filePath)),
        duration: drift.Value(duration),
        size: drift.Value(size),
        fileCreatedAt: drift.Value(stat.modified),
        thumbnailBlob: drift.Value(thumbBytes),
        metadataJson: drift.Value(jsonEncode(meta)),
        aiProcessed: const drift.Value(false),
      );
      
    } catch (e) {
      print('Error preparing $filePath: $e');
      return null;
    }
  }

  Future<void> _startAIWorker() async {
    if (_isAIWorkerRunning) return;
    _isAIWorkerRunning = true;
    _runAIWorker();
  }

  Future<void> _runAIWorker() async {
    try {
      final videoDao = ref.read(videosDaoProvider);
      final tagDao = ref.read(tagsDaoProvider);
      final db = ref.read(databaseProvider);

      while (true) {
        // Fetch fresh list of pending videos every loop
        final allVideos = await videoDao.getAllVideos();
        final pending = allVideos.where((v) => !v.aiProcessed).toList();
        
        if (pending.isEmpty) {
          ref.read(aIStatusProvider.notifier).setStatus('');
          break;
        }

        ref.read(aIStatusProvider.notifier).setStatus('AI Tagging: ${pending.length} remaining...');
        
        // Take a batch of up to 4
        final batchSize = pending.length >= 4 ? 4 : pending.length;
        final currentBatch = pending.take(batchSize).toList();

        // Prepare data for Isolate
        final List<Map<String, dynamic>> taskData = currentBatch.map((v) {
          final Map<String, dynamic> meta = jsonDecode(v.metadataJson ?? '{}');
          final Map<String, dynamic> raw = (meta['raw'] as Map?)?.cast<String, dynamic>() ?? {};
          final Map<String, dynamic> format = (raw['format'] as Map?)?.cast<String, dynamic>() ?? {};
          final Map<String, dynamic> tags = (format['tags'] as Map?)?.cast<String, dynamic>() ?? {};
          
          final title = tags['title'] ?? v.title;
          final description = tags['description'] ?? '';
          final synopsis = tags['synopsis'] ?? '';
          
          String promptText = [title, description, synopsis]
              .where((s) => s.toString().isNotEmpty)
              .join('\n');
          
          // Pre-processing: Remove URLs and Emojis
          // URL Regex
          promptText = promptText.replaceAll(RegExp(r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)'), '');
          // Emoji Regex (Simple range based)
          promptText = promptText.replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}]', unicode: true), '');
          
          // Extract hashtags before they get processed
          // Matches #word where word can contain letters, numbers, underscores (supports camelCase and underscore variants)
          final hashtagRegex = RegExp(r'#([a-zA-Z][a-zA-Z0-9_]*)(?:\s|$|[^\w])');
          final extractedHashtags = hashtagRegex.allMatches(promptText)
              .map((m) => m.group(1)!)
              .take(7)
              .toList();
          
          return {
            'id': v.id,
            'title': v.title,
            'prompt': promptText,
            'extractedHashtags': extractedHashtags,
          };
        }).toList();

        // RUN IN ISOLATE
        final results = await compute(_aiIsolateWorker, {
          'tasks': taskData,
          'token': RootIsolateToken.instance!,
        });

        // Commit the batch
        final List<int> processedIds = [];
        final List<TagsCompanion> batchTags = [];

        for (final res in (results as List)) {
          final id = res['id'] as int;
          final suggestions = (res['suggestions'] as List).cast<String>();
          final extractedHashtags = (res['extractedHashtags'] as List?)?.cast<String>() ?? [];
          
          // Combine AI suggestions with extracted hashtags (using Set to prevent duplicates)
          final allTags = <String>{...suggestions, ...extractedHashtags};
          
          for (final tag in allTags) {
            batchTags.add(TagsCompanion(
              videoId: drift.Value(id),
              tagText: drift.Value(tag),
              source: drift.Value('auto'),
            ));
          }
          processedIds.add(id);
        }

        if (processedIds.isNotEmpty) {
          await db.transaction(() async {
            if (batchTags.isNotEmpty) {
              await tagDao.insertTagsBatch(batchTags);
            }
            await videoDao.updateVideosAiProcessedBatch(processedIds, true);
          });
        }
      }
    } catch (e) {
      print('ERROR in AI Worker Loop: $e');
    } finally {
      _isAIWorkerRunning = false;
    }
  }
}

/// Dedicated static worker for AI Isolate
Future<List<Map<String, dynamic>>> _aiIsolateWorker(Map<String, dynamic> args) async {
  final List<Map<String, dynamic>> tasks = (args['tasks'] as List).cast<Map<String, dynamic>>();
  final RootIsolateToken token = args['token'];
  
  // Initialize communication with native side from background isolate
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  
  final List<Map<String, dynamic>> results = [];
  for (final task in tasks) {
    final id = task['id'] as int;
    final title = task['title'] as String;
    final prompt = task['prompt'] as String;
    final extractedHashtags = (task['extractedHashtags'] as List?)?.cast<String>() ?? <String>[];
    
    try {
      final now = DateTime.now();
      print('DEBUG ISOLATE: Serial AI Task START for: $title at ${now.minute}:${now.second}.${now.millisecond}');
      
      final suggestions = await NaturalLanguageService.extractTagsStatic(prompt);
      
      final end = DateTime.now();
      print('DEBUG ISOLATE: Serial AI Task COMPLETE for: $title at ${end.minute}:${end.second}.${end.millisecond}');
      
      results.add({'id': id, 'suggestions': suggestions, 'extractedHashtags': extractedHashtags});
    } catch (e) {
      print('ERROR in AI Isolate for $title: $e');
      results.add({'id': id, 'suggestions': <String>[], 'extractedHashtags': extractedHashtags});
    }
  }
  
  return results;
}
