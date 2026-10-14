import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/providers.dart';
import '../logic/library_operation_controller.dart';
import '../logic/video_version_models.dart';
import 'library_access_service.dart';
import 'media_service.dart';

/// Runs an action while no scan, move or cleanup can touch the Library.
typedef LibraryExclusiveRunner =
    Future<T> Function<T>(Future<T> Function() action);

Future<T> _runDirectly<T>(Future<T> Function() action) => action();

/// The catalog view of a `video_versions` row of a video whose primary file
/// is [primaryPath].
VideoVersionInfo videoVersionInfoFromRow(
  VideoVersion row, {
  required String primaryPath,
}) {
  final metadata = decodeVideoMetadataJson(row.metadataJson);
  final width = row.width;
  final height = row.height;
  final dimensions = width != null && height != null && width > 0 && height > 0
      ? VideoDimensions(width, height)
      : metadata == null
      ? null
      : videoDimensionsFromMetadata(metadata);
  return VideoVersionInfo(
    id: row.id,
    videoId: row.videoId,
    path: row.absolutePath,
    dimensions: dimensions,
    durationSeconds: row.duration,
    sizeBytes: row.size,
    isOriginal: row.isOriginal,
    isPrimary: row.absolutePath == primaryPath,
    videoCodec: metadata == null ? null : videoCodecFromMetadata(metadata),
    createdAt: row.createdAt,
  );
}

/// Every version of [video] given its `video_versions` [rows], primary
/// first, then by quality class (descending, unknown last), then newest
/// first. A missing primary row is synthesized from the `videos` row.
List<VideoVersionInfo> buildVideoVersionList(
  Video video,
  List<VideoVersion> rows,
) {
  final versions = [
    for (final row in rows.where((row) => row.videoId == video.id))
      videoVersionInfoFromRow(row, primaryPath: video.absolutePath),
  ];
  if (!versions.any((version) => version.isPrimary)) {
    final metadata = decodeVideoMetadataJson(video.metadataJson);
    versions.add(
      VideoVersionInfo(
        id: null,
        videoId: video.id,
        path: video.absolutePath,
        dimensions: metadata == null
            ? null
            : videoDimensionsFromMetadata(metadata),
        durationSeconds: video.duration,
        sizeBytes: video.size,
        isOriginal: !versions.any((version) => version.isOriginal),
        isPrimary: true,
        videoCodec: metadata == null ? null : videoCodecFromMetadata(metadata),
        createdAt: video.addedAt,
      ),
    );
  }
  versions.sort(_compareForListing);
  return versions;
}

/// Order in which versions are considered when the primary must be replaced:
/// the original first, then the highest quality class, then the newest.
int compareVideoVersionsForPromotion(VideoVersionInfo a, VideoVersionInfo b) {
  if (a.isOriginal != b.isOriginal) return a.isOriginal ? -1 : 1;
  final quality = _qualityRank(b).compareTo(_qualityRank(a));
  if (quality != 0) return quality;
  return _compareNewestFirst(a, b);
}

int _compareForListing(VideoVersionInfo a, VideoVersionInfo b) {
  if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
  final quality = _qualityRank(b).compareTo(_qualityRank(a));
  if (quality != 0) return quality;
  return _compareNewestFirst(a, b);
}

int _compareForSource(VideoVersionInfo a, VideoVersionInfo b) {
  final quality = _qualityRank(b).compareTo(_qualityRank(a));
  if (quality != 0) return quality;
  if (a.isOriginal != b.isOriginal) return a.isOriginal ? -1 : 1;
  if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
  return _compareNewestFirst(a, b);
}

int _qualityRank(VideoVersionInfo version) =>
    version.dimensions?.qualityClass ?? -1;

int _compareNewestFirst(VideoVersionInfo a, VideoVersionInfo b) {
  final created = (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
    a.createdAt?.millisecondsSinceEpoch ?? 0,
  );
  if (created != 0) return created;
  return (b.id ?? 0).compareTo(a.id ?? 0);
}

final _versionSuffix = RegExp(r'^(.+?) \[\d+p\](?: \(\d+\))?$');

/// File stem of [path] without a " [720p]" / " [720p] (2)" version suffix.
String videoVersionBaseStem(String path) {
  final stem = p.basenameWithoutExtension(path);
  final match = _versionSuffix.firstMatch(stem);
  return match?.group(1) ?? stem;
}

