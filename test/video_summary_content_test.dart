import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/logic/video_summary_models.dart';
import 'package:movie_manager/ui/widgets/video_grid.dart';

void main() {
  testWidgets('renders themed summary sections when available', (tester) async {
    await tester.pumpWidget(
      MacosApp(
        home: const VideoSummaryContent(
          summary: StructuredVideoSummary(
            synopsis: 'A broader synopsis.',
            themes: [
              VideoSummaryTheme(
                title: 'Setup',
                bullets: [
                  'Introduces the central problem.',
                  'Explains the main participants.',
                  'Frames the stakes.',
                ],
              ),
            ],
            highlights: ['Legacy highlight'],
            keywords: ['drama'],
          ),
        ),
      ),
    );

    expect(find.text('A broader synopsis.'), findsOneWidget);
    expect(find.text('Themes'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('• Introduces the central problem.'), findsOneWidget);
    expect(find.text('Highlights'), findsNothing);
    expect(find.text('• Legacy highlight'), findsNothing);
    expect(find.text('drama'), findsOneWidget);
  });

  testWidgets('renders legacy flat highlights when no themes are present', (
    tester,
  ) async {
    await tester.pumpWidget(
      MacosApp(
        home: const VideoSummaryContent(
          summary: StructuredVideoSummary(
            synopsis: 'A legacy synopsis.',
            highlights: ['Legacy highlight'],
            keywords: ['archive'],
          ),
        ),
      ),
    );

    expect(find.text('A legacy synopsis.'), findsOneWidget);
    expect(find.text('Highlights'), findsOneWidget);
    expect(find.text('• Legacy highlight'), findsOneWidget);
    expect(find.text('Themes'), findsNothing);
    expect(find.text('archive'), findsOneWidget);
  });
}
