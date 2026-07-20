import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/providers.dart';
import '../services/empty_folder_cleanup_service.dart';
import '../services/media_deletion_service.dart';
import '../services/thumbnail_service.dart';
import 'library_controller.dart' show scanStatusProvider;
import 'library_operation_controller.dart';
import 'managed_library_service.dart';
import 'private_library_controller.dart';
import 'settings_provider.dart';
import 'status_message_provider.dart';

part 'maintenance_controller.g.dart';

const emptyFolderCleanupScheduleAnchorKey = 'emptyFolderCleanupScheduleAnchor';

typedef EmptyFolderCleanupClock = DateTime Function();
typedef EmptyFolderCleanupTimerFactory =
    Timer Function(Duration duration, void Function() callback);

final emptyFolderCleanupClockProvider = Provider<EmptyFolderCleanupClock>(
  (ref) => DateTime.now,
);
final emptyFolderCleanupTimerFactoryProvider =
    Provider<EmptyFolderCleanupTimerFactory>(
      (ref) =>
          (duration, callback) => Timer(duration, callback),
    );

@Riverpod(keepAlive: true)
class MaintenanceController extends _$MaintenanceController {
  Timer? _emptyFolderCleanupTimer;
  EmptyFolderCleanupConfiguration _cleanupConfiguration =
      EmptyFolderCleanupConfiguration.defaults;
  DateTime? _cleanupAnchor;
  bool _cleanupInitialized = false;
  bool _cleanupRunning = false;

  @override
  Future<void> build() async {
    ref.onDispose(() => _emptyFolderCleanupTimer?.cancel());
    ref.listen(settingsProvider, (previous, next) {
      final configuration = next.asData?.value.emptyFolderCleanup;
      if (_cleanupInitialized && configuration != null) {
        unawaited(_applyCleanupConfiguration(configuration));
      }
    });
    ref.listen(libraryOperationControllerProvider, (previous, next) {
      if (_cleanupInitialized && (previous?.isBusy ?? false) && !next.isBusy) {
        unawaited(evaluateEmptyFolderCleanupSchedule());
      }
    });

    _cleanupConfiguration = (await ref.read(
      settingsProvider.future,
    )).emptyFolderCleanup;
    if (_cleanupConfiguration.enabled) {
      _cleanupAnchor = await _readCleanupAnchor();
      if (_cleanupAnchor == null) {
        _cleanupAnchor = ref.read(emptyFolderCleanupClockProvider)();
        await _writeCleanupAnchor(_cleanupAnchor!);
      }
    }
    final latestConfiguration = (await ref.read(
      settingsProvider.future,
    )).emptyFolderCleanup;
    _cleanupInitialized = true;
    await _applyCleanupConfiguration(latestConfiguration);
  }

  Future<void> _applyCleanupConfiguration(
    EmptyFolderCleanupConfiguration configuration,
  ) async {
    final wasEnabled = _cleanupConfiguration.enabled;
    _cleanupConfiguration = configuration;
    _emptyFolderCleanupTimer?.cancel();

    if (!configuration.enabled) {
      return;
    }
    if (!wasEnabled) {
      _cleanupAnchor = ref.read(emptyFolderCleanupClockProvider)();
      await _writeCleanupAnchor(_cleanupAnchor!);
    } else if (_cleanupAnchor == null) {
      _cleanupAnchor =
          await _readCleanupAnchor() ??
          ref.read(emptyFolderCleanupClockProvider)();
      await _writeCleanupAnchor(_cleanupAnchor!);
    }
    await evaluateEmptyFolderCleanupSchedule();
  }

