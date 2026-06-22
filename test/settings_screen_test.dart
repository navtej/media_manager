import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/stats_provider.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:movie_manager/ui/screens/settings_screen.dart';

void main() {
  testWidgets('library folder action icons expose explanatory tooltips', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime(2026, 6, 11);
    final folders = [
      Folder(
        id: 1,
        path: '/Volumes/Media/Movies',
        alias: 'Movies',
        securityScopedBookmark: 'bookmark',
        isPrivate: false,
        addedAt: now,
      ),
      Folder(
        id: 2,
        path: '/Volumes/Archive/Shows',
        alias: null,
        securityScopedBookmark: null,
        isPrivate: true,
        addedAt: now,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(_TestFoldersDao(db, folders)),
          settingsProvider.overrideWith(_TestSettings.new),
          dataFolderSizeProvider.overrideWith((ref) async => 0),
        ],
        child: const MacosApp(home: MacosWindow(child: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosTooltip &&
            widget.message ==
                'Removable storage. macOS keeps saved access for this folder; click to refresh or repair it.',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosTooltip &&
            widget.message ==
                'Access repair required. Click to reselect this folder and restore access.',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosTooltip &&
            widget.message ==
                'Remove this folder from the library. Files stay on disk.',
      ),
      findsNWidgets(2),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosTooltip &&
            widget.message ==
                'Public library. Click to require authentication before videos appear.',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosTooltip &&
            widget.message ==
                'Private library. Click to make videos visible by default.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('library folder privacy icon toggles folder privacy', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 6, 22);
    final foldersDao = _TestFoldersDao(db, [
      Folder(
        id: 1,
        path: '/Volumes/Media/Movies',
        alias: 'Movies',
        securityScopedBookmark: 'bookmark',
        isPrivate: false,
        addedAt: now,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(foldersDao),
          settingsProvider.overrideWith(_TestSettings.new),
          dataFolderSizeProvider.overrideWith((ref) async => 0),
        ],
        child: const MacosApp(home: MacosWindow(child: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.lock_open).first);
    await tester.pumpAndSettle();

    expect(foldersDao.privacyUpdates, [(1, true)]);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('private library must authenticate before becoming public', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final auth = _FakePrivateLibraryAuthService(result: true);
    final now = DateTime(2026, 6, 22);
    final foldersDao = _TestFoldersDao(db, [
      Folder(
        id: 1,
        path: '/Volumes/Private Movies',
        alias: 'Private Movies',
        securityScopedBookmark: 'bookmark',
        isPrivate: true,
        addedAt: now,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(foldersDao),
          privateLibraryAuthServiceProvider.overrideWithValue(auth),
          settingsProvider.overrideWith(_TestSettings.new),
          dataFolderSizeProvider.overrideWith((ref) async => 0),
        ],
        child: const MacosApp(home: MacosWindow(child: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.lock).first);
    await tester.pumpAndSettle();

    expect(auth.attempts, 1);
    expect(foldersDao.privacyUpdates, [(1, false)]);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('cancelled authentication keeps private library private', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final auth = _FakePrivateLibraryAuthService(result: false);
    final now = DateTime(2026, 6, 22);
    final foldersDao = _TestFoldersDao(db, [
      Folder(
        id: 1,
        path: '/Volumes/Private Movies',
        alias: 'Private Movies',
        securityScopedBookmark: 'bookmark',
        isPrivate: true,
        addedAt: now,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(foldersDao),
          privateLibraryAuthServiceProvider.overrideWithValue(auth),
          settingsProvider.overrideWith(_TestSettings.new),
          dataFolderSizeProvider.overrideWith((ref) async => 0),
        ],
        child: const MacosApp(home: MacosWindow(child: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.lock).first);
    await tester.pumpAndSettle();

    expect(auth.attempts, 1);
    expect(foldersDao.privacyUpdates, isEmpty);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _TestFoldersDao extends FoldersDao {
  _TestFoldersDao(super.db, this._folders);

  final List<Folder> _folders;
  final List<(int, bool)> privacyUpdates = [];

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);

  @override
  Future<void> updateFolderPrivacy(int id, bool isPrivate) async {
    privacyUpdates.add((id, isPrivate));
  }
}

class _TestSettings extends Settings {
  @override
  Future<Map<String, dynamic>> build() async {
    return <String, dynamic>{
      'scanInterval': 5,
      'batchSize': 4,
      'paginationSize': 50,
      'themeMode': 'system',
      'showOfflineMedia': true,
      'summaryModelPath': '',
      'summaryPreferVttSubtitles': true,
      'summaryApiUrl': '',
      'summaryApiKey': '',
    };
  }
}

class _FakePrivateLibraryAuthService extends PrivateLibraryAuthService {
  _FakePrivateLibraryAuthService({required this.result});

  final bool result;
  int attempts = 0;

  @override
  Future<bool> authenticate() async {
    attempts += 1;
    return result;
  }
}
