import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/video_summary_controller.dart';
import 'package:movie_manager/logic/video_summary_models.dart';
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

  testWidgets('fresh module state drives summary badge and dialog rendering', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 7, 20);
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
      absolutePath: '${folder.path}/clip.mp4',
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
    final state = VideoSummaryState.fresh(
      summary: const StructuredVideoSummary(
        synopsis: 'Shared fresh summary.',
        highlights: ['Point'],
        keywords: ['test'],
      ),
      configuredTranscriptModel: 'ggml-test.bin',
      preferVttSubtitles: true,
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
          videoSummaryStateProvider.overrideWith((_, _) async => state),
          videoSummarySubtitleAvailabilityProvider.overrideWith(
            (_, _) async => const VideoSummarySubtitleAvailability.notFound(),
          ),
          summaryModelValidationProvider.overrideWith(
            (_) async => const SummaryModelValidationResult.valid('Ready'),
          ),
        ],
        child: MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [
                ContentArea(
                  builder: (context, _) => SizedBox(
                    width: 350,
                    height: 280,
                    child: VideoGridItem(video: video),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final summaryIcon = find.byIcon(CupertinoIcons.doc_text);
    await _pumpUntil(tester, () {
      final icons = summaryIcon.evaluate();
      return icons.length == 1 &&
          tester.widget<Icon>(summaryIcon).color ==
              MacosColors.systemGreenColor;
    });

    expect(summaryIcon, findsOneWidget);
    expect(
      tester.widget<Icon>(summaryIcon).color,
      MacosColors.systemGreenColor,
    );

    await tester.tap(summaryIcon);
    await _pumpUntil(
      tester,
      () => find.text('Shared fresh summary.').evaluate().isNotEmpty,
    );

    expect(find.text('Shared fresh summary.'), findsOneWidget);
    expect(find.text('Regenerate'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  throw StateError('Timed out waiting for widget state.');
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
