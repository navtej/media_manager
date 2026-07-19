import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('private-library auto-lock defaults to ten minutes', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final settings = await container.read(settingsProvider.future);

    expect(settings.privateLibraryAccess.autoLockMinutes, 10);
    expect(
      container.read(privateLibraryAutoLockDurationProvider),
      const Duration(minutes: 10),
    );
  });

  test(
    'private-library auto-lock falls back when persisted value is invalid',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'privateLibraryAutoLockMinutes': 121,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = await container.read(settingsProvider.future);

      expect(settings.privateLibraryAccess.autoLockMinutes, 10);
    },
  );

  test('private-library auto-lock update persists across reloads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    await container
        .read(settingsProvider.notifier)
        .updatePrivateLibraryAutoLockMinutes(45);

    expect(
      (await container.read(
        settingsProvider.future,
      )).privateLibraryAccess.autoLockMinutes,
      45,
    );

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    final reloadedSettings = await reloaded.read(settingsProvider.future);
    expect(reloadedSettings.privateLibraryAccess.autoLockMinutes, 45);
  });

  test(
    'private-library auto-lock update rejects out-of-range values',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      expect(
        () => container
            .read(settingsProvider.notifier)
            .updatePrivateLibraryAutoLockMinutes(0),
        throwsRangeError,
      );
      expect(
        () => container
            .read(settingsProvider.notifier)
            .updatePrivateLibraryAutoLockMinutes(121),
        throwsRangeError,
      );
    },
  );

  test(
    'summary subtitle preference defaults to enabled and persists',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      var settings = await container.read(settingsProvider.future);
      expect(settings.videoSummary.preferVttSubtitles, isTrue);

      await container
          .read(settingsProvider.notifier)
          .updateSummaryPreferVttSubtitles(false);
      settings = await container.read(settingsProvider.future);
      expect(settings.videoSummary.preferVttSubtitles, isFalse);

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      final reloadedSettings = await reloaded.read(settingsProvider.future);
      expect(reloadedSettings.videoSummary.preferVttSubtitles, isFalse);
    },
  );

  test(
    'summary API settings default to empty and persist across reloads',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      var settings = await container.read(settingsProvider.future);
      expect(settings.videoSummary.apiUrl, '');
      expect(settings.videoSummary.apiKey, '');

      final notifier = container.read(settingsProvider.notifier);
      await notifier.updateSummaryApiUrl(
        ' https://summary.example.test/v1/chat/completions ',
      );
      await notifier.updateSummaryApiKey(' sk-test ');

      settings = await container.read(settingsProvider.future);
      expect(
        settings.videoSummary.apiUrl,
        'https://summary.example.test/v1/chat/completions',
      );
      expect(settings.videoSummary.apiKey, 'sk-test');

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      final reloadedSettings = await reloaded.read(settingsProvider.future);
      expect(
        reloadedSettings.videoSummary.apiUrl,
        'https://summary.example.test/v1/chat/completions',
      );
      expect(reloadedSettings.videoSummary.apiKey, 'sk-test');
    },
  );

  test(
    'downloaded managed models and selected model persist across reloads',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final managedDirectory = await Directory.systemTemp.createTemp(
        'managed-model-persist-test',
      );
      addTearDown(() async {
        if (await managedDirectory.exists()) {
          await managedDirectory.delete(recursive: true);
        }
      });

      final baseModelPath = '${managedDirectory.path}/ggml-base.en.bin';
      final mediumModelPath = '${managedDirectory.path}/ggml-medium.bin';
      await File(baseModelPath).writeAsBytes(const <int>[1, 2, 3, 4]);
      await File(mediumModelPath).writeAsBytes(const <int>[5, 6, 7, 8]);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.installManagedSummaryModel(
        modelId: 'base.en',
        path: baseModelPath,
        managedDirectoryPath: managedDirectory.path,
      );
      await notifier.installManagedSummaryModel(
        modelId: 'medium',
        path: mediumModelPath,
        managedDirectoryPath: managedDirectory.path,
      );

      final settings = await container.read(settingsProvider.future);
      expect(settings.videoSummary.downloadedManagedModels, <String, String>{
        'base.en': baseModelPath,
        'medium': mediumModelPath,
      });
      expect(settings.videoSummary.selectedModelId, 'medium');
      expect(settings.videoSummary.modelPath, mediumModelPath);

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      final reloadedSettings = await reloaded.read(settingsProvider.future);
      expect(
        reloadedSettings.videoSummary.downloadedManagedModels,
        <String, String>{'base.en': baseModelPath, 'medium': mediumModelPath},
      );
      expect(reloadedSettings.videoSummary.selectedModelId, 'medium');
      expect(reloadedSettings.videoSummary.modelPath, mediumModelPath);
    },
  );

  test(
    'removing a downloaded managed model clears its active path but keeps selection',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.installManagedSummaryModel(
        modelId: 'base.en',
        path: '/tmp/models/ggml-base.en.bin',
        managedDirectoryPath: '/tmp/models',
      );
      await notifier.removeDownloadedManagedModel('base.en');

      final settings = await container.read(settingsProvider.future);
      expect(settings.videoSummary.downloadedManagedModels, isEmpty);
      expect(settings.videoSummary.selectedModelId, 'base.en');
      expect(settings.videoSummary.modelPath, '');
    },
  );

  test(
    'startup scan rebuilds downloaded managed models from disk and restores selected path',
    () async {
      final managedDirectory = await Directory.systemTemp.createTemp(
        'managed-model-scan-test',
      );
      addTearDown(() async {
        if (await managedDirectory.exists()) {
          await managedDirectory.delete(recursive: true);
        }
      });

      final baseModelPath = '${managedDirectory.path}/ggml-base.en.bin';
      final mediumModelPath = '${managedDirectory.path}/ggml-medium.bin';
      await File(baseModelPath).writeAsBytes(const <int>[1, 2, 3, 4]);
      await File(mediumModelPath).writeAsBytes(const <int>[5, 6, 7, 8]);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'summaryModelSource': 'managed',
        'summarySelectedModelId': 'medium',
        'summaryManagedModelDirectoryPath': managedDirectory.path,
        'summaryDownloadedManagedModels':
            '{"stale":"/tmp/old.bin","base.en":"/tmp/old-base.bin"}',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final settings = await container.read(settingsProvider.future);
      expect(settings.videoSummary.downloadedManagedModels, <String, String>{
        'base.en': baseModelPath,
        'medium': mediumModelPath,
      });
      expect(settings.videoSummary.selectedModelId, 'medium');
      expect(settings.videoSummary.modelPath, mediumModelPath);
    },
  );
}
