import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/ui/widgets/private_library_auto_lock_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('control shows the default and commits on Enter', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      const ProviderScope(
        child: MacosApp(
          home: MacosWindow(
            child: Center(child: PrivateLibraryAutoLockControl()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey('private-library-auto-lock-minutes-field'),
    );
    expect(field, findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    await tester.enterText(field, '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt(privateLibraryAutoLockMinutesPreferenceKey), 25);
  });

  testWidgets('control commits a valid value when focus leaves the field', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      const ProviderScope(
        child: MacosApp(
          home: MacosWindow(
            child: Column(
              children: [
                PrivateLibraryAutoLockControl(),
                MacosTextField(key: ValueKey('other-field')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(
      const ValueKey('private-library-auto-lock-minutes-field'),
    );
    await tester.enterText(field, '30');
    await tester.tap(find.byKey(const ValueKey('other-field')));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getInt(privateLibraryAutoLockMinutesPreferenceKey), 30);
  });

  for (final invalidValue in <String>['', '0', '121']) {
    testWidgets(
      'control rejects ${invalidValue.isEmpty ? 'an empty value' : invalidValue}',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          privateLibraryAutoLockMinutesPreferenceKey: 20,
        });

        await tester.pumpWidget(
          const ProviderScope(
            child: MacosApp(
              home: MacosWindow(
                child: Center(child: PrivateLibraryAutoLockControl()),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final field = find.byKey(
          const ValueKey('private-library-auto-lock-minutes-field'),
        );
        await tester.enterText(field, invalidValue);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(
          find.text(privateLibraryAutoLockValidationMessage),
          findsOneWidget,
        );
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getInt(privateLibraryAutoLockMinutesPreferenceKey),
          20,
        );
      },
    );
  }
}
