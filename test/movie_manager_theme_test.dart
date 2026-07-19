import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MovieManagerApp reacts to typed appearance configuration', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        libraryControllerProvider.overrideWith(_TestLibraryController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MovieManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<MacosApp>(find.byType(MacosApp)).themeMode,
      ThemeMode.system,
    );

    await container
        .read(settingsProvider.notifier)
        .updateTheme(AppearanceThemeMode.dark);
    await tester.pump();

    expect(
      tester.widget<MacosApp>(find.byType(MacosApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _TestLibraryController extends LibraryController {
  @override
  Future<void> build() async {}
}
