import 'package:drift/drift.dart' as drift;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/catalog_controller.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/playback_controller.dart';
import 'package:movie_manager/services/playback_service.dart';
import 'package:movie_manager/logic/video_selection_controller.dart';
import 'package:movie_manager/ui/screens/home_screen.dart';
import 'package:movie_manager/ui/widgets/catalog_presentation.dart';
import 'package:movie_manager/ui/widgets/video_grid.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/natural_language_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'catalog anchor maps the same Video and local offset between layouts',
    () {
      final ids = List<int>.generate(40, (index) => index + 1);
      final gridAnchor = CatalogScrollAnchor.capture(
        presentation: CatalogPresentation.grid,
        orderedVideoIds: ids,
        scrollOffset: 1240,
        viewportWidth: 1000,
      );

      expect(gridAnchor.videoId, 13);
      expect(gridAnchor.localOffset, 24);
      expect(
        gridAnchor.offsetFor(
          presentation: CatalogPresentation.list,
          orderedVideoIds: ids,
          viewportWidth: 1000,
        ),
        992,
      );

      final deepGridAnchor = CatalogScrollAnchor.capture(
        presentation: CatalogPresentation.grid,
        orderedVideoIds: ids,
        scrollOffset: 1400,
        viewportWidth: 1000,
      );
      final deepListOffset = deepGridAnchor.offsetFor(
        presentation: CatalogPresentation.list,
        orderedVideoIds: ids,
        viewportWidth: 1000,
      );
      expect(deepGridAnchor.videoId, 13);
      expect(deepListOffset, 1047);
      expect(
        CatalogScrollAnchor.capture(
          presentation: CatalogPresentation.list,
          orderedVideoIds: ids,
          scrollOffset: deepListOffset,
          viewportWidth: 1000,
        ).videoId,
        deepGridAnchor.videoId,
      );

      final missingAnchorIds = ids.where((id) => id != 13).toList();
      expect(
        gridAnchor.offsetFor(
          presentation: CatalogPresentation.list,
          orderedVideoIds: missingAnchorIds,
          viewportWidth: 1000,
        ),
        992,
      );
    },
  );

  testWidgets('toolbar control exposes selected semantics and switches modes', (
    tester,
  ) async {
    var presentation = CatalogPresentation.grid;
    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: StatefulBuilder(
            builder: (context, setState) => Center(
              child: CatalogPresentationControl(
                presentation: presentation,
                onChanged: (value) => setState(() => presentation = value),
              ),
            ),
          ),
        ),
      ),
    );

    expect(_tooltipMessages(tester), containsAll(['Grid view', 'List view']));
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('catalog-presentation-grid')),
      ),
      matchesSemantics(
        label: 'Grid view',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(presentation, CatalogPresentation.list);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('catalog-presentation-list')),
      ),
      matchesSemantics(
        label: 'List view',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isFocusable: true,
        isFocused: true,
        hasEnabledState: true,
        isEnabled: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('compact row keeps required content and actions within 80 px', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 7, 21);
    final folder = Folder(
      id: 1,
      path: '/Volumes/Very Long Test Library',
      alias: 'Test Library',
      isPrivate: false,
      addedAt: now,
    );
    final video = Video(
      id: 1,
      folderId: 1,
      absolutePath:
          '/Volumes/Very Long Test Library/Deep/Nested/Folder/clip.mp4',
      title: 'A long Video title that must remain available in a tooltip',
      duration: 3723,
      size: 1024 * 1024 * 2,
      metadataJson: '{}',
      isOffline: true,
      isFavorite: false,
      addedAt: now,
      fileCreatedAt: now,
      aiProcessed: false,
    );
    final videosDao = _RecordingVideosDao(db);
    final tagsDao = _TestTagsDao(
      db,
      tags: [
        const Tag(
          id: 1,
          videoId: 1,
          tagText: 'A very long readable tag value',
          source: 'user',
        ),
      ],
    );
    final playbackController = _RecordingPlaybackController(
      foldersDao: _TestFoldersDao(db, [folder]),
      videosDao: videosDao,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(_TestFoldersDao(db, [folder])),
          videosDaoProvider.overrideWithValue(videosDao),
          tagsDaoProvider.overrideWithValue(tagsDao),
          playbackControllerProvider.overrideWithValue(playbackController),
          videoSummariesDaoProvider.overrideWithValue(
            _TestVideoSummariesDao(db),
          ),
          settingsProvider.overrideWith(_TestSettings.new),
        ],
        child: MacosApp(
          theme: MacosThemeData.light(),
          darkTheme: MacosThemeData.dark(),
          themeMode: ThemeMode.dark,
          home: MacosWindow(
            child: Center(
              child: SizedBox(
                width: 548,
                height: 80,
                child: VideoGridItem(
                  key: const ValueKey('video-row-1'),
                  video: video,
                  visibleVideoIds: const [1],
                  presentation: CatalogPresentation.list,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('video-row-1'))).height,
      80,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('video-thumbnail-1'))),
      const Size(112, 63),
    );
    expect(find.text('Offline'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('video-row-1'))),
      matchesSemantics(
        label: video.title,
        value: '1:02:03, 2.0 MB, Offline',
        isButton: true,
        isSelected: false,
        hasSelectedState: true,
        isFocusable: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );
    expect(
      _tooltipMessages(tester),
      containsAll([
        video.title,
        video.absolutePath,
        'Play',
        'Favorite',
        'Add or edit tags',
        'A very long readable tag value',
      ]),
    );

    await tester.tap(find.byKey(const ValueKey('video-play-1')));
    await tester.pump();
    expect(playbackController.playedVideoIds, [1]);
    await tester.tap(find.byKey(const ValueKey('video-favorite-1')));
    await tester.pump();
    expect(videosDao.favoriteToggles, [(id: 1, current: false)]);

    await tester.tap(find.byKey(const ValueKey('video-edit-tags-1')));
    await tester.pumpAndSettle();
    expect(find.text('Tags: ${video.title}'), findsOneWidget);
    expect(find.text('A very long readable tag value'), findsWidgets);
    expect(find.byType(MacosTextField), findsOneWidget);
    await tester.enterText(find.byType(MacosTextField), 'new tag');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(tagsDao.insertedTags, [(videoId: 1, tag: 'new tag')]);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(MacosPulldownButton));
    await tester.pumpAndSettle();
    for (final label in ['Reveal in Finder', 'Clear Tags']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Info'), findsNothing);
    expect(find.text('Video Summary'), findsNothing);
    expect(find.byType(MacosPulldownMenuDivider), findsNothing);

    await tester.tap(find.text('Reveal in Finder'));
    await tester.pumpAndSettle();
    expect(playbackController.revealedVideoIds, [1]);

    await tester.tap(find.byKey(const ValueKey('video-delete-1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Video?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('video-more-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Tags'));
    await tester.pumpAndSettle();
    expect(tagsDao.clearedVideoIds, [1]);
  });

  testWidgets('compact rows route plain, meta, shift, and checkbox selection', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 7, 21);
    final folder = Folder(
      id: 1,
      path: '/Volumes/Catalog',
      alias: 'Catalog',
      isPrivate: false,
      addedAt: now,
    );
    final videos = List.generate(
      3,
      (index) => Video(
        id: index + 1,
        folderId: 1,
        absolutePath: '/Volumes/Catalog/video-${index + 1}.mp4',
        title: 'Video ${index + 1}',
        duration: 60,
        size: 1024,
        metadataJson: '{}',
        isOffline: false,
        isFavorite: false,
        addedAt: now,
        fileCreatedAt: now,
        aiProcessed: false,
      ),
    );
    final visibleIds = videos.map((video) => video.id).toList(growable: false);

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
            child: Center(
              child: SizedBox(
                width: 548,
                height: 240,
                child: Column(
                  children: [
                    for (final video in videos)
                      SizedBox(
                        height: 80,
                        child: VideoGridItem(
                          key: ValueKey('compact-row-${video.id}'),
                          video: video,
                          visibleVideoIds: visibleIds,
                          presentation: CatalogPresentation.list,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('compact-row-1'))),
    );

    await tester.tap(find.byKey(const ValueKey('compact-row-1')));
    await tester.pump();
    expect(container.read(videoSelectionControllerProvider).selectedIds, {1});

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tap(find.byKey(const ValueKey('compact-row-3')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(container.read(videoSelectionControllerProvider).selectedIds, {
      1,
      3,
    });

    await tester.tap(find.byKey(const ValueKey('compact-row-1')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const ValueKey('compact-row-3')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(container.read(videoSelectionControllerProvider).selectedIds, {
      1,
      2,
      3,
    });

    await tester.tap(find.byKey(const ValueKey('video-selection-2')));
    await tester.pump();
    expect(container.read(videoSelectionControllerProvider).selectedIds, {
      1,
      3,
    });
  });

  testWidgets('grid cards expose focus and keyboard selection', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 7, 21);
    final folder = Folder(
      id: 1,
      path: '/Volumes/Catalog',
      alias: 'Catalog',
      isPrivate: false,
      addedAt: now,
    );
    final video = Video(
      id: 1,
      folderId: 1,
      absolutePath: '/Volumes/Catalog/video-1.mp4',
      title: 'Keyboard Video',
      duration: 60,
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
            child: Center(
              child: SizedBox(
                width: 240,
                height: 360,
                child: VideoGridItem(
                  key: const ValueKey('keyboard-grid-card'),
                  video: video,
                  visibleVideoIds: const [1],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('keyboard-grid-card'))),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(container.read(videoSelectionControllerProvider).selectedIds, {1});
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('keyboard-grid-card')),
    );
    expect(semantics.label, contains('Keyboard Video'));
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(semantics.flagsCollection.isFocused, Tristate.isTrue);
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets(
    'home switch preserves first visible Video, selection, and loaded pages',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'paginationSize': 100,
      });
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final folderId = await db
          .into(db.folders)
          .insert(FoldersCompanion.insert(path: '/Volumes/Catalog'));
      for (var index = 0; index < 40; index++) {
        await db
            .into(db.videos)
            .insert(
              VideosCompanion.insert(
                folderId: folderId,
                absolutePath: '/Volumes/Catalog/video-$index.mp4',
                title: 'Video $index',
                addedAt: drift.Value(DateTime(2026, 7, 21, 0, index)),
              ),
            );
      }
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          libraryControllerProvider.overrideWith(_TestLibraryController.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MacosApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final scrollController = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scrollController.jumpTo(920);
      await tester.pumpAndSettle();

      final gridAnchor = _firstVisibleVideo(tester);
      container
          .read(videoSelectionControllerProvider.notifier)
          .setSelected(gridAnchor.id, true);
      final loadedPages = container
          .read(catalogPaginationProvider)
          .requireValue
          .loadedPages;

      await tester.tap(find.byKey(const ValueKey('catalog-presentation-list')));
      await tester.pumpAndSettle();
      final listAnchor = _firstVisibleVideo(tester);
      expect(listAnchor.id, gridAnchor.id);
      expect(listAnchor.localOffset, closeTo(gridAnchor.localOffset, 2));
      expect(container.read(videoSelectionControllerProvider).selectedIds, {
        gridAnchor.id,
      });
      expect(
        container.read(catalogPaginationProvider).requireValue.loadedPages,
        loadedPages,
      );

      await tester.tap(find.byKey(const ValueKey('catalog-presentation-grid')));
      await tester.pumpAndSettle();
      final restoredGridAnchor = _firstVisibleVideo(tester);
      expect(restoredGridAnchor.id, gridAnchor.id);
      expect(
        restoredGridAnchor.localOffset,
        closeTo(gridAnchor.localOffset, 2),
      );

      await tester.tap(find.byKey(const ValueKey('catalog-presentation-list')));
      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('catalog-presentation-list')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  test('plain, toggle, and range selection use one ordered Video list', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final selection = container.read(videoSelectionControllerProvider.notifier);

    selection.selectWithIntent(
      videoId: 2,
      orderedVisibleVideoIds: const [1, 2, 3, 4],
      isRangeSelection: false,
      isToggleSelection: false,
    );
    expect(container.read(videoSelectionControllerProvider).selectedIds, {2});

    selection.selectWithIntent(
      videoId: 4,
      orderedVisibleVideoIds: const [1, 2, 3, 4],
      isRangeSelection: true,
      isToggleSelection: false,
    );
    expect(container.read(videoSelectionControllerProvider).selectedIds, {
      2,
      3,
      4,
    });

    selection.selectWithIntent(
      videoId: 3,
      orderedVisibleVideoIds: const [1, 2, 3, 4],
      isRangeSelection: false,
      isToggleSelection: true,
    );
    expect(container.read(videoSelectionControllerProvider).selectedIds, {
      2,
      4,
    });
  });
}

Iterable<String> _tooltipMessages(WidgetTester tester) => tester
    .widgetList<MacosTooltip>(find.byType(MacosTooltip))
    .map((tooltip) => tooltip.message);

({int id, double localOffset}) _firstVisibleVideo(WidgetTester tester) {
  final viewport = tester.getRect(find.byType(CustomScrollView));
  final visible = <({int id, Rect rect})>[];
  for (final item in tester.widgetList<VideoGridItem>(
    find.byType(VideoGridItem),
  )) {
    final finder = find.byWidgetPredicate(
      (widget) => widget is VideoGridItem && widget.video.id == item.video.id,
    );
    final rect = tester.getRect(finder);
    if (rect.bottom > viewport.top && rect.top < viewport.bottom) {
      visible.add((id: item.video.id, rect: rect));
    }
  }
  visible.sort((left, right) {
    final vertical = left.rect.top.compareTo(right.rect.top);
    return vertical != 0 ? vertical : left.rect.left.compareTo(right.rect.left);
  });
  final first = visible.first;
  return (id: first.id, localOffset: viewport.top - first.rect.top);
}

class _TestSettings extends Settings {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _TestLibraryController extends LibraryController {
  @override
  Future<void> build() async {}
}

class _TestFoldersDao extends FoldersDao {
  _TestFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Future<List<Folder>> getAllFolders() async => _folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);
}

class _RecordingVideosDao extends VideosDao {
  _RecordingVideosDao(super.db);

  final List<({int id, bool current})> favoriteToggles = [];

  @override
  Future<void> toggleFavorite(int id, bool currentStatus) async {
    favoriteToggles.add((id: id, current: currentStatus));
  }
}

class _TestTagsDao extends TagsDao {
  _TestTagsDao(super.db, {this.tags = const []});

  final List<int> clearedVideoIds = [];
  final List<({int videoId, String tag})> insertedTags = [];
  final List<Tag> tags;

  @override
  Stream<List<Tag>> watchTagsForVideo(int videoId) => Stream.value(tags);

  @override
  Stream<List<String>> watchAllUniqueTags({List<int>? folderIds}) =>
      Stream.value(const []);

  @override
  Future<void> deleteAllTagsForVideo(int videoId) async {
    clearedVideoIds.add(videoId);
  }

  @override
  Future<int> insertTag(TagsCompanion tag) async {
    insertedTags.add((videoId: tag.videoId.value, tag: tag.tagText.value));
    return insertedTags.length;
  }
}

class _RecordingPlaybackController extends PlaybackController {
  _RecordingPlaybackController({
    required super.foldersDao,
    required super.videosDao,
  }) : super(
         libraryAccessService: LibraryAccessService(),
         playbackService: PlaybackService(),
         naturalLanguageService: NaturalLanguageService(),
       );

  final List<int> playedVideoIds = [];
  final List<int> revealedVideoIds = [];

  @override
  Future<bool> play(Video video) async {
    playedVideoIds.add(video.id);
    return true;
  }

  @override
  Future<void> revealInFinder(Video video) async {
    revealedVideoIds.add(video.id);
  }
}

class _TestVideoSummariesDao extends VideoSummariesDao {
  _TestVideoSummariesDao(super.db);

  @override
  Stream<VideoSummary?> watchSummaryForVideo(int videoId) => Stream.value(null);
}
