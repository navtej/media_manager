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
  testWidgets('video info dialog closes after grid item rebuilds', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime(2026, 6, 8);
    final folder = Folder(
      id: 1,
      path: '/Volumes/Test Library',
      alias: 'Test Library',
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
    final rebuildToken = ValueNotifier<int>(0);
    addTearDown(rebuildToken.dispose);

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
                    child: ValueListenableBuilder<int>(
                      valueListenable: rebuildToken,
                      builder: (context, version, _) {
                        return VideoGridItem(
                          key: ValueKey(version),
                          video: video,
                        );
                      },
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

    await tester.tap(find.byIcon(CupertinoIcons.info));
    await tester.pumpAndSettle();
    expect(find.text('Video Information'), findsOneWidget);

    rebuildToken.value = 1;
    await tester.pump();
    expect(find.text('Video Information'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Video Information'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _TestSettings extends Settings {
  @override
  Future<Map<String, dynamic>> build() async {
    return <String, dynamic>{
      'summaryModelPath': '',
      'summaryPreferVttSubtitles': true,
      'summaryApiUrl': '',
      'summaryApiKey': '',
    };
  }
}

class _TestFoldersDao extends FoldersDao {
  _TestFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Future<List<Folder>> getAllFolders() async => _folders;
}

class _TestTagsDao extends TagsDao {
  _TestTagsDao(super.db);

  @override
  Stream<List<Tag>> watchTagsForVideo(int videoId) => Stream.value(const []);

  @override
  Stream<List<String>> watchAllUniqueTags() => Stream.value(const []);
}

class _TestVideoSummariesDao extends VideoSummariesDao {
  _TestVideoSummariesDao(super.db);

  @override
  Stream<VideoSummary?> watchSummaryForVideo(int videoId) => Stream.value(null);
}
