import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/ui/movie_manager_visual_system.dart';
import 'package:movie_manager/ui/widgets/macos_preference_checkbox.dart';

void main() {
  test('visual vocabulary matches PER-33 contract', () {
    expect(MovieManagerSpacing.values, [4, 8, 12, 16, 24]);
    expect(MovieManagerRadii.control, 6);
    expect(MovieManagerRadii.panel, 8);
    expect(MovieManagerRadii.dialog, 12);
    expect(MovieManagerIconSizes.inline, 14);
    expect(MovieManagerIconSizes.action, 16);
    expect(MovieManagerIconSizes.emphasis, 20);
    expect(MovieManagerControlMetrics.minimumTarget, 28);
    expect(MovieManagerWindowMetrics.minimumContentSize, const Size(800, 600));
    expect(
      MovieManagerWindowMetrics.referenceContentSize,
      const Size(1200, 800),
    );
  });

  test('semantic surfaces define distinct light and dark appearances', () {
    final light = MovieManagerVisuals.surfaceColorFor(Brightness.light);
    final dark = MovieManagerVisuals.surfaceColorFor(Brightness.dark);

    expect(light.computeLuminance(), greaterThan(dark.computeLuminance()));
  });

  testWidgets(
    'shared icon action has tooltip, semantics, target, and keyboard',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MacosApp(
          home: MacosWindow(
            child: Center(
              child: MovieManagerIconButton(
                key: const ValueKey('refresh-library-action'),
                label: 'Refresh Library',
                icon: CupertinoIcons.refresh,
                onPressed: () => calls++,
              ),
            ),
          ),
        ),
      );

      final action = find.byKey(const ValueKey('refresh-library-action'));
      expect(tester.getSize(action), const Size(28, 28));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is MacosTooltip && widget.message == 'Refresh Library',
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(action),
        matchesSemantics(
          label: 'Refresh Library',
          isButton: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
          hasFocusAction: true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(calls, 1);
      expect(
        tester.getSemantics(action),
        matchesSemantics(
          label: 'Refresh Library',
          isButton: true,
          isFocusable: true,
          isFocused: true,
          hasEnabledState: true,
          isEnabled: true,
          hasFocusAction: true,
        ),
      );
    },
  );

  testWidgets('preference checkbox uses a focusable 28 px target', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: StatefulBuilder(
            builder: (context, setState) => Center(
              child: MacosPreferenceCheckbox(
                key: const ValueKey('preference-checkbox'),
                value: value,
                semanticLabel: 'Show Offline Media',
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );

    final checkbox = find.byKey(const ValueKey('preference-checkbox'));
    expect(tester.getSize(checkbox), const Size(28, 28));
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(
        label: 'Show Offline Media',
        isButton: true,
        isChecked: false,
        hasCheckedState: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasFocusAction: true,
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(value, isTrue);
    expect(
      tester.getSemantics(checkbox),
      matchesSemantics(
        label: 'Show Offline Media',
        isButton: true,
        isChecked: true,
        hasCheckedState: true,
        isFocusable: true,
        isFocused: true,
        hasEnabledState: true,
        isEnabled: true,
        hasFocusAction: true,
      ),
    );
  });

  testWidgets('state message pairs error text with icon and retry action', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: MovieManagerStateMessage(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: 'Couldn’t load Videos',
            message: 'Check the library and try again.',
            actionLabel: 'Retry',
            onAction: () => retries++,
          ),
        ),
      ),
    );

    expect(find.byType(MacosIcon), findsOneWidget);
    expect(find.text('Couldn’t load Videos'), findsOneWidget);
    expect(find.text('Check the library and try again.'), findsOneWidget);
    await tester.tap(find.widgetWithText(PushButton, 'Retry'));
    expect(retries, 1);
  });
}
