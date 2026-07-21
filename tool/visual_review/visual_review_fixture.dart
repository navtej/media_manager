import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/stats_provider.dart';
import 'package:movie_manager/logic/video_selection_controller.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/ui/screens/home_screen.dart';
import 'package:movie_manager/ui/screens/settings_screen.dart';
import 'package:movie_manager/ui/widgets/video_move_dialog.dart';

enum VisualReviewScreen { grid, selection, settings, move }

enum VisualReviewTheme { light, dark }

final class VisualReviewViewport {
  const VisualReviewViewport(this.slug, this.size);

  static const reference = VisualReviewViewport('1200x800', Size(1200, 800));
  static const minimum = VisualReviewViewport('800x600', Size(800, 600));
  static const values = <VisualReviewViewport>[reference, minimum];

  final String slug;
  final Size size;
}

final class VisualReviewCaptureCase {
  const VisualReviewCaptureCase({
    required this.screen,
    required this.theme,
    required this.viewport,
  });

  final VisualReviewScreen screen;
  final VisualReviewTheme theme;
  final VisualReviewViewport viewport;

  String get fileName => '${screen.name}-${theme.name}-${viewport.slug}.png';
}

final class VisualReviewCaptureSelection {
  const VisualReviewCaptureSelection(this.cases);

  factory VisualReviewCaptureSelection.parse({
    required String screen,
    required String theme,
    required String size,
  }) {
    final screens = _parseValues(
      key: 'VISUAL_REVIEW_SCREEN',
      value: screen,
      values: VisualReviewScreen.values,
      slug: (value) => value.name,
    );
    final themes = _parseValues(
      key: 'VISUAL_REVIEW_THEME',
      value: theme,
      values: VisualReviewTheme.values,
      slug: (value) => value.name,
    );
    final viewports = _parseValues(
      key: 'VISUAL_REVIEW_SIZE',
      value: size,
      values: VisualReviewViewport.values,
      slug: (value) => value.slug,
    );

    return VisualReviewCaptureSelection([
      for (final viewport in viewports)
        for (final selectedTheme in themes)
          for (final selectedScreen in screens)
            VisualReviewCaptureCase(
              screen: selectedScreen,
              theme: selectedTheme,
              viewport: viewport,
            ),
    ]);
  }

  final List<VisualReviewCaptureCase> cases;
}

List<T> _parseValues<T>({
  required String key,
  required String value,
  required List<T> values,
  required String Function(T value) slug,
}) {
  if (value == 'all') return values;
  for (final candidate in values) {
    if (slug(candidate) == value) return [candidate];
  }
  throw ArgumentError.value(
    value,
    key,
    'Expected all or one of ${values.map(slug).join(', ')}',
  );
}

final class VisualReviewFixture {
  static const _needsRepairPath = '/VisualReviewFixture/NeedsRepair';
  static const _primaryPath = '/VisualReviewFixture/Primary';
  static const _archivePath = '/Volumes/VisualReviewFixtureArchive';
  static const _privatePath = '/VisualReviewFixture/Private';

  VisualReviewFixture._({
    required this.database,
    required this.folders,
    required this.videos,
    required this.selectionVideoIds,
    required this.moveVideoId,
  });

  final AppDatabase database;
  final List<Folder> folders;
  final List<Video> videos;
  final List<int> selectionVideoIds;
  final int moveVideoId;

  static Future<VisualReviewFixture> create() async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final addedAt = DateTime.utc(2026, 7, 21, 8);
    final folderIds = <int>[];
    for (final folder in <FoldersCompanion>[
      FoldersCompanion.insert(
        path: _needsRepairPath,
        alias: const drift.Value('Needs Access Repair'),
        addedAt: drift.Value(addedAt),
      ),
      FoldersCompanion.insert(
        path: _primaryPath,
        alias: const drift.Value('Studio Library'),
        securityScopedBookmark: const drift.Value('fixture-primary'),
        addedAt: drift.Value(addedAt.add(const Duration(minutes: 1))),
      ),
      FoldersCompanion.insert(
        path: _archivePath,
        alias: const drift.Value('Archive Library'),
        securityScopedBookmark: const drift.Value('fixture-archive'),
        addedAt: drift.Value(addedAt.add(const Duration(minutes: 2))),
      ),
      FoldersCompanion.insert(
        path: _privatePath,
        alias: const drift.Value('Private Drafts'),
        securityScopedBookmark: const drift.Value('fixture-private'),
        isPrivate: const drift.Value(true),
        addedAt: drift.Value(addedAt.add(const Duration(minutes: 3))),
      ),
    ]) {
      folderIds.add(await database.foldersDao.insertFolder(folder));
    }