/// Catalog and file operations for the versions (converted copies) of a video.
///
/// [finalizeConversion], [deleteVersions] and [setPrimaryVersion] change files
/// and catalog paths, so they run through [runExclusive] (by default the
/// Library's versioning operation) and never interleave with a scan, move or
/// cleanup.
class VideoVersionService {
  VideoVersionService({
    required AppDatabase database,
    required LibraryAccessService libraryAccessService,
    required MediaService mediaService,
    LibraryExclusiveRunner? runExclusive,
  }) : _db = database,
       _libraryAccess = libraryAccessService,
       _mediaService = mediaService,
       _runExclusive = runExclusive ?? _runDirectly;

  final AppDatabase _db;
  final LibraryAccessService _libraryAccess;
  final MediaService _mediaService;
  final LibraryExclusiveRunner _runExclusive;

  VideosDao get _videosDao => _db.videosDao;
  VideoVersionsDao get _versionsDao => _db.videoVersionsDao;

  /// All versions of [videoId], primary first, then by quality class
  /// (descending), then newest first. An unconverted video yields its single
  /// implicit primary version. Empty when the video no longer exists.
  Future<List<VideoVersionInfo>> listVersions(int videoId) async {
    final video = await _videosDao.getVideoById(videoId);
    if (video == null) return const [];
    final rows = await _versionsDao.getVersionsForVideo(videoId);
    return buildVideoVersionList(video, rows);
  }

  /// [listVersions], re-emitted whenever the `videos` or `video_versions`
  /// table changes.
  Stream<List<VideoVersionInfo>> watchVersions(int videoId) {
    return _db
        .customSelect(
          'SELECT (SELECT count(*) FROM videos WHERE id = ?1) AS v, '
          '(SELECT count(*) FROM video_versions WHERE video_id = ?1) AS n',
          variables: [Variable.withInt(videoId)],
          readsFrom: {_db.videos, _db.videoVersions},
        )
        .watch()
        .asyncMap((_) => listVersions(videoId));
  }

  /// Chooses the source version (highest resolution; ties prefer the
  /// original, then the primary) and the output paths for converting
  /// [videoId] to [preset].
  ///
  /// Throws [VideoVersionException] with a user-facing message when the
  /// video, its library or its source file is unavailable, or when the
  /// source is already at or below [preset].
  Future<VideoConversionPlan> planConversion({
    required int videoId,
    required VideoResolutionPreset preset,
    required bool keepSource,
  }) async {
    final video = await _requireVideo(videoId);
    if (video.isOffline) {
      throw VideoVersionException(
        '"${video.title}" is offline. Reconnect its drive and try again.',
      );
    }
    final access = await _requireLibrary(video);
    return _withAccess(access, video.title, () async {
      final rows = await _versionsDao.getVersionsForVideo(video.id);
      final versions = buildVideoVersionList(video, rows)
        ..sort(_compareForSource);
      final source = versions.first;
      if (await _statFile(source.path) == null) {
        throw VideoVersionException(
          'The file "${source.fileName}" of "${video.title}" is missing. '
          'Rescan the Library and try again.',
        );
      }
      final dimensions = source.dimensions;
      if (dimensions != null && dimensions.qualityClass <= preset.shortSide) {
        throw VideoVersionException(
          '"${video.title}" is already ${preset.label} or lower.',
        );
      }

      final outputPath = await _chooseOutputPath(
        source: source,
        preset: preset,
        keepSource: keepSource,
      );
      return VideoConversionPlan(
        videoId: video.id,
        videoTitle: video.title,
        folderId: video.folderId,
        libraryAccess: access,
        source: source,
        preset: preset,
        keepSource: keepSource,
        outputPath: outputPath,
        temporaryPath: '$outputPath.part',
      );
    });
  }

  /// Verifies the transcoder output at [VideoConversionPlan.temporaryPath],
  /// moves it to [VideoConversionPlan.outputPath] and registers it. When
  /// [VideoConversionPlan.keepSource] is false the new file becomes primary
  /// and the source file is deleted.
  ///
  /// The output may land on a different free name than
  /// [VideoConversionPlan.outputPath] if that path was taken meanwhile; the
  /// returned [VideoConversionOutcome.version] has the final path.
  ///
  /// Throws [VideoVersionException] (output discarded, catalog and source
  /// untouched) when verification fails or the video changed meanwhile.
  Future<VideoConversionOutcome> finalizeConversion(
    VideoConversionPlan plan, {
    required double expectedDurationSeconds,
  }) {
    return _runExclusive(
      () => _withAccess(
        plan.libraryAccess,
        plan.videoTitle,
        () => _finalize(plan, expectedDurationSeconds),
      ),
    );
  }

