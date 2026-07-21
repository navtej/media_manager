import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:movie_manager/logic/video_summary_models.dart';
import 'package:movie_manager/logic/whisper_model_catalog.dart';
import 'package:movie_manager/ui/widgets/summary_model_settings_panel.dart';

void main() {
  Widget buildHarness(Widget child) {
    return MacosApp(home: MacosWindow(child: child));
  }

  testWidgets(
    'renders combined download metric and separate progress metric for managed mode',
    (WidgetTester tester) async {
      final catalog = WhisperModelCatalogState(
        entries: builtInWhisperModelCatalog
            .where((entry) => entry.id == 'base.en' || entry.id == 'base')
            .toList(),
        lastRefreshedAt: null,
        isRefreshing: false,
        refreshError: null,
      );

      await tester.pumpWidget(
        buildHarness(
          SummaryModelSettingsPanel(
            sourceMode: SummaryModelSourceMode.managedDownload,
            modelPath: '/tmp/ggml-base.en.bin',
            selectedModelId: 'base.en',
            downloadedManagedModels: const <String, String>{
              'base.en': '/tmp/ggml-base.en.bin',
            },
            validation: const SummaryModelValidationResult.valid('Ready'),
            runtimeStatus: 'Bundled runtime ready',
            catalogState: catalog,
            downloadState: const ModelDownloadState(
              phase: ModelDownloadPhase.downloading,
              modelId: 'base.en',
              receivedBytes: 1536,
              totalBytes: 3072,
              bytesPerSecond: 100,
              eta: Duration(seconds: 5),
              error: null,
            ),
            canDeleteManagedModel: true,
            preferVttSubtitles: true,
            statusMessage: null,
            onSourceModeChanged: (_) {},
            onSelectedModelChanged: (_) {},
            onPreferVttSubtitlesChanged: (_) {},
            onDownloadPressed: () {},
            onStopDownloadPressed: () {},
            onDeletePressed: () {},
            onBrowsePressed: () {},
            onRevealPressed: () {},
            onRefreshCatalogPressed: () {},
            onClearSelectionPressed: () {},
          ),
        ),
      );

      expect(find.text('Available Models'), findsOneWidget);
      expect(
        find.text(
          "Video summarization uses MovieManager's bundled Whisper runtime.",
        ),
        findsOneWidget,
      );
      expect(find.text('Bundled runtime ready'), findsOneWidget);
      expect(find.text('Stop Download'), findsOneWidget);
      expect(find.text('Download Model'), findsNothing);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Total'), findsNothing);
      expect(find.text('Speed'), findsOneWidget);
      expect(find.text('ETA'), findsOneWidget);
      expect(find.text('1.50 KiB / 3.00 KiB'), findsOneWidget);
      expect(find.text('100.00 B/s'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Downloaded Models'), findsOneWidget);
      expect(find.text('base.en'), findsWidgets);
      expect(find.text('Selected'), findsOneWidget);
      expect(find.text('Select'), findsNothing);

      expect(
        tester
            .widget<PushButton>(
              find.widgetWithText(PushButton, 'Refresh Catalog'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<PushButton>(find.widgetWithText(PushButton, 'Delete Model'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('shows clear selection instead of delete in local mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        SummaryModelSettingsPanel(
          sourceMode: SummaryModelSourceMode.localFile,
          modelPath: '/Applications/OtherApp/models/ggml-base.en.bin',
          selectedModelId: null,
          downloadedManagedModels: const <String, String>{},
          validation: const SummaryModelValidationResult.valid('Ready'),
          runtimeStatus: 'Bundled runtime ready',
          catalogState: WhisperModelCatalogState(
            entries: builtInWhisperModelCatalog.take(1).toList(),
            lastRefreshedAt: null,
            isRefreshing: false,
            refreshError: null,
          ),
          downloadState: const ModelDownloadState.idle(),
          canDeleteManagedModel: false,
          preferVttSubtitles: true,
          statusMessage: null,
          onSourceModeChanged: (_) {},
          onSelectedModelChanged: (_) {},
          onPreferVttSubtitlesChanged: (_) {},
          onDownloadPressed: () {},
          onStopDownloadPressed: () {},
          onDeletePressed: () {},
          onBrowsePressed: () {},
          onRevealPressed: () {},
          onRefreshCatalogPressed: () {},
          onClearSelectionPressed: () {},
        ),
      ),
    );

    expect(find.text('Clear Selection'), findsOneWidget);
    expect(find.text('Delete Model'), findsNothing);
    expect(find.text('No managed models downloaded yet.'), findsOneWidget);
  });

  testWidgets('subtitle preference checkbox reports changes', (
    WidgetTester tester,
  ) async {
    bool? changedValue;

    await tester.pumpWidget(
      buildHarness(
        SummaryModelSettingsPanel(
          sourceMode: SummaryModelSourceMode.managedDownload,
          modelPath: '/tmp/ggml-base.en.bin',
          selectedModelId: 'base.en',
          downloadedManagedModels: const <String, String>{},
          validation: const SummaryModelValidationResult.valid('Ready'),
          runtimeStatus: 'Bundled runtime ready',
          catalogState: WhisperModelCatalogState(
            entries: builtInWhisperModelCatalog.take(1).toList(),
            lastRefreshedAt: null,
            isRefreshing: false,
            refreshError: null,
          ),
          downloadState: const ModelDownloadState.idle(),
          canDeleteManagedModel: false,
          preferVttSubtitles: true,
          statusMessage: null,
          onSourceModeChanged: (_) {},
          onSelectedModelChanged: (_) {},
          onPreferVttSubtitlesChanged: (value) {
            changedValue = value;
          },
          onDownloadPressed: () {},
          onStopDownloadPressed: () {},
          onDeletePressed: () {},
          onBrowsePressed: () {},
          onRevealPressed: () {},
          onRefreshCatalogPressed: () {},
          onClearSelectionPressed: () {},
        ),
      ),
    );

    expect(find.text('Use .vtt subtitles when available'), findsOneWidget);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('prefer-vtt-subtitles-checkbox')),
      ),
      matchesSemantics(
        label: 'Use .vtt subtitles when available',
        isChecked: true,
        hasCheckedState: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        hasFocusAction: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('prefer-vtt-subtitles-checkbox')),
    );
    await tester.pump();

    expect(changedValue, isFalse);
  });

  testWidgets(
    'local mode hides managed selection state and shows the selected local model path',
    (WidgetTester tester) async {
      const localModelPath = '/Applications/OtherApp/models/ggml-base.en.bin';
      final catalog = WhisperModelCatalogState(
        entries: builtInWhisperModelCatalog
            .where((entry) => entry.id == 'base.en' || entry.id == 'medium')
            .toList(),
        lastRefreshedAt: null,
        isRefreshing: false,
        refreshError: null,
      );

      await tester.pumpWidget(
        buildHarness(
          SummaryModelSettingsPanel(
            sourceMode: SummaryModelSourceMode.localFile,
            modelPath: localModelPath,
            selectedModelId: 'medium',
            downloadedManagedModels: const <String, String>{
              'medium': '/tmp/ggml-medium.bin',
            },
            validation: const SummaryModelValidationResult.valid('Ready'),
            runtimeStatus: 'Bundled runtime ready',
            catalogState: catalog,
            downloadState: const ModelDownloadState.idle(),
            canDeleteManagedModel: false,
            preferVttSubtitles: true,
            statusMessage: null,
            onSourceModeChanged: (_) {},
            onSelectedModelChanged: (_) {},
            onPreferVttSubtitlesChanged: (_) {},
            onDownloadPressed: () {},
            onStopDownloadPressed: () {},
            onDeletePressed: () {},
            onBrowsePressed: () {},
            onRevealPressed: () {},
            onRefreshCatalogPressed: () {},
            onClearSelectionPressed: () {},
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('available-models-picker')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('local-selected-model-path')),
        findsOneWidget,
      );
      expect(find.text(localModelPath), findsWidgets);
      expect(find.text('Selected'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
    },
  );

  testWidgets('shows only downloaded models with dedicated select controls', (
    WidgetTester tester,
  ) async {
    final catalog = WhisperModelCatalogState(
      entries: builtInWhisperModelCatalog
          .where((entry) => entry.id == 'base.en' || entry.id == 'medium')
          .toList(),
      lastRefreshedAt: null,
      isRefreshing: false,
      refreshError: null,
    );

    await tester.pumpWidget(
      buildHarness(
        SummaryModelSettingsPanel(
          sourceMode: SummaryModelSourceMode.managedDownload,
          modelPath: '/tmp/ggml-medium.bin',
          selectedModelId: 'medium',
          downloadedManagedModels: const <String, String>{
            'base.en': '/tmp/ggml-base.en.bin',
            'medium': '/tmp/ggml-medium.bin',
          },
          validation: const SummaryModelValidationResult.valid('Ready'),
          runtimeStatus: 'Bundled runtime ready',
          catalogState: catalog,
          downloadState: const ModelDownloadState.idle(),
          canDeleteManagedModel: true,
          preferVttSubtitles: true,
          statusMessage: null,
          onSourceModeChanged: (_) {},
          onSelectedModelChanged: (_) {},
          onPreferVttSubtitlesChanged: (_) {},
          onDownloadPressed: () {},
          onStopDownloadPressed: () {},
          onDeletePressed: () {},
          onBrowsePressed: () {},
          onRevealPressed: () {},
          onRefreshCatalogPressed: () {},
          onClearSelectionPressed: () {},
        ),
      ),
    );

    expect(find.text('Downloaded Models'), findsOneWidget);
    expect(find.text('base.en'), findsWidgets);
    expect(find.text('medium'), findsWidgets);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Not Downloaded'), findsNothing);
    expect(find.byType(PushButton), findsNWidgets(5));
  });

  testWidgets('available models picker responds to arrow keys when focused', (
    WidgetTester tester,
  ) async {
    String? changedModelId;
    final catalog = WhisperModelCatalogState(
      entries: builtInWhisperModelCatalog
          .where((entry) => entry.id == 'base.en' || entry.id == 'medium')
          .toList(),
      lastRefreshedAt: null,
      isRefreshing: false,
      refreshError: null,
    );

    await tester.pumpWidget(
      buildHarness(
        SummaryModelSettingsPanel(
          sourceMode: SummaryModelSourceMode.managedDownload,
          modelPath: '/tmp/ggml-base.en.bin',
          selectedModelId: 'base.en',
          downloadedManagedModels: const <String, String>{
            'base.en': '/tmp/ggml-base.en.bin',
          },
          validation: const SummaryModelValidationResult.valid('Ready'),
          runtimeStatus: 'Bundled runtime ready',
          catalogState: catalog,
          downloadState: const ModelDownloadState.idle(),
          canDeleteManagedModel: true,
          preferVttSubtitles: true,
          statusMessage: null,
          onSourceModeChanged: (_) {},
          onSelectedModelChanged: (value) {
            changedModelId = value;
          },
          onPreferVttSubtitlesChanged: (_) {},
          onDownloadPressed: () {},
          onStopDownloadPressed: () {},
          onDeletePressed: () {},
          onBrowsePressed: () {},
          onRevealPressed: () {},
          onRefreshCatalogPressed: () {},
          onClearSelectionPressed: () {},
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(changedModelId, 'medium');
  });
}