    final specifications = <_FixtureVideo>[
      _FixtureVideo(folderIds[1], 'Alpine Field Notes', 3723, 734003200, {
        'documentary',
        'nature',
      }),
      _FixtureVideo(folderIds[1], 'City After Rain', 542, 188743680, {
        'city',
        'night',
      }, favorite: true),
      _FixtureVideo(folderIds[1], 'Workshop Assembly', 1280, 419430400, {
        'education',
        'workshop',
      }),
      _FixtureVideo(folderIds[2], 'Archive Interview', 2460, 1073741824, {
        'archive',
        'interview',
      }, offline: true),
      _FixtureVideo(folderIds[2], 'Night Transit Study', 915, 314572800, {
        'city',
        'transit',
      }),
      _FixtureVideo(folderIds[3], 'Confidential Prototype', 305, 83886080, {
        'draft',
        'prototype',
      }),
      _FixtureVideo(folderIds[3], 'Unreleased Sequence', 688, 157286400, {
        'draft',
        'sequence',
      }, offline: true),
      _FixtureVideo(folderIds[0], 'Access Recovery Sample', 95, 25165824, {
        'error-state',
        'recovery',
      }),
    ];

    for (var index = 0; index < specifications.length; index += 1) {
      final specification = specifications[index];
      final path = _folderPath(folderIds, specification.folderId);
      final videoId = await database.videosDao.insertVideo(
        VideosCompanion.insert(
          folderId: specification.folderId,
          absolutePath: '$path/video-${index + 1}.mp4',
          title: specification.title,
          duration: drift.Value(specification.durationSeconds),
          size: drift.Value(specification.sizeBytes),
          metadataJson: const drift.Value(
            '{"format":{"format_long_name":"Fixture MPEG-4"}}',
          ),
          isOffline: drift.Value(specification.offline),
          isFavorite: drift.Value(specification.favorite),
          addedAt: drift.Value(addedAt.add(Duration(minutes: 10 + index))),
          fileCreatedAt: drift.Value(
            addedAt.subtract(Duration(days: specifications.length - index)),
          ),
        ),
      );
      await database.tagsDao.insertTagsBatch([
        for (final tag in specification.tags)
          TagsCompanion.insert(videoId: videoId, tagText: tag),
      ]);
    }

    return VisualReviewFixture._(
      database: database,
      folders: await database.foldersDao.getAllFolders(),
      videos: await database.videosDao.getAllVideos(),
      selectionVideoIds: const [1, 2, 4],
      moveVideoId: 1,
    );
  }

  static String _folderPath(List<int> folderIds, int folderId) {
    final index = folderIds.indexOf(folderId);
    return const [
      _needsRepairPath,
      _primaryPath,
      _archivePath,
      _privatePath,
    ][index];
  }

  ProviderContainer containerFor(VisualReviewCaptureCase capture) {
    final presentation = capture.screen == VisualReviewScreen.selection
        ? CatalogPresentation.list
        : CatalogPresentation.grid;
    final settings = AppSettings.defaults.copyWith(
      catalogBrowsing: CatalogBrowsingConfiguration.resolve(
        paginationSize: 50,
        showOfflineMedia: true,
        presentationValue: presentation.value,
      ),
      appearance: AppearanceConfiguration.resolve(
        themeMode: capture.theme.name,
      ),
    );
    return ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        libraryControllerProvider.overrideWith(_FixtureLibraryController.new),
        settingsProvider.overrideWith(() => _FixtureSettings(settings)),
        dataFolderSizeProvider.overrideWith((ref) async => 64 * 1024 * 1024),
        libraryAccessServiceProvider.overrideWithValue(
          LibraryAccessService(adapter: _FixtureLibraryAccessAdapter()),
        ),
      ],
    );
  }

  Future<void> dispose() => database.close();
}

