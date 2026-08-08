import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:movie_manager/ui/widgets/library_filter_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('library filter hides private libraries by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(db, _folders()),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(
            _FakePrivateLibraryAuthService(result: true),
          ),
        ],
        child: const MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [ContentArea(builder: _libraryFilterContentBuilder)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();

    expect(find.text('Public Movies'), findsOneWidget);
    expect(find.text('Private Movies'), findsNothing);
    expect(find.text('Unlock Private Libraries'), findsNothing);
  });

  testWidgets('library filter toggles folders and resets to all visible', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final folders = _folders();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(_StaticFoldersDao(db, folders)),
          privateLibraryAuthServiceProvider.overrideWithValue(
            _FakePrivateLibraryAuthService(result: true),
          ),
        ],
        child: const MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [ContentArea(builder: _libraryFilterContentBuilder)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Libraries: All'), findsOneWidget);

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public Movies'));
    await tester.pumpAndSettle();

    expect(find.text('Libraries: 1'), findsOneWidget);

    await tester.tap(find.text('Libraries: 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All visible libraries'));
    await tester.pumpAndSettle();

    expect(find.text('Libraries: All'), findsOneWidget);
  });

  testWidgets('group selection includes only public libraries', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'showPrivateLibrariesInFilter': true,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 8, 8);
    final container = ProviderContainer(
      overrides: [
        foldersDaoProvider.overrideWithValue(
          _StaticFoldersDao(db, [
            Folder(
              id: 1,
              path: '/Volumes/Public Cinema',
              alias: 'Public Cinema',
              groupName: 'Cinema',
              securityScopedBookmark: 'public-bookmark',
              isPrivate: false,
              addedAt: now,
            ),
            Folder(
              id: 2,
              path: '/Volumes/Private Cinema',
              alias: 'Private Cinema',
              groupName: 'Cinema',
              securityScopedBookmark: 'private-bookmark',
              isPrivate: true,
              addedAt: now,
            ),
          ]),
        ),
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [ContentArea(builder: _libraryFilterContentBuilder)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Public Cinema')).dx,
      greaterThan(tester.getTopLeft(find.text('Cinema')).dx),
    );
    await tester.tap(find.text('Cinema'));
    await tester.pumpAndSettle();

    expect(container.read(selectedLibraryFoldersControllerProvider), {1});
    expect(find.text('Libraries: 1'), findsOneWidget);
  });

  testWidgets('library filter unlocks private libraries before selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'privateLibraryAutoLockMinutes': 10,
      'showPrivateLibrariesInFilter': true,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final auth = _FakePrivateLibraryAuthService(result: true);
    final container = ProviderContainer(
      overrides: [
        foldersDaoProvider.overrideWithValue(_StaticFoldersDao(db, _folders())),
        privateLibraryAuthServiceProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [ContentArea(builder: _libraryFilterContentBuilder)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock Private Libraries'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(auth.attempts, 1);
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );

    await tester.tap(find.text('Libraries: All'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Private Movies').hitTestable().last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Libraries: 1'), findsOneWidget);
    expect(container.read(selectedLibraryFoldersControllerProvider), {2});

    container.read(privateLibraryAccessControllerProvider.notifier).lock();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('library filter manually locks private libraries', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'privateLibraryAutoLockMinutes': 1,
      'showPrivateLibrariesInFilter': true,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        foldersDaoProvider.overrideWithValue(_StaticFoldersDao(db, _folders())),
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [ContentArea(builder: _libraryFilterContentBuilder)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock Private Libraries'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );

    await tester.tap(find.text('Libraries: All'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Lock Private Libraries').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('library filter folder rows expose full path tooltips', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'showPrivateLibrariesInFilter': true,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(db, _folders()),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(
            _FakePrivateLibraryAuthService(result: true),
          ),
        ],
        child: const MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [ContentArea(builder: _libraryFilterContentBuilder)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosTooltip &&
            widget.message == '/Volumes/Public Movies',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MacosTooltip &&
            widget.message == '/Volumes/Private Movies',
      ),
      findsOneWidget,
    );
  });

  testWidgets('library filter lists private folders below unlock action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'showPrivateLibrariesInFilter': true,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 6, 22);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(db, [
              Folder(
                id: 1,
                path: '/Volumes/Public Movies',
                alias: 'Public Movies',
                securityScopedBookmark: 'public-bookmark',
                isPrivate: false,
                addedAt: now,
              ),
              Folder(
                id: 2,
                path: '/Volumes/Archive Private',
                alias: 'Archive Private',
                securityScopedBookmark: 'archive-private-bookmark',
                isPrivate: true,
                addedAt: now,
              ),
              Folder(
                id: 3,
                path: '/Volumes/Zoo Private',
                alias: 'Zoo Private',
                securityScopedBookmark: 'zoo-private-bookmark',
                isPrivate: true,
                addedAt: now,
              ),
            ]),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(
            _FakePrivateLibraryAuthService(result: true),
          ),
        ],
        child: const MacosApp(
          home: MacosWindow(
            child: MacosScaffold(
              children: [ContentArea(builder: _libraryFilterContentBuilder)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();

    final unlockTop = tester
        .getTopLeft(find.text('Unlock Private Libraries'))
        .dy;

    expect(
      tester.getTopLeft(find.text('Public Movies')).dy,
      lessThan(unlockTop),
    );
    expect(
      tester.getTopLeft(find.text('Archive Private')).dy,
      greaterThan(unlockTop),
    );
    expect(
      tester.getTopLeft(find.text('Zoo Private')).dy,
      greaterThan(unlockTop),
    );
  });

  testWidgets(
    'library filter shows descriptive names for duplicate basenames',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime(2026, 6, 22);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            foldersDaoProvider.overrideWithValue(
              _StaticFoldersDao(db, [
                Folder(
                  id: 1,
                  path: '/Volumes/Media/Movies',
                  alias: 'Family Movies',
                  securityScopedBookmark: 'public-bookmark',
                  isPrivate: false,
                  addedAt: now,
                ),
                Folder(
                  id: 2,
                  path: '/Volumes/Archive/Movies',
                  alias: 'Archive Movies',
                  securityScopedBookmark: 'archive-bookmark',
                  isPrivate: false,
                  addedAt: now,
                ),
              ]),
            ),
            privateLibraryAuthServiceProvider.overrideWithValue(
              _FakePrivateLibraryAuthService(result: true),
            ),
          ],
          child: const MacosApp(
            home: MacosWindow(
              child: MacosScaffold(
                children: [ContentArea(builder: _libraryFilterContentBuilder)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Libraries: All'));
      await tester.pumpAndSettle();

      expect(find.text('Family Movies'), findsOneWidget);
      expect(find.text('Archive Movies'), findsOneWidget);
      expect(find.text('Movies'), findsNothing);
    },
  );
}

Widget _libraryFilterContentBuilder(BuildContext context, ScrollController _) {
  return const Center(child: LibraryFilterMenu());
}

List<Folder> _folders() {
  final now = DateTime(2026, 6, 22);
  return [
    Folder(
      id: 1,
      path: '/Volumes/Public Movies',
      alias: 'Public Movies',
      securityScopedBookmark: 'public-bookmark',
      isPrivate: false,
      addedAt: now,
    ),
    Folder(
      id: 2,
      path: '/Volumes/Private Movies',
      alias: 'Private Movies',
      securityScopedBookmark: 'private-bookmark',
      isPrivate: true,
      addedAt: now,
    ),
  ];
}

class _StaticFoldersDao extends FoldersDao {
  _StaticFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);
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
