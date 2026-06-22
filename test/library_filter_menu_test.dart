import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:movie_manager/ui/widgets/library_filter_menu.dart';

void main() {
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

  testWidgets('library filter unlocks private libraries before selection', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final auth = _FakePrivateLibraryAuthService(result: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foldersDaoProvider.overrideWithValue(
            _StaticFoldersDao(db, _folders()),
          ),
          privateLibraryAuthServiceProvider.overrideWithValue(auth),
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
    await tester.tap(find.text('Unlock Private Libraries'));
    await tester.pumpAndSettle();

    expect(auth.attempts, 1);

    await tester.tap(find.text('Libraries: All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private Movies'));
    await tester.pumpAndSettle();

    expect(find.text('Libraries: 1'), findsOneWidget);
  });

  testWidgets('library filter folder rows expose full path tooltips', (
    tester,
  ) async {
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
