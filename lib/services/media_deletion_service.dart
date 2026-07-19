import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/providers.dart';
import 'library_access_service.dart';

enum MediaDeletionStatus {
  deleted,
  notFound,
  needsRepair,
  filesystemFailure,
  catalogFailure,
}

class MediaDeletionResult {
  const MediaDeletionResult({
    required this.videoId,
    required this.status,
    required this.userMessage,
  });

  final int videoId;
  final MediaDeletionStatus status;
  final String userMessage;

  bool get isDeleted => status == MediaDeletionStatus.deleted;
}

class MediaDeletionBatchResult {
  const MediaDeletionBatchResult(this.results);

  final List<MediaDeletionResult> results;

  List<int> get deletedVideoIds => results
      .where((result) => result.isDeleted)
      .map((result) => result.videoId)
      .toList(growable: false);

  String get userMessage {
    if (results.isEmpty) {
      return 'No videos were selected for deletion.';
    }

    final deletedCount = deletedVideoIds.length;
    if (deletedCount == results.length) {
      return 'Deleted ${_videoCountText(deletedCount)}.';
    }

    final firstFailure = results.firstWhere((result) => !result.isDeleted);
    if (deletedCount == 0) {
      return 'No videos were deleted. ${firstFailure.userMessage}';
    }

    return 'Deleted $deletedCount of ${results.length} videos. '
        '${results.length - deletedCount} not deleted. '
        '${firstFailure.userMessage}';
  }
}

String _videoCountText(int count) => count == 1 ? '1 video' : '$count videos';

abstract interface class MediaDeletionFileSystem {
  Future<void> deleteArtifacts({
    required String mediaPath,
    required String? thumbnailPath,
  });
}

class LocalMediaDeletionFileSystem implements MediaDeletionFileSystem {
  static const _subtitleExtensions = {'.vtt', '.srt'};

  @override
  Future<void> deleteArtifacts({
    required String mediaPath,
    required String? thumbnailPath,
  }) async {
    final mediaFile = File(mediaPath);
    final subtitleFiles = await _matchingSubtitleFiles(mediaFile);

    for (final subtitleFile in subtitleFiles) {
      await _deleteIfPresent(subtitleFile);
    }

    if (thumbnailPath != null &&
        thumbnailPath.isNotEmpty &&
        p.normalize(thumbnailPath) != p.normalize(mediaPath)) {
      await _deleteIfPresent(File(thumbnailPath));
    }

    // Delete the media last so an optional-artifact failure leaves the main
    // file available for a safe retry.
    await _deleteIfPresent(mediaFile);
  }

