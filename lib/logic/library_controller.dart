import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path/path.dart' as p;
import '../data/database.dart';
import '../data/providers.dart';
import '../services/scanner_service.dart';
import '../services/library_access_service.dart';
import '../services/media_service.dart';
import 'settings_provider.dart';
import '../services/thumbnail_service.dart';
import '../services/video_version_service.dart';
import 'ai_controller.dart';
import 'maintenance_controller.dart';
import 'library_operation_controller.dart';
import 'managed_library_service.dart';

part 'library_controller.g.dart';

typedef PeriodicScanTimerFactory =
    Timer Function(Duration duration, void Function(Timer timer) callback);

enum LibraryAddFlowStatus {
  completed,
  scanInProgress,
  moveInProgress,
  maintenanceInProgress,
}

class LibraryAddFlowResult {
  const LibraryAddFlowResult({required this.status, this.managedLibraryResult});

  final LibraryAddFlowStatus status;
  final ManagedLibraryAddResult? managedLibraryResult;
}

final periodicScanTimerFactoryProvider = Provider<PeriodicScanTimerFactory>(
  (ref) => Timer.periodic,
);

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
  bool _scanPending = false;
  Timer? _periodicTimer;

  @override
  Future<void> build() async {
    print('DEBUG: LibraryController.build starting');

    // Get initial settings and setup timer
    final synchronization = (await ref.read(
      settingsProvider.future,
    )).librarySynchronization;
    final initialInterval = synchronization.scanIntervalMinutes;
    await ref.read(managedLibraryServiceProvider).normalizeNames();
    _setupTimer(initialInterval);

    // Listen for settings changes to update the timer
    ref.listen(settingsProvider, (previous, next) {
      final oldInterval =
          previous?.asData?.value.librarySynchronization.scanIntervalMinutes;
      final newInterval =
          next.asData?.value.librarySynchronization.scanIntervalMinutes;

      if (newInterval != null && oldInterval != newInterval) {
        print(
          'DEBUG: Scan interval changed from $oldInterval to $newInterval. Updating timer.',
        );
        _setupTimer(newInterval);
      }
    });
    ref.listen(libraryOperationControllerProvider, (previous, next) {
      if (_scanPending && (previous?.isBusy ?? false) && !next.isBusy) {
        _scanPending = false;
        unawaited(syncAll());
      }
    });

    ref.onDispose(() {
      print('DEBUG: Disposing LibraryController');
      _periodicTimer?.cancel();
    });

    // Trigger startup scan in the background
    Future.microtask(() async {
      print('DEBUG: LibraryController microtask triggering syncAll');
      await ref
          .read(maintenanceControllerProvider.notifier)
          .checkAndMigrateThumbnails();
      syncAll();
    });
  }

  // _checkAndMigrateThumbnails moved to maintenance_controller.dart

  Future<void> syncAll({bool showBusyStatus = true}) async {
    if (_isScanning) {
      if (showBusyStatus) {
        print('DEBUG: syncAll ignored, scan already in progress');
        // Only an explicit request should replace the active scan status. A
        // periodic tick is expected to overlap a long-running scan.
        ref
            .read(scanStatusProvider.notifier)
            .setStatus('Scan already in progress');
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isScanning) ref.read(scanStatusProvider.notifier).setStatus('');
        });
      }
      return;
    }

    final operation = ref.read(libraryOperationControllerProvider.notifier);
    if (!operation.beginScan()) {
      final operationState = ref.read(libraryOperationControllerProvider);
      if (!operationState.isScanning) {
        _scanPending = true;
      }
      if (showBusyStatus) {
        ref
            .read(scanStatusProvider.notifier)
            .setStatus(_operationBlockedMessage(operationState));
        Future.delayed(const Duration(seconds: 2), () {
          if (!ref.read(libraryOperationControllerProvider).isBusy) {
            ref.read(scanStatusProvider.notifier).setStatus('');
          }
        });
      }
      return;
    }
    _scanPending = false;

    try {
      _isScanning = true;
      ref
          .read(scanStatusProvider.notifier)
          .setStatus('Checking for updates...');

      print('DEBUG: syncAll starting...');
      final folderDao = ref.read(foldersDaoProvider);
      final videoDao = ref.read(videosDaoProvider);
      final tagDao = ref.read(tagsDaoProvider);
      final versionDao = ref.read(videoVersionsDaoProvider);
      final db = ref.read(databaseProvider);
      final deletedSidecars = await videoDao.deleteAppleDoubleSidecarVideos();
      if (deletedSidecars > 0) {
        print('DEBUG: Removed $deletedSidecars AppleDouble sidecar rows');
      }

      final folders = await folderDao.getAllFolders();
      print('DEBUG: syncAll found ${folders.length} folders');

      // Video id -> the primary path that was found missing.
      final toDelete = <int, String>{};
      final toDeleteThumbnailPaths = <int, String?>{};
      final toPromote = <_VersionPromotion>[];
      // Version row id -> the non-primary path that was found missing.
      final toPruneVersions = <int, String>{};
      final toMarkOffline = <int>[];
      final toMarkOnline = <int>[];
      final toUpdateSize = <int, int>{};
      final toUpdateDate = <int, DateTime>{};

      for (final f in folders) {
        final folderVideos = await videoDao.getVideosByFolder(f.id);
        final versionsByVideo = <int, List<VideoVersion>>{};
        for (final row in await versionDao.getVersionsForVideos(
          folderVideos.map((v) => v.id).toList(growable: false),
        )) {
          versionsByVideo.putIfAbsent(row.videoId, () => []).add(row);
        }
        try {
          await ref
              .read(libraryAccessServiceProvider)
              .withAccess(
                library: LibraryAccessRequest(
                  path: f.path,
                  bookmark: f.securityScopedBookmark,
                ),
                action: () async {
                  final folderDir = Directory(f.path);
                  final folderExists = await folderDir.exists();

                  if (!folderExists) {
                    print('DEBUG: Folder ${f.path} is offline');
                    for (final v in folderVideos) {
                      if (!v.isOffline) toMarkOffline.add(v.id);
                    }
                    return;
                  }

                  // Folder exists - mark all as online (if they were offline)
                  print('DEBUG: Folder ${f.path} is online');
                  for (final v in folderVideos) {
                    if (v.isOffline) toMarkOnline.add(v.id);

                    // Other files of a converted video: prune rows of
                    // missing files, remember the rest as fallbacks.
                    final otherVersions = <VideoVersion, FileStat>{};
                    for (final row
                        in versionsByVideo[v.id] ?? const <VideoVersion>[]) {
                      if (row.absolutePath == v.absolutePath) continue;
                      final stat = await File(row.absolutePath).stat();
                      if (stat.type == FileSystemEntityType.file) {
                        otherVersions[row] = stat;
                      } else {
                        toPruneVersions[row.id] = row.absolutePath;
                      }
                    }

                    final file = File(v.absolutePath);
                    final fileExists = await file.exists();

                    if (!fileExists) {
                      if (otherVersions.isNotEmpty) {
                        final candidates = otherVersions.keys.toList()
                          ..sort(
                            (a, b) => compareVideoVersionsForPromotion(
                              videoVersionInfoFromRow(
                                a,
                                primaryPath: v.absolutePath,
                              ),
                              videoVersionInfoFromRow(
                                b,
                                primaryPath: v.absolutePath,
                              ),
                            ),
                          );
                        final promoted = candidates.first;
                        toPromote.add(
                          _VersionPromotion(
                            videoId: v.id,
                            missingPrimaryPath: v.absolutePath,
                            version: promoted,
                            size: otherVersions[promoted]!.size,
                          ),
                        );
                        continue;
                      }
                      toDelete[v.id] = v.absolutePath;
                      toDeleteThumbnailPaths[v.id] = v.thumbnailPath;
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

                  await _scanFolderContents(f.path, f.id);
                },
              );
        } on LibraryAccessNeedsRepairException catch (error) {
          print('DEBUG: ${error.message}');
          ref.read(scanStatusProvider.notifier).setStatus(error.message);
          for (final v in folderVideos) {
            if (!v.isOffline) toMarkOffline.add(v.id);
          }
        }
      }

      if (toDelete.isNotEmpty ||
          toPromote.isNotEmpty ||
          toPruneVersions.isNotEmpty ||
          toMarkOffline.isNotEmpty ||
          toMarkOnline.isNotEmpty ||
          toUpdateSize.isNotEmpty ||
          toUpdateDate.isNotEmpty) {
        print(
          'DEBUG: Starting transactional maintenance (Delete: ${toDelete.length}, Offline: ${toMarkOffline.length}, Online: ${toMarkOnline.length}, Size: ${toUpdateSize.length}, Date: ${toUpdateDate.length})',
        );

        final deletedIds = <int>[];
        await db.transaction(() async {
          // Re-check every row against what was inspected so a concurrent
          // change can never cause a wrong delete or promotion.
          if (toDelete.isNotEmpty) {
            final current = await videoDao.getVideosByIds(
              toDelete.keys.toList(growable: false),
            );
            deletedIds.addAll(
              current
                  .where((v) => toDelete[v.id] == v.absolutePath)
                  .map((v) => v.id),
            );
            await videoDao.deleteVideosByIds(deletedIds);
          }
          for (final promotion in toPromote) {
            await _applyVersionPromotion(db, promotion);
          }
          for (final entry in toPruneVersions.entries) {
            final row = await versionDao.getVersionByPath(entry.value);
            if (row == null || row.id != entry.key) continue;
            final owner = await videoDao.getVideoById(row.videoId);
            if (owner?.absolutePath == row.absolutePath) continue;
            await versionDao.deleteVersionById(row.id);
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
        if (deletedIds.isNotEmpty) {
          try {
            await ref
                .read(thumbnailServiceProvider)
                .deleteManagedFiles(
                  deletedIds.map((id) => toDeleteThumbnailPaths[id]),
                );
          } catch (error) {
            print(
              'Could not remove thumbnails for stale catalog videos: $error',
            );
          }
        }
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
      operation.endScan();
      ref.read(scanStatusProvider.notifier).setStatus('');
    }
  }

  void _setupTimer(int interval) {
    if (_periodicTimer != null) {
      print('DEBUG: Cancelling existing refresh timer');
      _periodicTimer?.cancel();
    }

    print(
      'DEBUG: Creating new periodic scan timer with interval: $interval minutes',
    );
    _periodicTimer = ref.read(periodicScanTimerFactoryProvider)(
      Duration(minutes: interval),
      (_) {
        if (_isScanning) {
          return;
        }
        print('DEBUG: Periodic scan timer triggered');
        unawaited(syncAll(showBusyStatus: false));
      },
    );
  }

  Future<LibraryAddFlowResult> addFolder(String path) async {
    if (_isScanning) {
      print('DEBUG: addFolder ignored, scan already in progress');
      ref
          .read(scanStatusProvider.notifier)
          .setStatus('Scan already in progress');
      return const LibraryAddFlowResult(
        status: LibraryAddFlowStatus.scanInProgress,
      );
    }
    final operation = ref.read(libraryOperationControllerProvider.notifier);
    if (!operation.beginScan()) {
      final operationState = ref.read(libraryOperationControllerProvider);
      ref
          .read(scanStatusProvider.notifier)
          .setStatus(_operationBlockedMessage(operationState));
      return LibraryAddFlowResult(
        status: operationState.isCleaning
            ? LibraryAddFlowStatus.maintenanceInProgress
            : operationState.isScanning
            ? LibraryAddFlowStatus.scanInProgress
            : LibraryAddFlowStatus.moveInProgress,
      );
    }
    print('DEBUG: addFolder called with $path');
    try {
      final result = await ref
          .read(managedLibraryServiceProvider)
          .addOrRefresh(path);
      final folder = result.folder;
      if (folder == null) {
        return LibraryAddFlowResult(
          status: LibraryAddFlowStatus.completed,
          managedLibraryResult: result,
        );
      }
      print('DEBUG: Managed Library ready with ID: ${folder.id}');
      await _scanFolder(folder.path, folder.id);
      return LibraryAddFlowResult(
        status: LibraryAddFlowStatus.completed,
        managedLibraryResult: result,
      );
    } finally {
      operation.endScan();
    }
  }

  // removeFolder moved to maintenance_controller.dart
  // deleteVideo moved to maintenance_controller.dart

  Future<void> rebuildLibrary() async {
    if (_isScanning) {
      print('DEBUG: rebuildLibrary ignored, scan in progress');
      ref
          .read(scanStatusProvider.notifier)
          .setStatus('Scan already in progress');
      return;
    }
    final operation = ref.read(libraryOperationControllerProvider.notifier);
    if (!operation.beginScan()) {
      ref
          .read(scanStatusProvider.notifier)
          .setStatus(
            _operationBlockedMessage(
              ref.read(libraryOperationControllerProvider),
            ),
          );
      return;
    }

    try {
      _isScanning = true;
      ref.read(scanStatusProvider.notifier).setStatus('Rebuilding library...');

      final db = ref.read(databaseProvider);
      final existingVideos = await ref.read(videosDaoProvider).getAllVideos();
      // Clearing drops every version row; remember each converted video's
      // files so former non-primary versions are re-linked instead of being
      // imported as separate videos.
      final versionGroups = _snapshotVersionGroups(
        existingVideos,
        await ref.read(videoVersionsDaoProvider).getAllVersions(),
      );
      final formerVersionPaths = {
        for (final group in versionGroups) ...group.nonPrimaryPaths,
      };
      await db.clearAllData();
      try {
        await ref
            .read(thumbnailServiceProvider)
            .deleteManagedFiles(
              existingVideos.map((video) => video.thumbnailPath),
            );
      } catch (error) {
        print('Could not remove thumbnails for rebuilt Library: $error');
      }

      print('DEBUG: Library cleared, starting full sync...');

      // Perform sync logic directly here to keep _isScanning = true
      final folderDao = ref.read(foldersDaoProvider);
      final folders = await folderDao.getAllFolders();
      for (final f in folders) {
        await _scanFolder(f.path, f.id, skipPaths: formerVersionPaths);
      }

      final orphanedFolderIds = await _relinkVersionGroups(
        versionGroups,
        folders,
      );
      // Former versions whose primary was not re-imported are imported as
      // videos of their own rather than dropped.
      for (final f in folders.where((f) => orphanedFolderIds.contains(f.id))) {
        await _scanFolder(f.path, f.id);
      }

      print('DEBUG: Rebuild completed successfully');
    } catch (e) {
      print('ERROR rebuilding library: $e');
      ref.read(scanStatusProvider.notifier).setStatus('Rebuild failed');
    } finally {
      _isScanning = false;
      operation.endScan();
      ref.read(scanStatusProvider.notifier).setStatus('');
    }
  }

  Future<void> scanFolder(String rootPath, int folderId) async {
    final operation = ref.read(libraryOperationControllerProvider.notifier);
    if (!operation.beginScan()) {
      ref
          .read(scanStatusProvider.notifier)
          .setStatus(
            _operationBlockedMessage(
              ref.read(libraryOperationControllerProvider),
            ),
          );
      return;
    }
    try {
      await _scanFolder(rootPath, folderId);
    } finally {
      operation.endScan();
    }
  }

  Future<void> _scanFolder(
    String rootPath,
    int folderId, {
    Set<String> skipPaths = const {},
  }) async {
    final folder = await ref.read(foldersDaoProvider).getFolderById(folderId);
    if (folder == null) {
      ref
          .read(scanStatusProvider.notifier)
          .setStatus('Library folder is missing.');
      return;
    }

    try {
      await ref
          .read(libraryAccessServiceProvider)
          .withAccess(
            library: LibraryAccessRequest(
              path: folder.path,
              bookmark: folder.securityScopedBookmark,
            ),
            action: () => _scanFolderContents(
              folder.path,
              folder.id,
              skipPaths: skipPaths,
            ),
          );
    } on LibraryAccessNeedsRepairException catch (error) {
      ref.read(scanStatusProvider.notifier).setStatus(error.message);
    }
  }

  Future<void> _scanFolderContents(
    String rootPath,
    int folderId, {
    Set<String> skipPaths = const {},
  }) async {
    if (ref.read(libraryOperationControllerProvider).isMoving) {
      ref.read(scanStatusProvider.notifier).setStatus('Move in progress');
      return;
    }
    print('DEBUG: scanFolder called for $rootPath');
    ref.read(scanStatusProvider.notifier).setStatus('Scanning $rootPath...');

    final scanner = ref.read(scannerServiceProvider);
    final videoDao = ref.read(videosDaoProvider);
    final versionDao = ref.read(videoVersionsDaoProvider);

    // 1. Get existing videos for this folder to skip them (Set for O(1) lookup)
    final existingVideos = await videoDao.getVideosByFolder(folderId);
    await _repairMissingThumbnails(existingVideos);
    // Version files belong to their video and are never imported on their own.
    final existingPaths = existingVideos.map((v) => v.absolutePath).toSet()
      ..addAll(await versionDao.getAllVersionPaths())
      ..addAll(skipPaths);

    int processedCount = 0;
    final List<VideosCompanion> batchCompanions = [];
    final synchronization = (await ref.read(
      settingsProvider.future,
    )).librarySynchronization;
    final dbBatchSize = synchronization.batchSize;

    try {
      // 2. Consume Stream
      await for (final pathBatch in scanner.scanPaths([rootPath])) {
        // Filter new files immediately
        final candidatePaths = pathBatch
            .where((p) => !existingPaths.contains(p))
            .toList();

        if (candidatePaths.isEmpty) continue;

        // A version may have been registered since the scan started.
        final registered = await versionDao.registeredPaths(candidatePaths);
        existingPaths.addAll(registered);
        final newPaths = candidatePaths
            .where((p) => !registered.contains(p))
            .toList();
        if (newPaths.isEmpty) continue;

        ref
            .read(scanStatusProvider.notifier)
            .setStatus('Processing ${newPaths.length} new files...');

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
            await _insertUnregisteredVideos(batchCompanions);
            batchCompanions.clear();
            // Trigger AI worker to run in background while we continue scanning
            ref.read(aIControllerProvider.notifier).startWorker();
          }
        }
      }

      // 3. Commit remaining
      if (batchCompanions.isNotEmpty) {
        await _insertUnregisteredVideos(batchCompanions);
        batchCompanions.clear();
        ref.read(aIControllerProvider.notifier).startWorker();
      }

      print(
        'DEBUG: Scan complete for $rootPath. Processed $processedCount new videos.',
      );
    } catch (e) {
      print('ERROR during scan of $rootPath: $e');
    } finally {
      ref.read(scanStatusProvider.notifier).setStatus('');
    }
  }

  /// Inserts [companions] except paths that became registered (as a video
  /// or a version) while they were being prepared.
  Future<void> _insertUnregisteredVideos(
    List<VideosCompanion> companions,
  ) async {
    final registered = await ref
        .read(videoVersionsDaoProvider)
        .registeredPaths(companions.map((c) => c.absolutePath.value));
    final insertable = registered.isEmpty
        ? companions
        : companions
              .where((c) => !registered.contains(c.absolutePath.value))
              .toList(growable: false);
    if (insertable.isEmpty) return;
    await ref.read(videosDaoProvider).insertVideosBatch(insertable);
  }

  Future<void> _applyVersionPromotion(
    AppDatabase db,
    _VersionPromotion promotion,
  ) async {
    final video = await db.videosDao.getVideoById(promotion.videoId);
    final row = await db.videoVersionsDao.getVersionByPath(
      promotion.version.absolutePath,
    );
    if (video == null ||
        video.absolutePath != promotion.missingPrimaryPath ||
        row == null ||
        row.videoId != video.id) {
      return;
    }
    await (db.update(db.videos)..where((t) => t.id.equals(video.id))).write(
      VideosCompanion(
        absolutePath: drift.Value(row.absolutePath),
        size: drift.Value(promotion.size),
        duration: drift.Value(row.duration),
        metadataJson: drift.Value(row.metadataJson),
        isOffline: const drift.Value(false),
      ),
    );
    final missingRow = await db.videoVersionsDao.getVersionByPath(
      promotion.missingPrimaryPath,
    );
    if (missingRow != null && missingRow.videoId == video.id) {
      await db.videoVersionsDao.deleteVersionById(missingRow.id);
    }
  }

  /// Re-creates the version rows of [groups] under their re-imported primary
  /// videos. Returns the folders whose former versions lost their primary.
  Future<Set<int>> _relinkVersionGroups(
    List<_VersionGroupSnapshot> groups,
    List<Folder> folders,
  ) async {
    final foldersById = {for (final f in folders) f.id: f};
    final videoDao = ref.read(videosDaoProvider);
    final db = ref.read(databaseProvider);
    final orphanedFolderIds = <int>{};
    for (final group in groups) {
      final folder = foldersById[group.folderId];
      if (folder == null) continue;
      try {
        await ref
            .read(libraryAccessServiceProvider)
            .withAccess(
              library: LibraryAccessRequest(
                path: folder.path,
                bookmark: folder.securityScopedBookmark,
              ),
              action: () async {
                final video = await videoDao.getVideoByPath(group.primaryPath);
                if (video == null) {
                  orphanedFolderIds.add(folder.id);
                  return;
                }
                final companions = <VideoVersionsCompanion>[];
                for (final entry in group.versions) {
                  if (entry.absolutePath != group.primaryPath &&
                      !await File(entry.absolutePath).exists()) {
                    continue;
                  }
                  companions.add(
                    VideoVersionsCompanion.insert(
                      videoId: video.id,
                      absolutePath: entry.absolutePath,
                      width: drift.Value(entry.width),
                      height: drift.Value(entry.height),
                      duration: drift.Value(entry.duration),
                      size: drift.Value(entry.size),
                      metadataJson: drift.Value(entry.metadataJson),
                      isOriginal: drift.Value(entry.isOriginal),
                      createdAt: drift.Value(entry.createdAt),
                    ),
                  );
                }
                final hasOthers = companions.any(
                  (c) => c.absolutePath.value != group.primaryPath,
                );
                if (!hasOthers) return;
                if (!companions.any(
                  (c) => c.absolutePath.value == group.primaryPath,
                )) {
                  companions.add(
                    VideoVersionsCompanion.insert(
                      videoId: video.id,
                      absolutePath: video.absolutePath,
                      duration: drift.Value(video.duration),
                      size: drift.Value(video.size),
                      metadataJson: drift.Value(video.metadataJson),
                      isOriginal: drift.Value(
                        !companions.any((c) => c.isOriginal.value),
                      ),
                    ),
                  );
                }
                await db.batch((b) {
                  b.insertAll(
                    db.videoVersions,
                    companions,
                    mode: drift.InsertMode.insertOrIgnore,
                  );
                });
              },
            );
      } on LibraryAccessNeedsRepairException catch (error) {
        debugPrint('Could not re-link versions: ${error.message}');
      } catch (error) {
        debugPrint(
          'Could not re-link versions of ${group.primaryPath}: $error',
        );
      }
    }
    return orphanedFolderIds;
  }

  Future<VideosCompanion?> _prepareVideoCompanion(
    String filePath,
    int folderId,
  ) async {
    final mediaService = ref.read(mediaServiceProvider);
    final thumbnailService = ref.read(thumbnailServiceProvider);

    try {
      final file = File(filePath);
      // Directory.list() is a live stream. A removable volume, downloader,
      // or another process can make a candidate disappear before we process
      // it. Read both values from one async stat and treat that as a normal
      // per-file scan miss instead of reporting a startup error.
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        return null;
      }
      final size = stat.size;

      // 1. Metadata
      final meta = await mediaService.getMetadata(filePath);
      if (!mediaService.shouldAcceptCandidateVideo(filePath, meta)) {
        return null;
      }

      final duration = (meta['duration'] as num?)?.toInt() ?? 0;

      // 2. Thumbnail
      final thumbPath = await _generateThumbnailPath(
        filePath,
        duration.toDouble(),
        mediaService: mediaService,
        thumbnailService: thumbnailService,
      );

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
    } on FileSystemException catch (error) {
      if (_isIgnorableScanFileSystemError(error)) {
        return null;
      }
      print('Error preparing $filePath: $error');
      return null;
    } catch (e) {
      print('Error preparing $filePath: $e');
      return null;
    }
  }

  Future<void> _repairMissingThumbnails(List<Video> videos) async {
    final videosMissingThumbnails = <Video>[];
    for (final video in videos) {
      if (video.thumbnailBlob != null && video.thumbnailBlob!.isNotEmpty) {
        continue;
      }

      final sourceFile = File(video.absolutePath);
      try {
        if (!await sourceFile.exists() || await sourceFile.length() == 0) {
          continue;
        }
      } on FileSystemException {
        continue;
      }

      final thumbnailPath = video.thumbnailPath;
      if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
        try {
          final thumbnailFile = File(thumbnailPath);
          if (await thumbnailFile.exists() &&
              await thumbnailFile.length() > 0) {
            continue;
          }
        } on FileSystemException {
          // Treat an unreadable thumbnail as missing so the source video is
          // retried on the next scan.
        }
      }
      videosMissingThumbnails.add(video);
    }

    if (videosMissingThumbnails.isEmpty) {
      return;
    }

    final mediaService = ref.read(mediaServiceProvider);
    final thumbnailService = ref.read(thumbnailServiceProvider);
    final videoDao = ref.read(videosDaoProvider);
    print(
      'DEBUG: Retrying thumbnails for '
      '${videosMissingThumbnails.length} existing videos',
    );

    for (var index = 0; index < videosMissingThumbnails.length; index++) {
      final video = videosMissingThumbnails[index];
      ref
          .read(scanStatusProvider.notifier)
          .setStatus(
            'Generating thumbnail '
            '${index + 1}/${videosMissingThumbnails.length}...',
          );
      try {
        final thumbnailPath = await _generateThumbnailPath(
          video.absolutePath,
          video.duration.toDouble(),
          mediaService: mediaService,
          thumbnailService: thumbnailService,
        );
        if (thumbnailPath != null) {
          await videoDao.updateVideoThumbnailPath(video.id, thumbnailPath);
        }
      } catch (error) {
        print('Error repairing thumbnail for ${video.absolutePath}: $error');
      }
    }
  }

  Future<String?> _generateThumbnailPath(
    String filePath,
    double durationSeconds, {
    required MediaService mediaService,
    required ThumbnailService thumbnailService,
  }) async {
    final thumbBytes = await mediaService.generateThumbnail(
      filePath,
      durationSeconds,
    );
    if (thumbBytes == null || thumbBytes.isEmpty) {
      return null;
    }

    final fileName = thumbnailService.generateFileName();
    return thumbnailService.saveThumbnail(fileName, thumbBytes);
  }

  // AI Logic moved to ai_controller.dart
}

