import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/ui/widgets/video_grid.dart';

void main() {
  testWidgets('summary error panel collapses long exceptions behind details', (
    tester,
  ) async {
    final longError = 'Bad state: ${'whisper failure ' * 80}';

    await tester.pumpWidget(
      MacosApp(
        home: MacosWindow(
          child: MacosScaffold(
            children: [
              ContentArea(
                builder: (context, _) =>
                    SummaryErrorPanel(errorText: longError),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Bad state:'), findsNothing);
    expect(find.text('Summary generation failed.'), findsOneWidget);
    expect(find.text('View Details'), findsOneWidget);

    await tester.tap(find.text('View Details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Summary Error Details'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);

    expect(find.text('Copy Error'), findsOneWidget);
  });
}