  Future<void> evaluateEmptyFolderCleanupSchedule() async {
    _emptyFolderCleanupTimer?.cancel();
    if (!_cleanupInitialized ||
        !_cleanupConfiguration.enabled ||
        _cleanupRunning) {
      return;
    }

    final anchor = _cleanupAnchor;
    if (anchor == null) {
      return;
    }
    final now = ref.read(emptyFolderCleanupClockProvider)();
    final dueAt = anchor.add(_cleanupConfiguration.interval);
    if (now.isBefore(dueAt)) {
      _emptyFolderCleanupTimer =
          ref.read(emptyFolderCleanupTimerFactoryProvider)(
            dueAt.difference(now),
            () => unawaited(evaluateEmptyFolderCleanupSchedule()),
          );
      return;
    }

    final operation = ref.read(libraryOperationControllerProvider.notifier);
    if (!operation.beginCleanup()) {
      return;
    }

    _cleanupRunning = true;
    ref
        .read(scanStatusProvider.notifier)
        .setStatus('Removing empty Library folders...');
    EmptyFolderCleanupResult? result;
    try {
      result = await ref.read(emptyFolderCleanupRunnerProvider)();
    } catch (error) {
      print('Empty-folder cleanup sweep failed: $error');
    } finally {
      if (result != null) {
        final completionAnchor = ref.read(emptyFolderCleanupClockProvider)();
        _cleanupAnchor = completionAnchor;
        try {
          await _writeCleanupAnchor(completionAnchor);
        } catch (error) {
          print('Failed to persist empty-folder cleanup schedule: $error');
        }
      }
      operation.endCleanup();
      ref.read(scanStatusProvider.notifier).setStatus('');
      _cleanupRunning = false;
    }
    if (result == null) {
      ref
          .read(statusMessageProvider.notifier)
          .set('Empty-folder cleanup failed; will retry later.');
      if (_cleanupConfiguration.enabled) {
        _emptyFolderCleanupTimer =
            ref.read(emptyFolderCleanupTimerFactoryProvider)(
              _cleanupConfiguration.interval,
              () => unawaited(evaluateEmptyFolderCleanupSchedule()),
            );
      }
      return;
    }
    ref.read(statusMessageProvider.notifier).set(result.summary);
    await evaluateEmptyFolderCleanupSchedule();
  }

  Future<DateTime?> _readCleanupAnchor() async {
    final persistence = await ref.read(settingsPersistenceProvider.future);
    final value = persistence.getString(emptyFolderCleanupScheduleAnchorKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> _writeCleanupAnchor(DateTime anchor) async {
    final persistence = await ref.read(settingsPersistenceProvider.future);
    await persistence.setString(
      emptyFolderCleanupScheduleAnchorKey,
      anchor.toIso8601String(),
    );
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
    }
    return result;
  }

  Future<MediaDeletionResult> deleteVideo(int videoId) async {
    final result = await ref
        .read(mediaDeletionServiceProvider)
        .deleteVideo(videoId);
    return result;
  }

  Future<MediaDeletionBatchResult?> deleteVideos(List<int> videoIds) {
    return ref
        .read(privateLibraryAccessControllerProvider.notifier)
        .runVideoAction<MediaDeletionBatchResult>(
          videoIds: videoIds,
          action: () async {
            final result = await ref
                .read(mediaDeletionServiceProvider)
                .deleteVideos(videoIds);
            return result;
          },
        );
  }

  Future<bool> setFavoriteForVideos(List<int> videoIds, bool isFavorite) async {
    final actionCompleted = await ref
        .read(privateLibraryAccessControllerProvider.notifier)
        .runVideoAction<bool>(
          videoIds: videoIds,
          action: () async {
            await ref
                .read(videosDaoProvider)
                .setFavoriteForVideos(videoIds, isFavorite);
            return true;
          },
        );
    return actionCompleted ?? false;
  }

  Future<bool> clearTagsForVideos(List<int> videoIds) async {
    final actionCompleted = await ref
        .read(privateLibraryAccessControllerProvider.notifier)
        .runVideoAction<bool>(
          videoIds: videoIds,
          action: () async {
            await ref.read(tagsDaoProvider).deleteAllTagsForVideos(videoIds);
            return true;
          },
        );
    return actionCompleted ?? false;
  }
}