  /// Deletes the temporary transcoder output of [plan] if present.
  Future<void> discardTemporaryOutput(VideoConversionPlan plan) async {
    try {
      await _libraryAccess.withAccess(
        library: plan.libraryAccess,
        action: () => _deleteQuietly(plan.temporaryPath),
      );
    } on LibraryAccessNeedsRepairException catch (error) {
      debugPrint('Could not discard ${plan.temporaryPath}: ${error.message}');
    }
  }

  /// Deletes the given version files of [videoId] from disk and catalog. If
  /// the primary is among them another version is promoted. Refuses (throws
  /// [VideoVersionException]) to delete every version of a video.
  Future<VideoVersionDeletionResult> deleteVersions({
    required int videoId,
    required Iterable<String> paths,
  }) {
    final requested = paths.toSet();
    return _runExclusive(() async {
      final video = await _requireVideo(videoId);
      final access = await _requireLibrary(video);
      return _withAccess(
        access,
        video.title,
        () => _deleteVersions(video, requested),
      );
    });
  }

  /// Makes the version at [path] the primary file of [videoId].
  Future<void> setPrimaryVersion({required int videoId, required String path}) {
    return _runExclusive(() async {
      final video = await _requireVideo(videoId);
      final access = await _requireLibrary(video);
      await _withAccess(access, video.title, () async {
        final rows = await _versionsDao.getVersionsForVideo(video.id);
        final versions = buildVideoVersionList(video, rows);
        final target = versions.where((v) => v.path == path).firstOrNull;
        if (target == null) {
          throw VideoVersionException(
            '"${p.basename(path)}" is not a version of "${video.title}".',
          );
        }
        if (target.isPrimary) return;
        final targetStat = await _statFile(path);
        if (targetStat == null) {
          throw VideoVersionException(
            'The file "${target.fileName}" is missing. Rescan the Library '
            'and try again.',
          );
        }
        final row = rows.firstWhere((row) => row.absolutePath == path);
        final oldStat = await _statFile(video.absolutePath);
        await _db.transaction(() async {
          await _ensurePrimaryRow(video, rows);
          await _switchPrimary(
            video: video,
            path: path,
            size: targetStat.size,
            duration: row.duration,
            metadataJson: row.metadataJson,
            oldStat: oldStat,
            newStat: targetStat,
          );
        });
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Finalize

  Future<VideoConversionOutcome> _finalize(
    VideoConversionPlan plan,
    double expectedDurationSeconds,
  ) async {
    final title = plan.videoTitle;
    final changedMessage =
        '"$title" was moved, deleted, or changed during conversion; '
        'the converted file was discarded.';

    final video = await _videosDao.getVideoById(plan.videoId);
    if (video == null || video.folderId != plan.folderId) {
      throw await _discard(plan, changedMessage);
    }
    final rows = await _versionsDao.getVersionsForVideo(video.id);
    final sourcePath = plan.source.path;
    final sourceIsPrimary = video.absolutePath == sourcePath;
    if (!sourceIsPrimary && !rows.any((r) => r.absolutePath == sourcePath)) {
      throw await _discard(plan, changedMessage);
    }
    final sourceStat = await _statFile(sourcePath);
    if (sourceStat == null) {
      throw await _discard(plan, changedMessage);
    }

    final temporaryStat = await _statFile(plan.temporaryPath);
    if (temporaryStat == null || temporaryStat.size <= 0) {
      throw await _discard(
        plan,
        'The converted file for "$title" is missing or empty; '
        'it was discarded.',
      );
    }

    final metadata = await _probe(plan.temporaryPath);
    final dimensions = videoDimensionsFromMetadata(metadata);
    if (dimensions == null) {
      throw await _discard(
        plan,
        'The converted file for "$title" has no readable video stream; '
        'it was discarded.',
      );
    }
    if (dimensions.qualityClass > plan.preset.shortSide) {
      throw await _discard(
        plan,
        'The converted file for "$title" is ${dimensions.qualityLabel}, not '
        '${plan.preset.label} or lower; it was discarded.',
      );
    }
    final durationSeconds = videoDurationFromMetadata(metadata);
    if (expectedDurationSeconds > 0) {
      final tolerance = expectedDurationSeconds * 0.02 > 2.0
          ? expectedDurationSeconds * 0.02
          : 2.0;
      if (durationSeconds == null ||
          (durationSeconds - expectedDurationSeconds).abs() > tolerance) {
        final actual = durationSeconds == null
            ? 'of unknown length'
            : '${durationSeconds.toStringAsFixed(1)} s long';
        throw await _discard(
          plan,
          'The converted file for "$title" is $actual but the source is '
          '${expectedDurationSeconds.toStringAsFixed(1)} s; '
          'it was discarded.',
        );
      }
    }

    final output = _ConvertedOutput(
      dimensions: dimensions,
      duration: (durationSeconds ?? 0).round(),
      metadataJson: jsonEncode(metadata),
    );

    final inPlace = !plan.keepSource && plan.outputPath == sourcePath;
    if (inPlace) {
      return _finalizeInPlace(
        plan: plan,
        video: video,
        rows: rows,
        sourceStat: sourceStat,
        output: output,
      );
    }

    var outputPath = plan.outputPath;
    if (await _isTaken(outputPath, ownTemporaryPath: plan.temporaryPath)) {
      outputPath = await _nextFreeVersionPath(
        sourcePath,
        plan.preset,
        ownTemporaryPath: plan.temporaryPath,
      );
    }

    // Register before the file appears at its final name so nothing can
    // import it as a new video.
    int? insertedPrimaryId;
    late final int newId;
    try {
      await _db.transaction(() async {
        insertedPrimaryId = await _ensurePrimaryRow(video, rows);
        newId = await _versionsDao.insertVersion(
          output.companion(
            videoId: video.id,
            path: outputPath,
            size: temporaryStat.size,
          ),
        );
      });
    } catch (error) {
      debugPrint('Could not register converted version $outputPath: $error');
      throw await _discard(plan, changedMessage);
    }

    try {
      if (await _exists(outputPath)) {
        throw FileSystemException('Destination already exists', outputPath);
      }
      await File(plan.temporaryPath).rename(outputPath);
    } on FileSystemException catch (error) {
      await _db.transaction(() async {
        await _versionsDao.deleteVersionById(newId);
        if (insertedPrimaryId case final id?) {
          await _versionsDao.deleteVersionById(id);
        }
      });
      throw await _discard(
        plan,
        'Could not save the converted file for "$title" '
        '(${_describe(error)}); it was discarded.',
      );
    }
    final outputStat = await _statFile(outputPath) ?? temporaryStat;

    if (plan.keepSource) {
      return VideoConversionOutcome(
        version: await _versionInfo(video.id, outputPath),
        replacedSource: false,
      );
    }

    final warnings = <String>[];
    final oldPrimaryStat = sourceIsPrimary
        ? sourceStat
        : await _statFile(video.absolutePath);
    try {
      await _db.transaction(
        () => _switchPrimary(
          video: video,
          path: outputPath,
          size: outputStat.size,
          duration: output.duration,
          metadataJson: output.metadataJson,
          oldStat: oldPrimaryStat,
          newStat: outputStat,
        ),
      );
    } catch (error) {
      debugPrint('Could not make $outputPath primary: $error');
      warnings.add(
        'The converted file was kept as an extra version because the '
        'Library could not be updated; the source was not deleted.',
      );
      return VideoConversionOutcome(
        version: await _versionInfo(video.id, outputPath),
        replacedSource: false,
        warnings: warnings,
      );
    }

    // The source stays registered (now non-primary) until its file is gone,
    // so a scan can never import it as a new video.
    var sourceDeleted = false;
    try {
      await File(sourcePath).delete();
      sourceDeleted = true;
    } on FileSystemException catch (error) {
      if (!await _exists(sourcePath)) {
        sourceDeleted = true;
      } else {
        warnings.add(
          'Could not delete "${p.basename(sourcePath)}" '
          '(${_describe(error)}); it was kept as an extra version.',
        );
      }
    }
    if (sourceDeleted) {
      try {
        await _deleteRowForPath(video.id, sourcePath);
      } catch (error) {
        debugPrint('Could not remove version row for $sourcePath: $error');
      }
    }

    return VideoConversionOutcome(
      version: await _versionInfo(video.id, outputPath),
      replacedSource: sourceDeleted,
      warnings: warnings,
    );
  }

  Future<VideoConversionOutcome> _finalizeInPlace({
    required VideoConversionPlan plan,
    required Video video,
    required List<VideoVersion> rows,
    required FileStat sourceStat,
    required _ConvertedOutput output,
  }) async {
    final sourcePath = plan.source.path;
    final sourceIsPrimary = video.absolutePath == sourcePath;
    final oldPrimaryStat = sourceIsPrimary
        ? sourceStat
        : await _statFile(video.absolutePath);

    try {
      // Same directory, so this atomically replaces the source.
      await File(plan.temporaryPath).rename(sourcePath);
    } on FileSystemException catch (error) {
      throw await _discard(
        plan,
        'Could not replace "${p.basename(sourcePath)}" with the converted '
        'file (${_describe(error)}); it was discarded.',
      );
    }
    final newStat = await _statFile(sourcePath);
    if (newStat == null) {
      throw VideoVersionException(
        'The converted file for "${plan.videoTitle}" disappeared after it '
        'was saved. Rescan the Library.',
      );
    }

    try {
      await _db.transaction(() async {
        final sourceRow = rows
            .where((row) => row.absolutePath == sourcePath)
            .firstOrNull;
        final companion = output.companion(
          videoId: video.id,
          path: sourcePath,
          size: newStat.size,
        );
        if (sourceRow == null) {
          await _versionsDao.insertVersion(companion);
        } else {
          await (_db.update(_db.videoVersions)
                ..where((t) => t.id.equals(sourceRow.id)))
              .write(companion.copyWith(createdAt: Value(DateTime.now())));
        }
        if (!sourceIsPrimary) {
          await _ensurePrimaryRow(video, rows);
        }
        await _switchPrimary(
          video: video,
          path: sourcePath,
          size: newStat.size,
          duration: output.duration,
          metadataJson: output.metadataJson,
          oldStat: oldPrimaryStat,
          newStat: newStat,
        );
      });
    } catch (error) {
      debugPrint('Could not update catalog for $sourcePath: $error');
      throw VideoVersionException(
        'The converted file replaced "${p.basename(sourcePath)}", but the '
        'Library could not be updated. Rescan the Library.',
      );
    }

    return VideoConversionOutcome(
      version: await _versionInfo(video.id, sourcePath),
      replacedSource: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Delete

  Future<VideoVersionDeletionResult> _deleteVersions(
    Video video,
    Set<String> requested,
  ) async {
    final rows = await _versionsDao.getVersionsForVideo(video.id);
    final versions = buildVideoVersionList(video, rows);
    final byPath = {for (final version in versions) version.path: version};
    final failures = <String, String>{};
    final targets = <VideoVersionInfo>[];
    for (final path in requested) {
      final version = byPath[path];
      if (version == null) {
        failures[path] =
            '"${p.basename(path)}" is not a version of "${video.title}".';
      } else {
        targets.add(version);
      }
    }
    if (targets.isEmpty) {
      return VideoVersionDeletionResult(
        deletedPaths: const [],
        failures: failures,
      );
    }
    if (targets.length == versions.length) {
      throw const VideoVersionException(
        'Keep at least one version. To remove the video entirely, delete the '
        'video.',
      );
    }

    String? newPrimaryPath;
    final primaryTarget = targets.where((v) => v.isPrimary).firstOrNull;
    if (primaryTarget != null) {
      final targetPaths = targets.map((v) => v.path).toSet();
      final candidates =
          versions.where((v) => !targetPaths.contains(v.path)).toList()
            ..sort(compareVideoVersionsForPromotion);
      VideoVersionInfo? replacement;
      FileStat? replacementStat;
      for (final candidate in candidates) {
        final stat = await _statFile(candidate.path);
        if (stat != null) {
          replacement = candidate;
          replacementStat = stat;
          break;
        }
      }
      if (replacement == null || replacementStat == null) {
        failures[primaryTarget.path] =
            'No other version of "${video.title}" is available to become the '
            'primary version.';
        targets.remove(primaryTarget);
      } else {
        final promoted = replacement;
        final promotedStat = replacementStat;
        final row = rows.firstWhere((r) => r.absolutePath == promoted.path);
        final oldStat = await _statFile(video.absolutePath);
        await _db.transaction(() async {
          await _ensurePrimaryRow(video, rows);
          await _switchPrimary(
            video: video,
            path: promoted.path,
            size: promotedStat.size,
            duration: row.duration,
            metadataJson: row.metadataJson,
            oldStat: oldStat,
            newStat: promotedStat,
          );
        });
        newPrimaryPath = promoted.path;
      }
    }

    final deleted = <String>[];
    for (final target in targets) {
      try {
        final file = File(target.path);
        if (await file.exists()) {
          await file.delete();
        }
        deleted.add(target.path);
      } on FileSystemException catch (error) {
        failures[target.path] =
            'Could not delete "${target.fileName}" (${_describe(error)}).';
      }
    }
    if (deleted.isNotEmpty) {
      await _db.transaction(() async {
        for (final path in deleted) {
          await _deleteRowForPath(video.id, path);
        }
      });
    }

    return VideoVersionDeletionResult(
      deletedPaths: deleted,
      failures: failures,
      newPrimaryPath: newPrimaryPath,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers

  Future<Video> _requireVideo(int videoId) async {
    final video = await _videosDao.getVideoById(videoId);
    if (video == null) {
      throw const VideoVersionException(
        'This video is no longer in the Library.',
      );
    }
    return video;
  }

  Future<LibraryAccessRequest> _requireLibrary(Video video) async {
    final folder = await _db.foldersDao.getFolderById(video.folderId);
    if (folder == null) {
      throw VideoVersionException(
        'The Library folder of "${video.title}" is missing. Rescan the '
        'Library and try again.',
      );
    }
    return LibraryAccessRequest(
      path: folder.path,
      bookmark: folder.securityScopedBookmark,
    );
  }

  Future<T> _withAccess<T>(
    LibraryAccessRequest access,
    String title,
    Future<T> Function() action,
  ) async {
    try {
      return await _libraryAccess.withAccess(library: access, action: action);
    } on LibraryAccessNeedsRepairException catch (error) {
      throw VideoVersionException(
        'Could not open the Library of "$title". ${error.message}',
      );
    }
  }

  Future<String> _chooseOutputPath({
    required VideoVersionInfo source,
    required VideoResolutionPreset preset,
    required bool keepSource,
  }) async {
    if (!keepSource) {
      final preferred = p.join(
        p.dirname(source.path),
        '${videoVersionBaseStem(source.path)}.mp4',
      );
      if (preferred == source.path || !await _isTaken(preferred)) {
        return preferred;
      }
    }
    return _nextFreeVersionPath(source.path, preset);
  }

  Future<String> _nextFreeVersionPath(
    String sourcePath,
    VideoResolutionPreset preset, {
    String? ownTemporaryPath,
  }) async {
    final directory = p.dirname(sourcePath);
    final stem = '${videoVersionBaseStem(sourcePath)} [${preset.label}]';
    var candidate = p.join(directory, '$stem.mp4');
    for (var n = 2; ; n++) {
      if (!await _isTaken(candidate, ownTemporaryPath: ownTemporaryPath)) {
        return candidate;
      }
      candidate = p.join(directory, '$stem ($n).mp4');
    }
  }

  /// Whether [path] exists on disk, is being written by another conversion
  /// (`.part`), or is already owned by a catalog video.
  Future<bool> _isTaken(String path, {String? ownTemporaryPath}) async {
    if (await _exists(path)) return true;
    final partPath = '$path.part';
    if (partPath != ownTemporaryPath && await _exists(partPath)) return true;
    return (await _versionsDao.registeredPaths([path])).isNotEmpty;
  }

  Future<Map<String, dynamic>> _probe(String path) async {
    try {
      return await _mediaService.getMetadata(path);
    } catch (error) {
      debugPrint('Could not probe converted file $path: $error');
      return const {};
    }
  }

  /// Inserts the primary row of a video that has none (an unconverted video
  /// or one whose primary row went missing). Returns the new row id.
  Future<int?> _ensurePrimaryRow(Video video, List<VideoVersion> rows) async {
    if (rows.any((row) => row.absolutePath == video.absolutePath)) {
      return null;
    }
    final existing = await _versionsDao.getVersionByPath(video.absolutePath);
    if (existing != null) return null;
    final dimensions = videoDimensionsFromMetadataJson(video.metadataJson);
    return _versionsDao.insertVersion(
      VideoVersionsCompanion.insert(
        videoId: video.id,
        absolutePath: video.absolutePath,
        width: Value(dimensions?.width),
        height: Value(dimensions?.height),
        duration: Value(video.duration),
        size: Value(video.size),
        metadataJson: Value(video.metadataJson),
        isOriginal: Value(!rows.any((row) => row.isOriginal)),
        createdAt: Value(video.addedAt),
      ),
    );
  }

  /// Points the `videos` row at [path] (call inside a transaction).
  Future<void> _switchPrimary({
    required Video video,
    required String path,
    required int size,
    required int duration,
    required String metadataJson,
    required FileStat? oldStat,
    required FileStat newStat,
  }) async {
    await (_db.update(_db.videos)..where((t) => t.id.equals(video.id))).write(
      VideosCompanion(
        absolutePath: Value(path),
        size: Value(size),
        duration: Value(duration),
        metadataJson: Value(metadataJson),
        isOffline: const Value(false),
      ),
    );
    await rebindVideoSummary(
      _db,
      videoId: video.id,
      oldStat: oldStat,
      newStat: newStat,
    );
  }

  Future<void> _deleteRowForPath(int videoId, String path) async {
    final row = await _versionsDao.getVersionByPath(path);
    if (row != null && row.videoId == videoId) {
      await _versionsDao.deleteVersionById(row.id);
    }
  }

  Future<VideoVersionInfo> _versionInfo(int videoId, String path) async {
    final versions = await listVersions(videoId);
    return versions.firstWhere((version) => version.path == path);
  }

  Future<VideoVersionException> _discard(
    VideoConversionPlan plan,
    String message,
  ) async {
    await _deleteQuietly(plan.temporaryPath);
    return VideoVersionException(message);
  }
}

class _ConvertedOutput {
  const _ConvertedOutput({
    required this.dimensions,
    required this.duration,
    required this.metadataJson,
  });

  final VideoDimensions dimensions;
  final int duration;
  final String metadataJson;

  VideoVersionsCompanion companion({
    required int videoId,
    required String path,
    required int size,
  }) {
    return VideoVersionsCompanion.insert(
      videoId: videoId,
      absolutePath: path,
      width: Value(dimensions.width),
      height: Value(dimensions.height),
      duration: Value(duration),
      size: Value(size),
      metadataJson: Value(metadataJson),
      isOriginal: const Value(false),
    );
  }
}

/// Keeps a summary fresh when the primary file changes encoding but not
/// content: if the stored source stat matched [oldStat] it is moved to
/// [newStat]; otherwise the summary is left as is.
Future<void> rebindVideoSummary(
  AppDatabase db, {
  required int videoId,
  required FileStat? oldStat,
  required FileStat newStat,
}) async {
  if (oldStat == null) return;
  final summary = await db.videoSummariesDao.getSummaryForVideo(videoId);
  if (summary == null) return;
  if (summary.sourceVideoSize != oldStat.size ||
      summary.sourceVideoModifiedAt.millisecondsSinceEpoch ~/ 1000 !=
          oldStat.modified.millisecondsSinceEpoch ~/ 1000) {
    return;
  }
  await (db.update(
    db.videoSummaries,
  )..where((t) => t.videoId.equals(videoId))).write(
    VideoSummariesCompanion(
      sourceVideoSize: Value(newStat.size),
      sourceVideoModifiedAt: Value(newStat.modified),
    ),
  );
}

Future<FileStat?> _statFile(String path) async {
  try {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.file ? stat : null;
  } on FileSystemException {
    return null;
  }
}

Future<bool> _exists(String path) async {
  return await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}

Future<void> _deleteQuietly(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException catch (error) {
    debugPrint('Could not delete $path: $error');
  }
}

String _describe(FileSystemException error) {
  final osMessage = error.osError?.message;
  if (osMessage != null && osMessage.isNotEmpty) return osMessage;
  return error.message;
}

final videoVersionServiceProvider = Provider<VideoVersionService>((ref) {
  return VideoVersionService(
    database: ref.watch(databaseProvider),
    libraryAccessService: ref.watch(libraryAccessServiceProvider),
    mediaService: ref.watch(mediaServiceProvider),
    runExclusive: <T>(action) => ref
        .read(libraryOperationControllerProvider.notifier)
        .runVersioning(action),
  );
});

/// Live versions of a video (re-emits when its `videos` row or any of its
/// `video_versions` rows change).
final videoVersionsProvider = StreamProvider.autoDispose
    .family<List<VideoVersionInfo>, int>((ref, videoId) {
      return ref.watch(videoVersionServiceProvider).watchVersions(videoId);
    });
