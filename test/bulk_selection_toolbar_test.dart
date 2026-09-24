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
            onCopyYoutubeUrls: () {},
            onPlay: () {},
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

    expect(find.text('Loaded'), findsOneWidget);
    expect(find.text('Select Loaded'), findsNothing);
    expect(find.byKey(const ValueKey('bulk-selection-group')), findsOneWidget);
    expect(find.text('Selection'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bulk-selection-group')),
        matching: find.text('Loaded'),
      ),
      findsOneWidget,
    );
    expect(find.text('0 Selected'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Unfavorite'), findsOneWidget);
    expect(find.text('Clear Tags'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Show Selected'), findsOneWidget);

    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Play'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Play'))
          .secondary,
      isTrue,
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Loaded'))
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
          .widget<PushButton>(find.widgetWithText(PushButton, 'Move'))
          .secondary,
      isTrue,
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
            onCopyYoutubeUrls: () {},
            onPlay: () {},
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
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Play'))
          .secondary,
      isFalse,
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Move'))
          .secondary,
      isTrue,
    );

    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Play'),
        matching: find.byIcon(CupertinoIcons.play_fill),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(PushButton, 'Loaded'),
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
        of: find.widgetWithText(PushButton, 'Clear'),
        matching: find.byIcon(CupertinoIcons.clear_circled),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bulk toolbar hides YouTube copying unless it is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: BulkSelectionToolbar(
            selectedCount: 1,
            isBusy: false,
            onSelectLoaded: () {},
            onPlay: () {},
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

    expect(find.text('Copy YouTube URLs'), findsNothing);
    expect(
      find.byKey(const ValueKey('bulk-copy-youtube-urls-button')),
      findsNothing,
    );
  });

  testWidgets('bulk toolbar toggles selected-only view', (tester) async {
    var toggles = 0;
    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: BulkSelectionToolbar(
            selectedCount: 1,
            isBusy: false,
            onSelectLoaded: () {},
            onToggleShowSelectedOnly: () => toggles += 1,
            onPlay: () {},
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

    expect(find.text('Show Selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bulk-show-selected-button')));
    expect(toggles, 1);
  });

  testWidgets('bulk toolbar dispatches selected actions', (tester) async {
    tester.view.physicalSize = const Size(2400, 600);
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
            onCopyYoutubeUrls: () => calls.add('copy-youtube-urls'),
            onPlay: () => calls.add('play'),
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

    await tester.tap(find.widgetWithText(PushButton, 'Loaded'));
    await tester.tap(find.widgetWithText(PushButton, 'Play'));
    await tester.tap(find.widgetWithText(PushButton, 'Move'));
    await tester.tap(find.widgetWithText(PushButton, 'Delete'));
    await tester.tap(find.widgetWithText(PushButton, 'Favorite'));
    await tester.tap(find.widgetWithText(PushButton, 'Unfavorite'));
    await tester.tap(find.widgetWithText(PushButton, 'Clear Tags'));
    await tester.tap(find.widgetWithText(PushButton, 'Clear'));
    await tester.tap(find.widgetWithText(PushButton, 'Copy YouTube URLs'));

    expect(calls, [
      'select-loaded',
      'play',
      'move',
      'delete',
      'favorite',
      'unfavorite',
      'clear-tags',
      'clear-selection',
      'copy-youtube-urls',
    ]);
  });

  testWidgets('bulk toolbar selects a bounded random count and copies URLs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final randomCounts = <int>[];
    var copyCalls = 0;

    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: BulkSelectionToolbar(
            selectedCount: 2,
            isBusy: false,
            maxLoadedVideoCount: 5,
            onSelectLoaded: () {},
            onSelectRandom: randomCounts.add,
            onCopyYoutubeUrls: () => copyCalls++,
            onPlay: () {},
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

    expect(find.text('Selection'), findsOneWidget);
    expect(find.text('Loaded'), findsOneWidget);
    expect(find.text('Select Loaded'), findsNothing);
    expect(
      find.byKey(const ValueKey('bulk-random-count-field')),
      findsOneWidget,
    );
    expect(find.text('Random'), findsOneWidget);
    expect(find.text('Copy YouTube URLs'), findsOneWidget);
    expect(
      tester
          .widget<MacosTextField>(
            find.byKey(const ValueKey('bulk-random-count-field')),
          )
          .controller!
          .text,
      '1',
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Random'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<PushButton>(
            find.widgetWithText(PushButton, 'Copy YouTube URLs'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester.getCenter(find.widgetWithText(PushButton, 'Copy YouTube URLs')).dx,
      greaterThan(
        tester.getCenter(find.widgetWithText(PushButton, 'Clear')).dx,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('bulk-random-count-field')),
      '3',
    );
    await tester.pump();
    expect(
      tester
          .widget<MacosTextField>(
            find.byKey(const ValueKey('bulk-random-count-field')),
          )
          .controller!
          .text,
      '3',
    );
    expect(
      tester
          .widget<PushButton>(find.widgetWithText(PushButton, 'Random'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(PushButton, 'Random'));
    await tester.tap(find.widgetWithText(PushButton, 'Copy YouTube URLs'));

    expect(randomCounts, [3]);
    expect(copyCalls, 1);
  });

  testWidgets('bulk toolbar caps random count at loaded video count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: BulkSelectionToolbar(
            selectedCount: 0,
            isBusy: false,
            maxLoadedVideoCount: 2,
            onSelectLoaded: () {},
            onSelectRandom: (_) {},
            onCopyYoutubeUrls: () {},
            onPlay: () {},
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

    final field = find.byKey(const ValueKey('bulk-random-count-field'));
    await tester.enterText(field, '9');

    expect(tester.widget<MacosTextField>(field).controller!.text, '2');
  });
}
