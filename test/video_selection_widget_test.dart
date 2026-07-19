import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/ui/widgets/video_grid.dart';

void main() {
  testWidgets('video selection checkbox marks the card selected', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime(2026, 6, 8);
    final folder = Folder(
      id: 1,
      path: '/Volumes/Test Library',
      alias: 'Test Library',
      isPrivate: false,
      addedAt: now,
    );
    final video = Video(
      id: 1,
      folderId: folder.id,
      absolutePath: '/Volumes/Test Library/clip.mp4',
      title: 'clip',
      duration: 12,
      size: 1024,
      metadataJson: '{}',
      isOffline: false,
      isFavorite: false,
      addedAt: now,
      fileCreatedAt: now,
      aiProcessed: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(_TestFoldersDao(db, [folder])),
          tagsDaoProvider.overrideWithValue(_TestTagsDao(db)),
          videoSummariesDaoProvider.overrideWithValue(
            _TestVideoSummariesDao(db),
          ),
          settingsProvider.overrideWith(_TestSettings.new),
        ],
        child: MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [
                ContentArea(
                  builder: (context, _) => SizedBox(
                    width: 350,
                    height: 280,
                    child: VideoGridItem(
                      key: const ValueKey('video-item'),
                      video: video,
                      visibleVideoIds: const [1],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('video-selection-1')));
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.checkmark), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _TestSettings extends Settings {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _TestFoldersDao extends FoldersDao {
  _TestFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Future<List<Folder>> getAllFolders() async => _folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);
}

class _TestTagsDao extends TagsDao {
  _TestTagsDao(super.db);

  @override
  Stream<List<Tag>> watchTagsForVideo(int videoId) => Stream.value(const []);

  @override
  Stream<List<String>> watchAllUniqueTags({List<int>? folderIds}) =>
      Stream.value(const []);
}

class _TestVideoSummariesDao extends VideoSummariesDao {
  _TestVideoSummariesDao(super.db);

  @override
  Stream<VideoSummary?> watchSummaryForVideo(int videoId) => Stream.value(null);
}
