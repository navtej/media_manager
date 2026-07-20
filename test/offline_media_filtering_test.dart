import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/catalog_controller.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/provider_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offline-media preference immediately updates videos and counts',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'showOfflineMedia': false,
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final folderId = await db.foldersDao.insertFolder(
        FoldersCompanion.insert(path: '/Volumes/Media/Movies'),
      );
      await db.videosDao.insertVideo(
        VideosCompanion.insert(
          folderId: folderId,
          absolutePath: '/Volumes/Media/Movies/online.mp4',
          title: 'Online Clip',
        ),
      );
      await db.videosDao.insertVideo(
        VideosCompanion.insert(
          folderId: folderId,
          absolutePath: '/Volumes/Media/Movies/offline.mp4',
          title: 'Offline Clip',
          isOffline: const drift.Value(true),
        ),
      );
      final onlineVideo = (await db.videosDao.getVideoByPath(
        '/Volumes/Media/Movies/online.mp4',
      ))!;
      final offlineVideo = (await db.videosDao.getVideoByPath(
        '/Volumes/Media/Movies/offline.mp4',
      ))!;
      await db.tagsDao.insertTagsBatch([
        TagsCompanion.insert(
          videoId: onlineVideo.id,
          tagText: 'Online',
          source: const drift.Value('user'),
        ),
        TagsCompanion.insert(
          videoId: offlineVideo.id,
          tagText: 'Offline',
          source: const drift.Value('user'),
        ),
      ]);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await readAsyncValue(container, libraryFoldersProvider);

      expect(
        (await readAsyncValue(
          container,
          filteredVideosProvider,
        )).map((video) => video.title),
        ['Online Clip'],
      );
      expect(await readAsyncValue(container, selectedVideoCountProvider), 1);
      expect(
        (await readAsyncValue(
          container,
          allTagsProvider,
        )).map((entry) => entry.key),
        ['online'],
      );
      expect(
        (await readAsyncValue(container, libraryStatsProvider)).totalCount,
        1,
      );

      await container
          .read(settingsProvider.notifier)
          .updateShowOfflineMedia(true);

      expect(
        (await readAsyncValue(
          container,
          filteredVideosProvider,
        )).map((video) => video.title),
        unorderedEquals(['Online Clip', 'Offline Clip']),
      );
      expect(await readAsyncValue(container, selectedVideoCountProvider), 2);
      expect(
        (await readAsyncValue(
          container,
          allTagsProvider,
        )).map((entry) => entry.key).toSet(),
        {'offline', 'online'},
      );
      expect(
        (await readAsyncValue(container, libraryStatsProvider)).totalCount,
        2,
      );
    },
  );
}
