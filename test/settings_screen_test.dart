import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/managed_library_service.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/stats_provider.dart';
import 'package:movie_manager/services/library_access_service.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:movie_manager/ui/screens/settings_screen.dart';
import 'package:movie_manager/ui/widgets/private_library_auto_lock_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/library_access_test_adapter.dart';

void main() {
  testWidgets('settings labels libraries and saves inline name edits', (
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
      Folder(
        id: 2,
        path: '/Volumes/Archive/Movies',
        alias: 'Archive Movies',
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

    expect(find.text('Libraries'), findsOneWidget);
    expect(find.text('Transcription & Summarization'), findsOneWidget);
    expect(find.text('Transcribe'), findsNothing);
    expect(find.text('Summarization'), findsNothing);
    expect(
      find.byKey(const ValueKey('show-private-libraries-in-filter-checkbox')),
      findsOneWidget,
    );
    expect(find.byType(PrivateLibraryAutoLockControl), findsOneWidget);
    expect(
      find.byKey(const ValueKey('empty-folder-cleanup-checkbox')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('empty-folder-cleanup-interval-days-field')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(
              const ValueKey('show-private-libraries-in-filter-checkbox'),
            ),
          )
          .dy,
      greaterThan(
        tester
            .getBottomLeft(
              find.byKey(const ValueKey('settings-library-folder-list')),
            )
            .dy,
      ),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(
              const ValueKey('show-private-libraries-in-filter-checkbox'),
            ),
          )
          .dy,
      lessThan(
        tester.getTopLeft(find.byType(PrivateLibraryAutoLockControl)).dy,
      ),
    );
    expect(
      tester
              .getRect(
                find.byKey(
                  const ValueKey('show-private-libraries-in-filter-checkbox'),
                ),
              )
              .left -
          tester
              .getRect(
                find.text('Show private libraries in the Library filter'),
              )
              .right,
      lessThanOrEqualTo(6),
    );
    expect(find.text('Library Folders'), findsNothing);
    expect(find.text('Show Offline Media'), findsNothing);
    expect(find.text('/Volumes/Media/Movies'), findsOneWidget);
    expect(
      (tester.getCenter(find.byKey(const ValueKey('library-name-field-1'))).dy -
              tester.getCenter(find.text('/Volumes/Media/Movies')).dy)
          .abs(),
      lessThan(12),
    );

    await tester.tap(find.byKey(const ValueKey('library-name-field-1')));
    await tester.enterText(
      find.byKey(const ValueKey('library-name-field-1')),
      '  Primary Movies  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(foldersDao.nameUpdates, [(1, 'Primary Movies')]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'settings persists private-filter visibility without authentication',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final auth = _FakePrivateLibraryAuthService(result: true);
      final container = ProviderContainer(
        overrides: [
          foldersDaoProvider.overrideWithValue(_TestFoldersDao(db, [])),
          privateLibraryAuthServiceProvider.overrideWithValue(auth),
          dataFolderSizeProvider.overrideWith((ref) async => 0),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MacosApp(home: MacosWindow(child: SettingsScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        container
            .read(settingsProvider)
            .requireValue
            .privateLibraryAccess
            .showPrivateLibrariesInFilter,
        isFalse,
      );

      await tester.tap(
        find.byKey(const ValueKey('show-private-libraries-in-filter-checkbox')),
      );
      await tester.pumpAndSettle();

      expect(
        container
            .read(settingsProvider)
            .requireValue
            .privateLibraryAccess
            .showPrivateLibrariesInFilter,
        isTrue,
      );
      expect(auth.attempts, 0);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('showPrivateLibrariesInFilter'), isTrue);
    },
  );

  testWidgets('settings add folder button adds selected library folder', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync(
      'settings_add_library_test_',
    );
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });
    final selectedDirectory = Directory('${root.path}/Settings Library');
    selectedDirectory.createSync();

    final filePicker = _FakeFilePicker(selectedDirectory.path);
    FilePicker.platform = filePicker;
    addTearDown(FilePickerIO.registerWith);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final foldersDao = _TestFoldersDao(db, []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          foldersDaoProvider.overrideWithValue(foldersDao),
          settingsProvider.overrideWith(_TestSettings.new),
          dataFolderSizeProvider.overrideWith((ref) async => 0),
          libraryAccessServiceProvider.overrideWithValue(
            LibraryAccessService(adapter: AlwaysAllowedLibraryAccessAdapter()),
          ),
        ],
        child: const MacosApp(home: MacosWindow(child: SettingsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Libraries'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is MacosTooltip && widget.message == 'Add Folder',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('settings-add-library-folder-button')),
    );
    await tester.pump();

    final folder = await tester.runAsync(
      () => _waitForFolder(foldersDao, selectedDirectory.path),
    );
    await tester.pump();

    expect(filePicker.directoryPickCount, 1);
    expect(folder, isNotNull);
    expect(folder!.path, selectedDirectory.path);
    expect(folder.alias, 'Settings Library');
    expect(folder.securityScopedBookmark, 'bookmark:${selectedDirectory.path}');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('settings presents the managed Library add outcome', (
    tester,
  ) async {
    final filePicker = _FakeFilePicker('/Volumes/Selected Library');
    FilePicker.platform = filePicker;
    addTearDown(FilePickerIO.registerWith);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(_TestFoldersDao(db, [])),
          libraryControllerProvider.overrideWith(_ResultLibraryController.new),
          settingsProvider.overrideWith(_TestSettings.new),
          dataFolderSizeProvider.overrideWith((ref) async => 0),
        ],
        child: const MacosApp(home: MacosWindow(child: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings-add-library-folder-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Library added.'), findsOneWidget);
    expect(filePicker.directoryPickCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('settings rejects blank and duplicate inline library names', (
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
      Folder(
        id: 2,
        path: '/Volumes/Archive/Shows',
        alias: 'Shows',
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

    await tester.enterText(
      find.byKey(const ValueKey('library-name-field-2')),
      ' movies ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Library name must be unique.'), findsOneWidget);
    expect(foldersDao.nameUpdates, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('library-name-field-2')),
      ' ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Library name is required.'), findsOneWidget);
    expect(foldersDao.nameUpdates, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

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
  final List<(int, String)> nameUpdates = [];

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);

  @override
  Future<List<Folder>> getAllFolders() async => List.unmodifiable(_folders);

  @override
  Future<Folder?> getFolderById(int id) async {
    for (final folder in _folders) {
      if (folder.id == id) {
        return folder;
      }
    }
    return null;
  }

  @override
  Future<int> insertFolder(FoldersCompanion folder) async {
    final path = folder.path.value;
    for (final existing in _folders) {
      if (existing.path == path) {
        return 0;
      }
    }

    var id = folder.id.present ? folder.id.value : 1;
    if (!folder.id.present) {
      for (final existing in _folders) {
        if (existing.id >= id) {
          id = existing.id + 1;
        }
      }
    }

    _folders.add(
      Folder(
        id: id,
        path: path,
        alias: folder.alias.present ? folder.alias.value : null,
        securityScopedBookmark: folder.securityScopedBookmark.present
            ? folder.securityScopedBookmark.value
            : null,
        isPrivate: folder.isPrivate.present ? folder.isPrivate.value : false,
        addedAt: folder.addedAt.present ? folder.addedAt.value : DateTime.now(),
      ),
    );
    return id;
  }

  @override
  Future<void> updateFolderName(int id, String name) async {
    nameUpdates.add((id, name));
  }

  @override
  Future<void> updateFolderPrivacy(int id, bool isPrivate) async {
    privacyUpdates.add((id, isPrivate));
  }

  @override
  Future<void> updateFolderBookmark(int id, String? bookmark) async {
    for (var index = 0; index < _folders.length; index += 1) {
      final folder = _folders[index];
      if (folder.id == id) {
        _folders[index] = Folder(
          id: folder.id,
          path: folder.path,
          alias: folder.alias,
          securityScopedBookmark: bookmark,
          isPrivate: folder.isPrivate,
          addedAt: folder.addedAt,
        );
        return;
      }
    }
  }
}

class _TestSettings extends Settings {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _ResultLibraryController extends LibraryController {
  @override
  Future<void> build() async {}

  @override
  Future<LibraryAddFlowResult> addFolder(String path) async {
    return const LibraryAddFlowResult(
      status: LibraryAddFlowStatus.completed,
      managedLibraryResult: ManagedLibraryAddResult(
        status: ManagedLibraryAddStatus.created,
      ),
    );
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

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.selectedDirectory);

  final String? selectedDirectory;
  int directoryPickCount = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    directoryPickCount += 1;
    return selectedDirectory;
  }
}

Future<Folder> _waitForFolder(FoldersDao foldersDao, String path) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    final folders = await foldersDao.getAllFolders();
    for (final folder in folders) {
      if (folder.path == path) {
        return folder;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Expected folder $path to be added.');
}