bool _isIgnorableScanFileSystemError(FileSystemException error) {
  final code = error.osError?.errorCode;
  // ENOENT is what a file that disappeared between directory enumeration and
  // preparation reports on macOS/Linux. Include the platform equivalents for
  // missing path and overlong-name failures so one bad candidate cannot abort
  // the rest of a scan.
  return code == 2 || // POSIX ENOENT
      code == 3 || // Windows ERROR_PATH_NOT_FOUND
      code == 20 || // POSIX ENOTDIR
      code == 36 || // Linux ENAMETOOLONG
      code == 63 || // macOS ENAMETOOLONG
      code == 206; // Windows ERROR_FILENAME_EXCED_RANGE
}

class _VersionPromotion {
  const _VersionPromotion({
    required this.videoId,
    required this.missingPrimaryPath,
    required this.version,
    required this.size,
  });

  final int videoId;
  final String missingPrimaryPath;
  final VideoVersion version;
  final int size;
}

class _VersionGroupSnapshot {
  const _VersionGroupSnapshot({
    required this.folderId,
    required this.primaryPath,
    required this.versions,
  });

  final int folderId;
  final String primaryPath;
  final List<VideoVersion> versions;

  Iterable<String> get nonPrimaryPaths =>
      versions.map((v) => v.absolutePath).where((path) => path != primaryPath);
}

List<_VersionGroupSnapshot> _snapshotVersionGroups(
  List<Video> videos,
  List<VideoVersion> versions,
) {
  final byVideo = <int, List<VideoVersion>>{};
  for (final version in versions) {
    byVideo.putIfAbsent(version.videoId, () => []).add(version);
  }
  return [
    for (final video in videos)
      if (byVideo[video.id] case final rows?)
        _VersionGroupSnapshot(
          folderId: video.folderId,
          primaryPath: video.absolutePath,
          versions: rows,
        ),
  ];
}

String _operationBlockedMessage(LibraryOperationState state) {
  if (state.isCleaning) {
    return 'Library maintenance in progress';
  }
  if (state.isVersioning) {
    return 'Updating video versions';
  }
  if (state.isScanning) {
    return 'Scan already in progress';
  }
  return 'Move in progress';
}
