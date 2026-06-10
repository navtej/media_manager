import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/stats_provider.dart';
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
        addedAt: now,
      ),
      Folder(
        id: 2,
        path: '/Volumes/Archive/Shows',
        alias: null,
        securityScopedBookmark: null,
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

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _TestFoldersDao extends FoldersDao {
  _TestFoldersDao(super.db, this._folders);

  final List<Folder> _folders;

  @override
  Stream<List<Folder>> watchAllFolders() => Stream.value(_folders);
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
