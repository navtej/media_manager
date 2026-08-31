import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/logic/playback_controller.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/natural_language_service.dart';
import 'package:movie_manager/services/playback_service.dart';

void main() {
  test(
    'keeps Library access for the complete native playback request',
    () async {
      final fixture = await _PlaybackFixture.create();
      addTearDown(fixture.dispose);

      expect(await fixture.controller.play(fixture.video), isTrue);

      expect(fixture.events, [
        'start:/Library:bookmark',
        'play:/Library/movie.mp4',
        'stop:/Library',
      ]);
    },
  );

  test('does not request playback when Library access needs repair', () async {
    final fixture = await _PlaybackFixture.create(bookmark: null);
    addTearDown(fixture.dispose);

    await expectLater(
      fixture.controller.play(fixture.video),
      throwsA(isA<LibraryAccessNeedsRepairException>()),
    );

    expect(fixture.events, isEmpty);
  });

  test('builds one playlist while all libraries are open', () async {
    final fixture = await _PlaybackFixture.create();
    addTearDown(fixture.dispose);
    final secondFolderId = await fixture.db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Archive',
        securityScopedBookmark: const drift.Value('archive-bookmark'),
      ),
    );
    await fixture.db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: secondFolderId,
        absolutePath: '/Archive/second.mp4',
        title: 'second',
      ),
    );
    final second = (await fixture.db.videosDao.getVideoByPath(
      '/Archive/second.mp4',
    ))!;

    expect(
      await fixture.controller.playPlaylist([second.id, fixture.video.id]),
      isTrue,
    );

    expect(fixture.events, [
      'start:/Archive:archive-bookmark',
      'start:/Library:bookmark',
      'playlist:/Archive/second.mp4,/Library/movie.mp4',
      'stop:/Library',
      'stop:/Archive',
    ]);
  });
}

class _PlaybackFixture {
  const _PlaybackFixture({
    required this.db,
    required this.controller,
    required this.video,
    required this.events,
  });

  final AppDatabase db;
  final PlaybackController controller;
  final Video video;
  final List<String> events;

  static Future<_PlaybackFixture> create({
    String? bookmark = 'bookmark',
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Library',
        securityScopedBookmark: drift.Value(bookmark),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: folderId,
        absolutePath: '/Library/movie.mp4',
        title: 'movie',
      ),
    );
    final video = (await db.videosDao.getVideoByPath('/Library/movie.mp4'))!;
    final events = <String>[];
    final controller = PlaybackController(
      foldersDao: db.foldersDao,
      videosDao: db.videosDao,
      libraryAccessService: LibraryAccessService(
        adapter: _PlaybackLibraryAccessAdapter(events),
      ),
      playbackService: _RecordingPlaybackService(events),
      naturalLanguageService: NaturalLanguageService(),
    );

    return _PlaybackFixture(
      db: db,
      controller: controller,
      video: video,
      events: events,
    );
  }

  Future<void> dispose() => db.close();
}

class _PlaybackLibraryAccessAdapter implements LibraryAccessAdapter {
  _PlaybackLibraryAccessAdapter(this.events);

  final List<String> events;

  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    events.add('start:$path:$bookmark');
    return true;
  }

  @override
  Future<void> stopAccessing(String path) async {
    events.add('stop:$path');
  }
}

class _RecordingPlaybackService extends PlaybackService {
  _RecordingPlaybackService(this.events);

  final List<String> events;

  @override
  Future<bool> playVideo(String path) async {
    events.add('play:$path');
    return true;
  }

  @override
  Future<bool> playPlaylist(List<String> paths) async {
    events.add('playlist:${paths.join(',')}');
    return true;
  }
}
