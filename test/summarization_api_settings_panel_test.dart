import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/ui/widgets/summarization_api_settings_panel.dart';

void main() {
  Widget buildHarness(Widget child) {
    return MacosApp(home: MacosWindow(child: child));
  }

  testWidgets('renders API URL and optional API key fields', (tester) async {
    await tester.pumpWidget(
      buildHarness(
        SummarizationApiSettingsPanel(
          apiUrl: 'https://summary.example.test/v1/chat/completions',
          apiKey: 'sk-test',
          statusMessage: 'Saved',
          onSave: ({required apiUrl, required apiKey}) {},
        ),
      ),
    );

    expect(find.text('OpenAI-Compatible API'), findsOneWidget);
    expect(find.text('API URL'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(
      find.text('https://summary.example.test/v1/chat/completions'),
      findsOneWidget,
    );
    expect(find.text('Saved'), findsOneWidget);
    expect(find.widgetWithText(PushButton, 'Save'), findsOneWidget);
  });

  testWidgets('reports trimmed API settings when saved', (tester) async {
    String? savedUrl;
    String? savedKey;

    await tester.pumpWidget(
      buildHarness(
        SummarizationApiSettingsPanel(
          apiUrl: '',
          apiKey: '',
          statusMessage: null,
          onSave: ({required apiUrl, required apiKey}) {
            savedUrl = apiUrl;
            savedKey = apiKey;
          },
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('summarization-api-url-field')),
      ' https://summary.example.test/v1/chat/completions ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('summarization-api-key-field')),
      ' sk-test ',
    );
    await tester.tap(find.widgetWithText(PushButton, 'Save'));

    expect(savedUrl, 'https://summary.example.test/v1/chat/completions');
    expect(savedKey, 'sk-test');
  });
}
