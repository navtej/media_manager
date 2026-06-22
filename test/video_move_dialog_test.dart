import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/video_move_controller.dart';
import 'package:movie_manager/services/folder_access_service.dart';
import 'package:movie_manager/ui/widgets/video_move_dialog.dart';

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
    await db.videosDao.insertVideo(
      VideosCompanion.insert(
        folderId: sourceFolderId,
        absolutePath: '/Volumes/Source Library/clip.mp4',
        title: 'clip',
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
          folderAccessServiceProvider.overrideWithValue(
            _AlwaysAllowedFolderAccessService(),
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

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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

class _AlwaysAllowedFolderAccessService extends FolderAccessService {
  @override
  Future<FolderAccessSession> startAccessing({
    required String path,
    required String? bookmark,
  }) async {
    return FolderAccessSession(path: path, canAccess: true, needsRepair: false);
  }

  @override
  Future<void> stopAccessing({
    required String path,
    required String? bookmark,
  }) async {}
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