  Future<List<File>> _matchingSubtitleFiles(File mediaFile) async {
    final directory = mediaFile.parent;
    if (!await directory.exists()) {
      return const [];
    }

    final mediaBasename = p.basenameWithoutExtension(mediaFile.path);
    final matchingFiles = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final extension = p.extension(entity.path).toLowerCase();
      if (!_subtitleExtensions.contains(extension)) {
        continue;
      }

      final subtitleBasename = p.basenameWithoutExtension(entity.path);
      if (subtitleBasename == mediaBasename ||
          subtitleBasename.startsWith('$mediaBasename.')) {
        matchingFiles.add(entity);
      }
    }
    return matchingFiles;
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class MediaDeletionService {
  const MediaDeletionService({
    required VideosDao videosDao,
    required FoldersDao foldersDao,
    required LibraryAccessService libraryAccessService,
    required MediaDeletionFileSystem fileSystem,
  }) : _videosDao = videosDao,
       _foldersDao = foldersDao,
       _libraryAccessService = libraryAccessService,
       _fileSystem = fileSystem;

  final VideosDao _videosDao;
  final FoldersDao _foldersDao;
  final LibraryAccessService _libraryAccessService;
  final MediaDeletionFileSystem _fileSystem;

  Future<MediaDeletionResult> deleteVideo(int videoId) => _deleteOne(videoId);

  Future<MediaDeletionBatchResult> deleteVideos(List<int> videoIds) async {
    final results = <MediaDeletionResult>[];
    for (final videoId in videoIds) {
      results.add(await _deleteOne(videoId));
    }
    return MediaDeletionBatchResult(List.unmodifiable(results));
  }

  Future<MediaDeletionResult> _deleteOne(int videoId) async {
    final Video? video;
    try {
      video = await _videosDao.getVideoById(videoId);
    } catch (error) {
      return _catalogFailure(videoId, 'video $videoId');
    }
    if (video == null) {
      return MediaDeletionResult(
        videoId: videoId,
        status: MediaDeletionStatus.notFound,
        userMessage: 'Video $videoId is no longer in the Library.',
      );
    }
    final resolvedVideo = video;

    final Folder? folder;
    try {
      folder = await _foldersDao.getFolderById(resolvedVideo.folderId);
    } catch (error) {
      return _catalogFailure(videoId, resolvedVideo.title);
    }
    if (folder == null) {
      return MediaDeletionResult(
        videoId: videoId,
        status: MediaDeletionStatus.needsRepair,
        userMessage:
            'Could not delete "${resolvedVideo.title}". Its Library is missing; '
            'remove the stale entry or rescan the Library.',
      );
    }

    MediaDeletionResult? completedResult;
    try {
      return await _libraryAccessService.withAccess(
        library: LibraryAccessRequest(
          path: folder.path,
          bookmark: folder.securityScopedBookmark,
        ),
        action: () async {
          final MediaDeletionResult result;
          try {
            await _fileSystem.deleteArtifacts(
              mediaPath: resolvedVideo.absolutePath,
              thumbnailPath: resolvedVideo.thumbnailPath,
            );
          } catch (error) {
            result = MediaDeletionResult(
              videoId: videoId,
              status: MediaDeletionStatus.filesystemFailure,
              userMessage:
                  'Could not delete "${resolvedVideo.title}" from disk. '
                  'Check that the files are writable and retry.',
            );
            completedResult = result;
            return result;
          }

          try {
            await _videosDao.deleteVideo(videoId);
          } catch (error) {
            result = _catalogFailure(videoId, resolvedVideo.title);
            completedResult = result;
            return result;
          }

          result = MediaDeletionResult(
            videoId: videoId,
            status: MediaDeletionStatus.deleted,
            userMessage: 'Deleted "${resolvedVideo.title}".',
          );
          completedResult = result;
          return result;
        },
      );
    } on LibraryAccessNeedsRepairException catch (error) {
      if (completedResult case final result?) {
        return result;
      }
      return MediaDeletionResult(
        videoId: videoId,
        status: MediaDeletionStatus.needsRepair,
        userMessage:
            'Could not delete "${resolvedVideo.title}". ${error.message}',
      );
    } catch (error) {
      if (completedResult case final result?) {
        return result;
      }
      return _catalogFailure(videoId, resolvedVideo.title);
    }
  }

  MediaDeletionResult _catalogFailure(int videoId, String title) {
    return MediaDeletionResult(
      videoId: videoId,
      status: MediaDeletionStatus.catalogFailure,
      userMessage:
          'Could not finish deleting "$title" from the Library. '
          'Its catalog record was kept; retry or rescan the Library.',
    );
  }
}

final mediaDeletionFileSystemProvider = Provider<MediaDeletionFileSystem>(
  (ref) => LocalMediaDeletionFileSystem(),
);

final mediaDeletionServiceProvider = Provider<MediaDeletionService>((ref) {
  return MediaDeletionService(
    videosDao: ref.watch(videosDaoProvider),
    foldersDao: ref.watch(foldersDaoProvider),
    libraryAccessService: ref.watch(libraryAccessServiceProvider),
    fileSystem: ref.watch(mediaDeletionFileSystemProvider),
  );
});
