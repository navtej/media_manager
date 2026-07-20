import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/ui/widgets/empty_folder_cleanup_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('control shows defaults and persists toggle and interval', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      const ProviderScope(
        child: MacosApp(home: MacosWindow(child: EmptyFolderCleanupControl())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('empty-folder-cleanup-checkbox')),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(
      const ValueKey('empty-folder-cleanup-interval-days-field'),
    );
    await tester.enterText(field, '30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('emptyFolderCleanupEnabled'), isFalse);
    expect(preferences.getInt('emptyFolderCleanupIntervalDays'), 30);
  });

  for (final invalidValue in <String>['', 'not-a-number', '0', '-1', '91']) {
    testWidgets('control rejects "$invalidValue" without persistence', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'emptyFolderCleanupEnabled': true,
        'emptyFolderCleanupIntervalDays': 14,
      });
      await tester.pumpWidget(
        const ProviderScope(
          child: MacosApp(
            home: MacosWindow(child: EmptyFolderCleanupControl()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byKey(
        const ValueKey('empty-folder-cleanup-interval-days-field'),
      );
      await tester.enterText(field, invalidValue);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text(emptyFolderCleanupValidationMessage), findsOneWidget);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('emptyFolderCleanupIntervalDays'), 14);
    });
  }
}
