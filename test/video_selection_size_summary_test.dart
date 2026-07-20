import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/catalog_controller.dart';
import 'package:movie_manager/logic/video_move_controller.dart';

void main() {
  group('VideoSelectionSizeSummary', () {
    test('deduplicates IDs and totals all known sizes', () {
      final summary = VideoSelectionSizeSummary.fromSelection(
        selectedIds: const [2, 1, 2],
        videos: [_video(1, 1024), _video(2, 2048)],
      );

      expect(summary.selectedCount, 2);
      expect(summary.knownBytes, 3072);
      expect(summary.unknownCount, 0);
      expect(summary.label, '2 selected • 3.0 KB');
    });

    test('reports mixed known, non-positive, and missing sizes', () {
      final summary = VideoSelectionSizeSummary.fromSelection(
        selectedIds: const [1, 2, 3, 4],
        videos: [_video(1, 1024), _video(2, 0), _video(3, -1)],
      );

      expect(summary.knownBytes, 1024);
      expect(summary.unknownCount, 3);
      expect(summary.label, '4 selected • 1.0 KB known • 3 sizes unknown');
    });

    test('formats all-unknown singular and plural selections', () {
      final singular = VideoSelectionSizeSummary.fromSelection(
        selectedIds: const [1],
        videos: [_video(1, 0)],
      );
      final plural = VideoSelectionSizeSummary.fromSelection(
        selectedIds: const [1, 2],
        videos: [_video(1, 0)],
      );

      expect(singular.label, '1 selected • 0 B known • 1 size unknown');
      expect(plural.label, '2 selected • 0 B known • 2 sizes unknown');
    });
  });

  test('existing size formatter keeps binary unit boundaries', () {
    expect(LibraryStats.formatSize(0), '0 B');
    expect(LibraryStats.formatSize(1023), '1023 B');
    expect(LibraryStats.formatSize(1024), '1.0 KB');
    expect(LibraryStats.formatSize(1024 * 1024), '1.0 MB');
    expect(LibraryStats.formatSize(1024 * 1024 * 1024), '1.0 GB');
  });

  test(
    'controller resolves the complete selection through VideosDao',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final folderId = await db.foldersDao.insertFolder(
        FoldersCompanion.insert(path: '/library'),
      );
      await db.videosDao.insertVideo(
        VideosCompanion.insert(
          folderId: folderId,
          absolutePath: '/library/known.mp4',
          title: 'known',
          size: const drift.Value(2048),
        ),
      );
      final video = (await db.videosDao.getVideoByPath('/library/known.mp4'))!;
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final summary = await container
          .read(videoMoveControllerProvider.notifier)
          .summarizeSelection([video.id, 999, video.id]);

      expect(summary.selectedCount, 2);
      expect(summary.knownBytes, 2048);
      expect(summary.unknownCount, 1);
    },
  );
}

Video _video(int id, int size) {
  return Video(
    id: id,
    folderId: 1,
    absolutePath: '/library/$id.mp4',
    title: '$id',
    duration: 0,
    size: size,
    metadataJson: '{}',
    isOffline: false,
    isFavorite: false,
    addedAt: DateTime(2026),
    aiProcessed: false,
  );
}
