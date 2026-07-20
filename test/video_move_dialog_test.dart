import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/video_move_controller.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/ui/widgets/video_move_dialog.dart';

import 'support/library_access_test_adapter.dart';

void main() {
  test('wide compact sizing scales from the window size', () {
    final defaultWindowSize = wideCompactMoveDialogSizeForTesting(
      const Size(800, 600),
    );
    expect(defaultWindowSize.width, 720);
    expect(defaultWindowSize.height, 340);

    final largeWindowSize = wideCompactMoveDialogSizeForTesting(
      const Size(1400, 900),
    );
    expect(largeWindowSize.width, 1120);
    expect(largeWindowSize.height, 396);
  });

  testWidgets('move dialog ellipsizes long destination folder labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final sourceFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Source Library',
        alias: const drift.Value('  Source Library  '),
        securityScopedBookmark: const drift.Value('source-bookmark'),
      ),
    );
    final destinationFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path:
            '/Volumes/Archive/Projects/Client Library/2026/Very Long Destination Folder Name',
        alias: const drift.Value('Archive Destination With A Very Long Alias'),
        securityScopedBookmark: const drift.Value('destination-bookmark'),
      ),
    );
    await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Private Destination',
        alias: const drift.Value('Private Destination'),
        isPrivate: const drift.Value(true),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: sourceFolderId,
        absolutePath: '/Volumes/Source Library/clip.mp4',
        title: 'clip',
        size: const drift.Value(1024),
      ),
    );
    final video = (await db.videosDao.getVideoByPath(
      '/Volumes/Source Library/clip.mp4',
    ))!;
    final sourceFolder = (await db.foldersDao.getFolderById(sourceFolderId))!;
    final destinationFolder = (await db.foldersDao.getFolderById(
      destinationFolderId,
    ))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(db, [sourceFolder, destinationFolder]),
          ),
          libraryAccessServiceProvider.overrideWithValue(
            LibraryAccessService(adapter: AlwaysAllowedLibraryAccessAdapter()),
          ),
        ],
        child: MacosApp(
          home: MacosWindow(
            child: Consumer(
              builder: (context, ref, _) {
                return Center(
                  child: PushButton(
                    controlSize: ControlSize.large,
                    onPressed: () {
                      showVideoMoveDialog(
                        context: context,
                        ref: ref,
                        selectedVideoIds: [video.id],
                      );
                    },
                    child: const Text('Move Videos'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Move Videos'));
    await tester.pumpAndSettle();

    expect(find.text('Move Selected Videos'), findsOneWidget);
    expect(find.text('1 selected • 1.0 KB'), findsOneWidget);
    final expectedDialogSize = wideCompactMoveDialogSizeForTesting(
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    expect(
      tester.getSize(find.byKey(wideMoveDialogFrameKey)),
      expectedDialogSize,
    );
    expect(tester.takeException(), isNull);
    expect(destinationFolderId, isPositive);
    expect(
      find.text('Source Library (/Volumes/Source Library)'),
      findsOneWidget,
    );
    expect(
      find.text('Private Destination (/Volumes/Private Destination)'),
      findsNothing,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'shows unique count while size loads and keeps summary across preflight',
    (tester) async {
      final fixture = await _DialogFixture.create(size: 2048);
      addTearDown(fixture.dispose);
      final videosDao = _DeferredFirstVideosDao(fixture.db);

      await _pumpMoveDialog(
        tester,
        fixture: fixture,
        videosDao: videosDao,
        selectedVideoIds: [fixture.video.id, fixture.video.id],
      );
      await tester.tap(find.text('Move Videos'));
      await tester.pump();

      expect(find.text('1 selected • Calculating size…'), findsOneWidget);

      videosDao.firstCall.complete([fixture.video]);
      await tester.pumpAndSettle();
      expect(find.text('1 selected • 2.0 KB'), findsOneWidget);

      await tester.tap(find.text(fixture.sourceLabel).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(fixture.destinationLabel).last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1 selected • 2.0 KB'), findsOneWidget);
      expect(videosDao.callCount, 3);
    },
  );

  testWidgets('size query failure leaves destination preflight usable', (
    tester,
  ) async {
    final fixture = await _DialogFixture.create(size: 1024);
    addTearDown(fixture.dispose);
    final videosDao = _FailingFirstVideosDao(fixture.db);

    await _pumpMoveDialog(
      tester,
      fixture: fixture,
      videosDao: videosDao,
      selectedVideoIds: [fixture.video.id],
    );
    await tester.tap(find.text('Move Videos'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected • total size unavailable'), findsOneWidget);
    expect(find.text('clip -> Already in destination'), findsOneWidget);
    expect(videosDao.callCount, 2);
  });

  testWidgets('move results dialog uses responsive body size', (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: Builder(
            builder: (context) {
              return Center(
                child: PushButton(
                  controlSize: ControlSize.large,
                  onPressed: () {
                    showVideoMoveResultDialog(
                      context: context,
                      result: const VideoMoveResult(
                        skipped: [
                          VideoMoveItemResult(
                            videoId: 1,
                            title: 'Skipped Clip',
                            sourcePath: '/source/skipped.mp4',
                            destinationPath: '/destination/skipped.mp4',
                            message: 'Already in destination.',
                          ),
                        ],
                        failures: [
                          VideoMoveItemResult(
                            videoId: 2,
                            title: 'Failed Clip',
                            sourcePath: '/source/failed.mp4',
                            destinationPath: '/destination/failed.mp4',
                            message: 'Destination exists.',
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Show Results'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show Results'));
    await tester.pumpAndSettle();

    expect(find.text('Move Results'), findsOneWidget);
    final expectedDialogSize = wideCompactMoveDialogSizeForTesting(
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    expect(
      tester.getSize(find.byKey(wideMoveDialogFrameKey)),
      expectedDialogSize,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _StaticFoldersDao extends FoldersDao {
  _StaticFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Future<List<Folder>> getAllFolders() async => _folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);

  @override
  Future<Folder?> getFolderById(int id) async {
    for (final folder in _folders) {
      if (folder.id == id) {
        return folder;
      }
    }
    return null;
  }
}

class _DeferredFirstVideosDao extends VideosDao {
  _DeferredFirstVideosDao(super.db);

  final firstCall = Completer<List<Video>>();
  int callCount = 0;

  @override
  Future<List<Video>> getVideosByIds(List<int> ids) {
    callCount += 1;
    if (callCount == 1) return firstCall.future;
    return super.getVideosByIds(ids);
  }
}

class _FailingFirstVideosDao extends VideosDao {
  _FailingFirstVideosDao(super.db);

  int callCount = 0;

  @override
  Future<List<Video>> getVideosByIds(List<int> ids) {
    callCount += 1;
    if (callCount == 1) {
      return Future<List<Video>>.error(StateError('size query failed'));
    }
    return super.getVideosByIds(ids);
  }
}

class _DialogFixture {
  const _DialogFixture({
    required this.db,
    required this.video,
    required this.sourceFolder,
    required this.destinationFolder,
  });

  final AppDatabase db;
  final Video video;
  final Folder sourceFolder;
  final Folder destinationFolder;

  String get sourceLabel => 'Source Library (${sourceFolder.path})';
  String get destinationLabel =>
      'Destination Library (${destinationFolder.path})';

  static Future<_DialogFixture> create({required int size}) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final sourceFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Test Source',
        alias: const drift.Value('Source Library'),
        securityScopedBookmark: const drift.Value('source-bookmark'),
      ),
    );
    final destinationFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Test Destination',
        alias: const drift.Value('Destination Library'),
        securityScopedBookmark: const drift.Value('destination-bookmark'),
      ),
    );
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: sourceFolderId,
        absolutePath: '/Volumes/Test Source/clip.mp4',
        title: 'clip',
        size: drift.Value(size),
      ),
    );

    return _DialogFixture(
      db: db,
      video: (await db.videosDao.getVideoByPath(
        '/Volumes/Test Source/clip.mp4',
      ))!,
      sourceFolder: (await db.foldersDao.getFolderById(sourceFolderId))!,
      destinationFolder: (await db.foldersDao.getFolderById(
        destinationFolderId,
      ))!,
    );
  }

  Future<void> dispose() => db.close();
}

Future<void> _pumpMoveDialog(
  WidgetTester tester, {
  required _DialogFixture fixture,
  required VideosDao videosDao,
  required List<int> selectedVideoIds,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(fixture.db),
        videosDaoProvider.overrideWithValue(videosDao),
        foldersDaoProvider.overrideWithValue(
          _StaticFoldersDao(fixture.db, [
            fixture.sourceFolder,
            fixture.destinationFolder,
          ]),
        ),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: AlwaysAllowedLibraryAccessAdapter()),
        ),
      ],
      child: MacosApp(
        home: MacosWindow(
          child: Consumer(
            builder: (context, ref, _) => Center(
              child: PushButton(
                controlSize: ControlSize.large,
                onPressed: () => showVideoMoveDialog(
                  context: context,
                  ref: ref,
                  selectedVideoIds: selectedVideoIds,
                ),
                child: const Text('Move Videos'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
