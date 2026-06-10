import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_craft/icon_craft.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/ui/widgets/bulk_selection_toolbar.dart';

void main() {
  testWidgets('bulk toolbar shows all actions and disables selection actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: BulkSelectionToolbar(
            selectedCount: 0,
            isBusy: false,
            onSelectLoaded: () {},
            onMove: () {},
            onDelete: () {},
            onFavorite: () {},
            onUnfavorite: () {},
            onClearTags: () {},
            onClearSelection: () {},
          ),
        ),
      ),
    );

    expect(find.text('Select Loaded'), findsOneWidget);
    expect(find.text('0 Selected'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Unfavorite'), findsOneWidget);
    expect(find.text('Clear Tags'), findsOneWidget);
    expect(find.text('Clear Selection'), findsOneWidget);

    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Select Loaded'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Move'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Delete'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Clear Tags'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('bulk toolbar labels include action icons', (tester) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: BulkSelectionToolbar(
            selectedCount: 3,
            isBusy: false,
            onSelectLoaded: () {},
            onMove: () {},
            onDelete: () {},
            onFavorite: () {},
            onUnfavorite: () {},
            onClearTags: () {},
            onClearSelection: () {},
          ),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Select Loaded'),
        matching: find.byIcon(CupertinoIcons.check_mark_circled),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Move'),
        matching: find.byIcon(CupertinoIcons.arrow_right_arrow_left),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Delete'),
        matching: find.byIcon(CupertinoIcons.trash),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Favorite'),
        matching: find.byIcon(CupertinoIcons.heart_fill),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Unfavorite'),
        matching: find.byIcon(CupertinoIcons.heart),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Clear Tags'),
        matching: find.byType(IconCraft),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Clear Selection'),
        matching: find.byIcon(CupertinoIcons.clear_circled),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bulk toolbar dispatches selected actions', (tester) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final calls = <String>[];

    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: BulkSelectionToolbar(
            selectedCount: 2,
            isBusy: false,
            onSelectLoaded: () => calls.add('select-loaded'),
            onMove: () => calls.add('move'),
            onDelete: () => calls.add('delete'),
            onFavorite: () => calls.add('favorite'),
            onUnfavorite: () => calls.add('unfavorite'),
            onClearTags: () => calls.add('clear-tags'),
            onClearSelection: () => calls.add('clear-selection'),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(PushButton, 'Select Loaded'));
    await tester.tap(find.widgetWithText(PushButton, 'Move'));
    await tester.tap(find.widgetWithText(PushButton, 'Delete'));
    await tester.tap(find.widgetWithText(PushButton, 'Favorite'));
    await tester.tap(find.widgetWithText(PushButton, 'Unfavorite'));
    await tester.tap(find.widgetWithText(PushButton, 'Clear Tags'));
    await tester.tap(find.widgetWithText(PushButton, 'Clear Selection'));

    expect(calls, [
      'select-loaded',
      'move',
      'delete',
      'favorite',
      'unfavorite',
      'clear-tags',
      'clear-selection',
    ]);
  });
}