final class _FixtureVideo {
  const _FixtureVideo(
    this.folderId,
    this.title,
    this.durationSeconds,
    this.sizeBytes,
    this.tags, {
    this.offline = false,
    this.favorite = false,
  });

  final int folderId;
  final String title;
  final int durationSeconds;
  final int sizeBytes;
  final Set<String> tags;
  final bool offline;
  final bool favorite;
}

final class _FixtureSettings extends Settings {
  _FixtureSettings(this.settings);

  final AppSettings settings;

  @override
  Future<AppSettings> build() async => settings;
}

final class _FixtureLibraryController extends LibraryController {
  @override
  Future<void> build() async {}
}

final class _FixtureLibraryAccessAdapter implements LibraryAccessAdapter {
  @override
  Future<String?> createBookmark(String path) async => 'fixture-bookmark';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async => true;

  @override
  Future<void> stopAccessing(String path) async {}
}

final _captureBoundaryKey = GlobalKey();
const _accentColorChannel = MethodChannel('appkit_ui_element_colors');

Future<File> captureVisualReviewCase({
  required WidgetTester tester,
  required VisualReviewCaptureCase capture,
  required Directory outputDirectory,
}) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        _accentColorChannel,
        (call) async => call.method == 'getColorComponents'
            ? <String, double>{'hueComponent': 0.6085324903200698}
            : null,
      );
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(capture.viewport.size);

  final fixture = await VisualReviewFixture.create();
  final container = fixture.containerFor(capture);
  try {
    if (capture.screen == VisualReviewScreen.selection) {
      await container
          .read(videoSelectionControllerProvider.notifier)
          .selectLoaded(fixture.selectionVideoIds);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MacosApp(
          theme: MacosThemeData.light(),
          darkTheme: MacosThemeData.dark(),
          themeMode: capture.theme == VisualReviewTheme.light
              ? ThemeMode.light
              : ThemeMode.dark,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => RepaintBoundary(
            key: _captureBoundaryKey,
            child: child ?? const SizedBox.shrink(),
          ),
          home: switch (capture.screen) {
            VisualReviewScreen.grid ||
            VisualReviewScreen.selection => const HomeScreen(),
            VisualReviewScreen.settings => const SettingsScreen(),
            VisualReviewScreen.move => _MoveCaptureHost(
              selectedVideoIds: [fixture.moveVideoId],
            ),
          },
        ),
      ),
    );
    await _pumpUntilReady(tester, capture.screen);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureBoundaryKey),
    );
    final file = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('Could not encode fixture image.');
        await outputDirectory.create(recursive: true);
        final output = File('${outputDirectory.path}/${capture.fileName}');
        await output.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        return output;
      } finally {
        image.dispose();
      }
    });
    if (file == null) throw StateError('Could not write fixture image.');
    return file;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    for (var flush = 0; flush < 5; flush += 1) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.runAsync(fixture.dispose);
  }
}

Future<void> _pumpUntilReady(
  WidgetTester tester,
  VisualReviewScreen screen,
) async {
  final ready = switch (screen) {
    VisualReviewScreen.grid ||
    VisualReviewScreen.selection => find.text('Access Recovery Sample'),
    VisualReviewScreen.settings => find.text('Access repair required'),
    VisualReviewScreen.move => find.text(libraryAccessRepairMessage),
  };
  for (var attempt = 0; attempt < 60; attempt += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final exception = tester.takeException();
    if (exception != null) throw exception;
    if (ready.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      final finalException = tester.takeException();
      if (finalException != null) throw finalException;
      return;
    }
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .take(80)
      .join(' | ');
  throw StateError(
    'Visual review state ${screen.name} did not become ready. '
    'Visible text: $visibleText',
  );
}

final class _MoveCaptureHost extends ConsumerStatefulWidget {
  const _MoveCaptureHost({required this.selectedVideoIds});

  final List<int> selectedVideoIds;

  @override
  ConsumerState<_MoveCaptureHost> createState() => _MoveCaptureHostState();
}

final class _MoveCaptureHostState extends ConsumerState<_MoveCaptureHost> {
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    if (!_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          showVideoMoveDialog(
            context: context,
            ref: ref,
            selectedVideoIds: widget.selectedVideoIds,
          ),
        );
      });
    }
    return const HomeScreen();
  }
}
