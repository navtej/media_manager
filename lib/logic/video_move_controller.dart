import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/providers.dart';
import '../services/library_access_service.dart';
import 'catalog_controller.dart';
import 'library_operation_controller.dart';
import 'private_library_controller.dart';
import 'status_message_provider.dart';
import 'video_selection_controller.dart';

class VideoMoveState {
  const VideoMoveState({
    this.isMoving = false,
    this.completedCount = 0,
    this.totalCount = 0,
    this.statusMessage = '',
  });

  final bool isMoving;
  final int completedCount;
  final int totalCount;
  final String statusMessage;

  VideoMoveState copyWith({
    bool? isMoving,
    int? completedCount,
    int? totalCount,
    String? statusMessage,
  }) {
    return VideoMoveState(
      isMoving: isMoving ?? this.isMoving,
      completedCount: completedCount ?? this.completedCount,
      totalCount: totalCount ?? this.totalCount,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

class VideoMovePlanItem {
  const VideoMovePlanItem({
    required this.video,
    required this.sourceFolder,
    required this.destinationFolder,
    required this.sourcePath,
    required this.destinationPath,
    required this.relativePath,
    this.sidecars = const <VideoMoveSidecar>[],
    this.isNoOp = false,
  });

  final Video video;
  final Folder sourceFolder;
  final Folder destinationFolder;
  final String sourcePath;
  final String destinationPath;
  final String relativePath;
  final List<VideoMoveSidecar> sidecars;
  final bool isNoOp;

  VideoMovePlanItem copyWith({List<VideoMoveSidecar>? sidecars}) {
    return VideoMovePlanItem(
      video: video,
      sourceFolder: sourceFolder,
      destinationFolder: destinationFolder,
      sourcePath: sourcePath,
      destinationPath: destinationPath,
      relativePath: relativePath,
      sidecars: sidecars ?? this.sidecars,
      isNoOp: isNoOp,
    );
  }
}

class VideoMoveSidecar {
  const VideoMoveSidecar({
    required this.sourcePath,
    required this.destinationPath,
  });

  final String sourcePath;
  final String destinationPath;
}

class VideoMoveConflict {
  const VideoMoveConflict({
    required this.videoId,
    required this.destinationPath,
    required this.message,
  });

  final int videoId;
  final String destinationPath;
  final String message;
}

class VideoMovePreflight {
  const VideoMovePreflight({
    required this.items,
    this.conflicts = const <VideoMoveConflict>[],
    this.errors = const <String>[],
  });

  final List<VideoMovePlanItem> items;
  final List<VideoMoveConflict> conflicts;
  final List<String> errors;

  bool get canMove => conflicts.isEmpty && errors.isEmpty;
}

class VideoMoveItemResult {
  const VideoMoveItemResult({
    required this.videoId,
    required this.title,
    required this.sourcePath,
    required this.destinationPath,
    required this.message,
  });

  final int videoId;
  final String title;
  final String sourcePath;
  final String destinationPath;
  final String message;
}

class VideoMoveResult {
  const VideoMoveResult({
    this.moved = const <VideoMoveItemResult>[],
    this.skipped = const <VideoMoveItemResult>[],
    this.failures = const <VideoMoveItemResult>[],
  });

  final List<VideoMoveItemResult> moved;
  final List<VideoMoveItemResult> skipped;
  final List<VideoMoveItemResult> failures;

  int get movedCount => moved.length;
  int get skippedCount => skipped.length;
  int get failedCount => failures.length;
  bool get hasFailuresOrSkips => failures.isNotEmpty || skipped.isNotEmpty;
}

final class VideoSelectionSizeSummary {
  const VideoSelectionSizeSummary({
    required this.selectedCount,
    required this.knownBytes,
    required this.unknownCount,
  });

  factory VideoSelectionSizeSummary.fromSelection({
    required Iterable<int> selectedIds,
    required Iterable<Video> videos,
  }) {
    final uniqueIds = selectedIds.toSet();
    final videosById = {for (final video in videos) video.id: video};
    var knownBytes = 0;
    var unknownCount = 0;

    for (final id in uniqueIds) {
      final size = videosById[id]?.size;
      if (size == null || size <= 0) {
        unknownCount += 1;
      } else {
        knownBytes += size;
      }
    }

    return VideoSelectionSizeSummary(
      selectedCount: uniqueIds.length,
      knownBytes: knownBytes,
      unknownCount: unknownCount,
    );
  }

  final int selectedCount;
  final int knownBytes;
  final int unknownCount;

  String get label {
    final total = LibraryStats.formatSize(knownBytes);
    if (unknownCount == 0) {
      return '$selectedCount selected • $total';
    }
    final unknownLabel = unknownCount == 1 ? 'size unknown' : 'sizes unknown';
    return '$selectedCount selected • $total known • '
        '$unknownCount $unknownLabel';
  }
}

List<VideoMovePlanItem> buildVideoMovePlan({
  required List<Video> videos,
  required Map<int, Folder> foldersById,
  required Folder destinationFolder,
}) {
  return videos
      .map((video) {
        final sourceFolder = foldersById[video.folderId];
        if (sourceFolder == null) {
          throw StateError('Library folder is missing for ${video.title}.');
        }
        if (video.folderId == destinationFolder.id) {
          return VideoMovePlanItem(
            video: video,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            sourcePath: video.absolutePath,
            destinationPath: video.absolutePath,
            relativePath: p.basename(video.absolutePath),
            isNoOp: true,
          );
        }

        final relativePath = _relativeVideoPath(
          video.absolutePath,
          sourceFolder,
        );
        return VideoMovePlanItem(
          video: video,
          sourceFolder: sourceFolder,
          destinationFolder: destinationFolder,
          sourcePath: video.absolutePath,
          destinationPath: p.join(destinationFolder.path, relativePath),
          relativePath: relativePath,
        );
      })
      .toList(growable: false);
}

class VideoMoveController extends Notifier<VideoMoveState> {
  @override
  VideoMoveState build() => const VideoMoveState();

  Future<VideoSelectionSizeSummary> summarizeSelection(
    Iterable<int> videoIds,
  ) async {
    final uniqueIds = videoIds.toSet().toList()..sort();
    final videos = await ref.read(videosDaoProvider).getVideosByIds(uniqueIds);
    return VideoSelectionSizeSummary.fromSelection(
      selectedIds: uniqueIds,
      videos: videos,
    );
  }

  Future<VideoMovePreflight> preflightMove({
    required List<int> videoIds,
    required int destinationFolderId,
  }) async {
    final operationState = ref.read(libraryOperationControllerProvider);
    if (operationState.isScanning || operationState.isCleaning) {
      return VideoMovePreflight(
        items: [],
        errors: [
          operationState.isCleaning
              ? 'Cannot move videos while Library maintenance is in progress.'
              : 'Cannot move videos while a scan is in progress.',
        ],
      );
    }

    final folderDao = ref.read(foldersDaoProvider);
    final videoDao = ref.read(videosDaoProvider);
    final folders = await folderDao.getAllFolders();
    final foldersById = {for (final folder in folders) folder.id: folder};
    final destinationFolder = foldersById[destinationFolderId];
    if (destinationFolder == null) {
      return const VideoMovePreflight(
        items: [],
        errors: ['Destination library folder is missing.'],
      );
    }

    final selectedVideos = await videoDao.getVideosByIds(videoIds);
    final selectedById = {for (final video in selectedVideos) video.id: video};
    final orderedVideos = videoIds
        .map((id) => selectedById[id])
        .whereType<Video>()
        .toList(growable: false);

    final errors = <String>[];
    for (final missingId in videoIds.where(
      (id) => !selectedById.containsKey(id),
    )) {
      errors.add('Selected video $missingId no longer exists.');
    }

    late final List<VideoMovePlanItem> plannedItems;
    try {
      plannedItems = buildVideoMovePlan(
        videos: orderedVideos,
        foldersById: foldersById,
        destinationFolder: destinationFolder,
      );
    } catch (error) {
      return VideoMovePreflight(items: const [], errors: [error.toString()]);
    }

    var items = plannedItems;

    for (final item in items) {
      if (item.video.isOffline) {
        errors.add('${item.video.title} is offline.');
      }
      if (!_isWithinOrEqual(item.sourcePath, item.sourceFolder.path)) {
        errors.add('${item.video.title} is outside its managed source folder.');
      }
    }

    var conflicts = <VideoMoveConflict>[];
    try {
      await ref
          .read(libraryAccessServiceProvider)
          .withAccessToAll(
            libraries: _accessRequests(
              _preflightFolders(items, destinationFolder),
            ),
            action: () async {
              items = await _attachSubtitleSidecars(items, errors);
              conflicts = await _findConflicts(items, videoDao);
            },
          );
    } on FileSystemException catch (error) {
      errors.add(
        _fileSystemErrorMessage('Could not inspect move paths', error),
      );
    } catch (error) {
      errors.add(_plainErrorMessage(error));
    }

    return VideoMovePreflight(
      items: items,
      conflicts: conflicts,
      errors: errors,
    );
  }

  Future<VideoMoveResult?> moveVideos({
    required List<int> videoIds,
    required int destinationFolderId,
    bool removeEmptySourceFolders = false,
  }) {
    return ref
        .read(privateLibraryAccessControllerProvider.notifier)
        .runVideoAction<VideoMoveResult>(
          videoIds: videoIds,
          libraryIds: [destinationFolderId],
          action: () => _moveVideos(
            videoIds: videoIds,
            destinationFolderId: destinationFolderId,
            removeEmptySourceFolders: removeEmptySourceFolders,
          ),
        );
  }

  Future<VideoMoveResult> _moveVideos({
    required List<int> videoIds,
    required int destinationFolderId,
    required bool removeEmptySourceFolders,
  }) async {
    final operation = ref.read(libraryOperationControllerProvider.notifier);
    final operationState = ref.read(libraryOperationControllerProvider);
    if (!operation.beginMove()) {
      final message = operationState.isScanning
          ? 'Cannot move videos while a scan is in progress.'
          : operationState.isCleaning
          ? 'Cannot move videos while Library maintenance is in progress.'
          : 'Another move is already in progress.';
      return VideoMoveResult(
        failures: [
          VideoMoveItemResult(
            videoId: -1,
            title: 'Move blocked',
            sourcePath: '',
            destinationPath: '',
            message: message,
          ),
        ],
      );
    }

    state = VideoMoveState(
      isMoving: true,
      totalCount: videoIds.length,
      statusMessage: 'Preparing move...',
    );

    try {
      final preflight = await preflightMove(
        videoIds: videoIds,
        destinationFolderId: destinationFolderId,
      );
      if (!preflight.canMove) {
        final failures = <VideoMoveItemResult>[
          ...preflight.errors.map(
            (message) => VideoMoveItemResult(
              videoId: -1,
              title: 'Move blocked',
              sourcePath: '',
              destinationPath: '',
              message: message,
            ),
          ),
          ...preflight.conflicts.map(
            (conflict) => VideoMoveItemResult(
              videoId: conflict.videoId,
              title: 'Conflict',
              sourcePath: '',
              destinationPath: conflict.destinationPath,
              message: conflict.message,
            ),
          ),
        ];
        return VideoMoveResult(failures: failures);
      }

      return await ref
          .read(libraryAccessServiceProvider)
          .withAccessToAll(
            libraries: _accessRequestsForMove(preflight.items),
            action: () async {
              final moved = <VideoMoveItemResult>[];
              final skipped = <VideoMoveItemResult>[];
              final failures = <VideoMoveItemResult>[];
              final clearFromSelection = <int>[];

              for (final item in preflight.items) {
                if (item.isNoOp) {
                  skipped.add(
                    VideoMoveItemResult(
                      videoId: item.video.id,
                      title: item.video.title,
                      sourcePath: item.sourcePath,
                      destinationPath: item.destinationPath,
                      message: 'Already in destination folder.',
                    ),
                  );
                  clearFromSelection.add(item.video.id);
                  _markProgress(
                    moved.length + skipped.length + failures.length,
                  );
                  continue;
                }

                try {
                  state = state.copyWith(
                    statusMessage: 'Moving ${item.video.title}...',
                  );
                  await _moveFile(
                    sourcePath: item.sourcePath,
                    destinationPath: item.destinationPath,
                  );
                  final sidecarFailures = <String>[];
                  for (final sidecar in item.sidecars) {
                    try {
                      await _moveFile(
                        sourcePath: sidecar.sourcePath,
                        destinationPath: sidecar.destinationPath,
                      );
                    } catch (error) {
                      sidecarFailures.add(
                        '${p.basename(sidecar.sourcePath)}: $error',
                      );
                    }
                  }

                  await ref
                      .read(videosDaoProvider)
                      .updateVideoLocation(
                        id: item.video.id,
                        folderId: item.destinationFolder.id,
                        absolutePath: item.destinationPath,
                      );

                  if (removeEmptySourceFolders) {
                    await _removeEmptyParents(
                      Directory(p.dirname(item.sourcePath)),
                      Directory(item.sourceFolder.path),
                    );
                  }

                  moved.add(
                    VideoMoveItemResult(
                      videoId: item.video.id,
                      title: item.video.title,
                      sourcePath: item.sourcePath,
                      destinationPath: item.destinationPath,
                      message: sidecarFailures.isEmpty
                          ? 'Moved.'
                          : 'Moved video, but some sidecars failed: ${sidecarFailures.join('; ')}',
                    ),
                  );
                  clearFromSelection.add(item.video.id);
                } catch (error) {
                  failures.add(
                    VideoMoveItemResult(
                      videoId: item.video.id,
                      title: item.video.title,
                      sourcePath: item.sourcePath,
                      destinationPath: item.destinationPath,
                      message: error.toString(),
                    ),
                  );
                } finally {
                  _markProgress(
                    moved.length + skipped.length + failures.length,
                  );
                }
              }

              ref
                  .read(videoSelectionControllerProvider.notifier)
                  .removeIds(clearFromSelection);
              final result = VideoMoveResult(
                moved: moved,
                skipped: skipped,
                failures: failures,
              );
              ref
                  .read(statusMessageProvider.notifier)
                  .set(
                    _completionMessage(result),
                    duration: const Duration(seconds: 5),
                  );
              return result;
            },
          );
    } finally {
      operation.endMove();
      state = const VideoMoveState();
    }
  }

  void _markProgress(int completed) {
    state = state.copyWith(
      completedCount: completed,
      statusMessage: 'Moving videos: $completed/${state.totalCount}',
    );
  }

  String _completionMessage(VideoMoveResult result) {
    final parts = <String>[];
    if (result.movedCount > 0) parts.add('${result.movedCount} moved');
    if (result.skippedCount > 0) parts.add('${result.skippedCount} skipped');
    if (result.failedCount > 0) parts.add('${result.failedCount} failed');
    return parts.isEmpty
        ? 'No videos moved'
        : 'Move complete: ${parts.join(', ')}';
  }

  Iterable<Folder> _preflightFolders(
    List<VideoMovePlanItem> items,
    Folder destinationFolder,
  ) {
    final folders = <int, Folder>{destinationFolder.id: destinationFolder};
    for (final item in items.where((item) => !item.isNoOp)) {
      folders[item.sourceFolder.id] = item.sourceFolder;
    }
    return folders.values;
  }

  Future<List<VideoMovePlanItem>> _attachSubtitleSidecars(
    List<VideoMovePlanItem> items,
    List<String> errors,
  ) async {
    final updatedItems = <VideoMovePlanItem>[];
    for (final item in items) {
      if (item.isNoOp) {
        updatedItems.add(item);
        continue;
      }
      try {
        final sidecars = await _findSubtitleSidecars(item);
        updatedItems.add(item.copyWith(sidecars: sidecars));
      } on FileSystemException catch (error) {
        errors.add(
          _fileSystemErrorMessage(
            'Could not inspect subtitles for ${item.video.title}',
            error,
          ),
        );
        updatedItems.add(item);
      } catch (error) {
        errors.add(
          'Could not inspect subtitles for ${item.video.title}: '
          '${_plainErrorMessage(error)}',
        );
        updatedItems.add(item);
      }
    }
    return updatedItems;
  }

  Iterable<LibraryAccessRequest> _accessRequestsForMove(
    List<VideoMovePlanItem> items,
  ) {
    final folders = <int, Folder>{};
    for (final item in items.where((item) => !item.isNoOp)) {
      folders[item.sourceFolder.id] = item.sourceFolder;
      folders[item.destinationFolder.id] = item.destinationFolder;
    }
    return _accessRequests(folders.values);
  }

  Iterable<LibraryAccessRequest> _accessRequests(Iterable<Folder> folders) {
    return folders.map(
      (folder) => LibraryAccessRequest(
        path: folder.path,
        bookmark: folder.securityScopedBookmark,
      ),
    );
  }

  Future<List<VideoMoveConflict>> _findConflicts(
    List<VideoMovePlanItem> items,
    VideosDao videoDao,
  ) async {
    final conflicts = <VideoMoveConflict>[];
    final plannedDestinations = <String, int>{};

    for (final item in items.where((item) => !item.isNoOp)) {
      final destinations = <String>[
        item.destinationPath,
        ...item.sidecars.map((s) => s.destinationPath),
      ];
      for (final destinationPath in destinations) {
        final previousVideoId = plannedDestinations[destinationPath];
        if (previousVideoId != null) {
          conflicts.add(
            VideoMoveConflict(
              videoId: item.video.id,
              destinationPath: destinationPath,
              message:
                  'Destination collides with another selected video ($previousVideoId).',
            ),
          );
          continue;
        }
        plannedDestinations[destinationPath] = item.video.id;

        if (await File(destinationPath).exists()) {
          conflicts.add(
            VideoMoveConflict(
              videoId: item.video.id,
              destinationPath: destinationPath,
              message: 'Destination already exists.',
            ),
          );
          continue;
        }

        if (destinationPath == item.destinationPath) {
          final existing = await videoDao.getVideoByPath(destinationPath);
          if (existing != null && existing.id != item.video.id) {
            conflicts.add(
              VideoMoveConflict(
                videoId: item.video.id,
                destinationPath: destinationPath,
                message: 'Destination is already indexed in the library.',
              ),
            );
          }
        }
      }
    }
    return conflicts;
  }
}

final videoMoveControllerProvider =
    NotifierProvider<VideoMoveController, VideoMoveState>(
      VideoMoveController.new,
    );

String _relativeVideoPath(String absolutePath, Folder sourceFolder) {
  if (!_isWithinOrEqual(absolutePath, sourceFolder.path)) {
    return p.basename(absolutePath);
  }
  return p.relative(absolutePath, from: sourceFolder.path);
}

bool _isWithinOrEqual(String childPath, String parentPath) {
  final child = p.normalize(childPath);
  final parent = p.normalize(parentPath);
  return child == parent || p.isWithin(parent, child);
}

String _plainErrorMessage(Object error) {
  if (error is StateError) {
    return error.message;
  }
  if (error is FileSystemException) {
    return _fileSystemErrorMessage('File system error', error);
  }
  return error.toString();
}

String _fileSystemErrorMessage(String prefix, FileSystemException error) {
  final parts = <String>[prefix];
  if (error.message.isNotEmpty) {
    parts.add(error.message);
  }
  final path = error.path;
  if (path != null && path.isNotEmpty) {
    parts.add(path);
  }
  final osError = error.osError;
  if (osError != null) {
    parts.add(osError.message);
  }
  return parts.join(': ');
}

Future<List<VideoMoveSidecar>> _findSubtitleSidecars(
  VideoMovePlanItem item,
) async {
  final sourceFile = File(item.sourcePath);
  final sourceDir = sourceFile.parent;
  if (!await sourceDir.exists()) {
    return const [];
  }

  final basename = p.basenameWithoutExtension(item.sourcePath);
  const extensions = {'.vtt', '.srt', '.VTT', '.SRT'};
  final sidecars = <VideoMoveSidecar>[];
  await for (final entity in sourceDir.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final entityName = p.basename(entity.path);
    if (!entityName.startsWith(basename) ||
        !extensions.contains(p.extension(entity.path))) {
      continue;
    }
    sidecars.add(
      VideoMoveSidecar(
        sourcePath: entity.path,
        destinationPath: p.join(p.dirname(item.destinationPath), entityName),
      ),
    );
  }
  return sidecars;
}

Future<void> _moveFile({
  required String sourcePath,
  required String destinationPath,
}) async {
  final source = File(sourcePath);
  final destination = File(destinationPath);
  final stat = await source.stat();
  if (stat.type == FileSystemEntityType.notFound) {
    throw FileSystemException('Source file does not exist.', sourcePath);
  }

  await destination.parent.create(recursive: true);
  try {
    await source.rename(destinationPath);
  } on FileSystemException {
    await source.copy(destinationPath);
    await destination.setLastModified(stat.modified);
    await source.delete();
  }
}

Future<void> _removeEmptyParents(Directory start, Directory stopAt) async {
  var current = Directory(p.normalize(start.path));
  final stopPath = p.normalize(stopAt.path);

  while (p.normalize(current.path) != stopPath &&
      _isWithinOrEqual(current.path, stopPath)) {
    if (!await current.exists()) {
      current = current.parent;
      continue;
    }
    final hasChildren = !await current.list(followLinks: false).isEmpty;
    if (hasChildren) {
      return;
    }
    await current.delete();
    current = current.parent;
  }
}
