import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/ui/screens/home_screen.dart';
import 'package:movie_manager/ui/widgets/library_filter_menu.dart';
import 'package:movie_manager/ui/widgets/macos_preference_checkbox.dart';
import 'package:movie_manager/ui/widgets/show_offline_media_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('control loads and persists the offline-media preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'showOfflineMedia': false,
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MacosApp(
          home: MacosWindow(child: Center(child: ShowOfflineMediaControl())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Show Offline Media'), findsOneWidget);
    expect(_checkbox(tester).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('show-offline-media-checkbox')));
    await tester.pumpAndSettle();

    expect(_checkbox(tester).value, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('showOfflineMedia'), isTrue);
  });

  testWidgets('control does not guess a value while settings are loading', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(_DeferredSettings.new)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MacosApp(
          home: MacosWindow(child: Center(child: ShowOfflineMediaControl())),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('show-offline-media-checkbox')),
      findsNothing,
    );

    final settings =
        container.read(settingsProvider.notifier) as _DeferredSettings;
    settings.complete(showOfflineMedia: false);
    await tester.pumpAndSettle();

    expect(_checkbox(tester).value, isFalse);
  });

  testWidgets('home toolbar places the control after the Libraries menu', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'showOfflineMedia': false,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MacosApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final librariesMenu = find.byType(LibraryFilterMenu);
    final offlineControl = find.byType(ShowOfflineMediaControl);
    expect(librariesMenu, findsOneWidget);
    expect(offlineControl, findsOneWidget);
    expect(find.text('Show Offline Media'), findsOneWidget);

    final menuRect = tester.getRect(librariesMenu);
    final controlRect = tester.getRect(offlineControl);
    expect(controlRect.left, greaterThan(menuRect.right));
    expect((controlRect.center.dy - menuRect.center.dy).abs(), lessThan(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
}

MacosPreferenceCheckbox _checkbox(WidgetTester tester) {
  return tester.widget<MacosPreferenceCheckbox>(
    find.byKey(const ValueKey('show-offline-media-checkbox')),
  );
}

class _DeferredSettings extends Settings {
  final Completer<Map<String, dynamic>> _completer = Completer();

  @override
  Future<Map<String, dynamic>> build() => _completer.future;

  void complete({required bool showOfflineMedia}) {
    _completer.complete(<String, dynamic>{
      'showOfflineMedia': showOfflineMedia,
    });
  }
}
