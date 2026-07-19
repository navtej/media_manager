import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/video_summary_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings expose cohesive typed defaults', () async {
    final persistence = MemorySettingsPersistence();
    final container = _containerFor(persistence);
    addTearDown(container.dispose);

    final settings = await container.read(settingsProvider.future);

    expect(settings.librarySynchronization.scanIntervalMinutes, 5);
    expect(settings.librarySynchronization.batchSize, 4);
    expect(
      settings.privateLibraryAccess.autoLockDuration,
      const Duration(minutes: 10),
    );
    expect(settings.appearance.themeMode, AppearanceThemeMode.system);
    expect(settings.catalogBrowsing.paginationSize, 50);
    expect(settings.catalogBrowsing.showOfflineMedia, isTrue);
    expect(
      settings.videoSummary.modelSource,
      SummaryModelSourceMode.managedDownload,
    );
    expect(settings.videoSummary.modelPath, isEmpty);
    expect(settings.videoSummary.preferVttSubtitles, isTrue);
  });

  test(
    'every existing preference key migrates into typed configuration',
    () async {
      final managedDirectory = await Directory.systemTemp.createTemp(
        'typed-settings-migration-test',
      );
      addTearDown(() async {
        if (await managedDirectory.exists()) {
          await managedDirectory.delete(recursive: true);
        }
      });
      final managedModelPath = '${managedDirectory.path}/ggml-medium.bin';
      await File(managedModelPath).writeAsBytes(const <int>[1, 2, 3]);

      final persistence = MemorySettingsPersistence({
        'scanInterval': 12,
        'batchSize': 8,
        'themeMode': 'dark',
        'paginationSize': 75,
        'showOfflineMedia': false,
        'privateLibraryAutoLockMinutes': 45,
        'summaryModelSource': 'managed',
        'summaryModelPath': '/stale/model.bin',
        'summarySelectedModelId': 'medium',
        'summaryCatalogLastRefreshedAt': '2026-07-19T09:30:00.000Z',
        'summaryManagedModelDirectoryPath': managedDirectory.path,
        'summaryDownloadedManagedModels': jsonEncode({
          'stale': '/missing/model.bin',
        }),
        'summaryPreferVttSubtitles': false,
        'summaryApiUrl': 'https://summary.example.test/v1/chat/completions',
        'summaryApiKey': 'secret',
      });
      final container = _containerFor(persistence);
      addTearDown(container.dispose);

      final settings = await container.read(settingsProvider.future);

      expect(settings.librarySynchronization.scanIntervalMinutes, 12);
      expect(settings.librarySynchronization.batchSize, 8);
      expect(settings.appearance.themeMode, AppearanceThemeMode.dark);
      expect(settings.catalogBrowsing.paginationSize, 75);
      expect(settings.catalogBrowsing.showOfflineMedia, isFalse);
      expect(settings.privateLibraryAccess.autoLockMinutes, 45);
      expect(
        settings.videoSummary.modelSource,
        SummaryModelSourceMode.managedDownload,
      );
      expect(settings.videoSummary.selectedModelId, 'medium');
      expect(settings.videoSummary.modelPath, managedModelPath);
      expect(
        settings.videoSummary.catalogLastRefreshedAt,
        DateTime.utc(2026, 7, 19, 9, 30),
      );
      expect(
        settings.videoSummary.managedModelDirectoryPath,
        managedDirectory.path,
      );
      expect(settings.videoSummary.downloadedManagedModels, {
        'medium': managedModelPath,
      });
      expect(settings.videoSummary.preferVttSubtitles, isFalse);
      expect(
        settings.videoSummary.apiUrl,
        'https://summary.example.test/v1/chat/completions',
      );
      expect(settings.videoSummary.apiKey, 'secret');
    },
  );

  test(
    'existing local model path loads without managed-model resolution',
    () async {
      final persistence = MemorySettingsPersistence({
        'summaryModelSource': 'local',
        'summaryModelPath': '/Users/test/custom-model.bin',
        'summarySelectedModelId': 'base.en',
      });
      final container = _containerFor(persistence);
      addTearDown(container.dispose);

      final summary = (await container.read(
        settingsProvider.future,
      )).videoSummary;

      expect(summary.modelSource, SummaryModelSourceMode.localFile);
      expect(summary.modelPath, '/Users/test/custom-model.bin');
      expect(summary.selectedModelId, 'base.en');
    },
  );

  test('load and update share domain validation rules', () async {
    final persistence = MemorySettingsPersistence({
      'scanInterval': 0,
      'batchSize': -1,
      'paginationSize': 0,
      'themeMode': 'sepia',
      'privateLibraryAutoLockMinutes': 121,
    });
    final container = _containerFor(persistence);
    addTearDown(container.dispose);

    var settings = await container.read(settingsProvider.future);
    expect(settings.librarySynchronization.scanIntervalMinutes, 5);
    expect(settings.librarySynchronization.batchSize, 4);
    expect(settings.catalogBrowsing.paginationSize, 50);
    expect(settings.appearance.themeMode, AppearanceThemeMode.system);
    expect(settings.privateLibraryAccess.autoLockMinutes, 10);

    await container.read(settingsProvider.notifier).updateSettings(0, -1, 0);
    await container
        .read(settingsProvider.notifier)
        .updateTheme(AppearanceThemeMode.system);
    settings = await container.read(settingsProvider.future);
    expect(settings.librarySynchronization.scanIntervalMinutes, 5);
    expect(settings.librarySynchronization.batchSize, 4);
    expect(settings.catalogBrowsing.paginationSize, 50);
    expect(settings.appearance.themeMode, AppearanceThemeMode.system);
  });

  test('typed domain providers publish configuration changes', () async {
    final persistence = MemorySettingsPersistence();
    final container = _containerFor(persistence);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    final notifier = container.read(settingsProvider.notifier);
    await notifier.updateSettings(15, 6, 80);
    await notifier.updateShowOfflineMedia(false);
    await notifier.updatePrivateLibraryAutoLockMinutes(25);
    await notifier.updateTheme(AppearanceThemeMode.dark);
    await notifier.updateSummaryPreferVttSubtitles(false);
    await notifier.updateSummaryApiUrl('https://summary.example.test');

    final synchronization = container
        .read(librarySynchronizationConfigurationProvider)
        .requireValue;
    final privateLibrary = container
        .read(privateLibraryAccessConfigurationProvider)
        .requireValue;
    final appearance = container
        .read(appearanceConfigurationProvider)
        .requireValue;
    final catalog = container
        .read(catalogBrowsingConfigurationProvider)
        .requireValue;
    final summary = container
        .read(videoSummaryConfigurationProvider)
        .requireValue;

    expect(synchronization.scanIntervalMinutes, 15);
    expect(synchronization.batchSize, 6);
    expect(privateLibrary.autoLockDuration, const Duration(minutes: 25));
    expect(appearance.themeMode, AppearanceThemeMode.dark);
    expect(catalog.paginationSize, 80);
    expect(catalog.showOfflineMedia, isFalse);
    expect(summary.preferVttSubtitles, isFalse);
    expect(summary.apiUrl, 'https://summary.example.test');

    final reloadedContainer = _containerFor(persistence);
    addTearDown(reloadedContainer.dispose);
    final reloaded = await reloadedContainer.read(settingsProvider.future);
    expect(reloaded.librarySynchronization.scanIntervalMinutes, 15);
    expect(reloaded.librarySynchronization.batchSize, 6);
    expect(reloaded.privateLibraryAccess.autoLockMinutes, 25);
    expect(reloaded.appearance.themeMode, AppearanceThemeMode.dark);
    expect(reloaded.catalogBrowsing.paginationSize, 80);
    expect(reloaded.catalogBrowsing.showOfflineMedia, isFalse);
    expect(reloaded.videoSummary.preferVttSubtitles, isFalse);
    expect(reloaded.videoSummary.apiUrl, 'https://summary.example.test');
  });

  test('reload resolves a selected managed model that disappeared', () async {
    final managedDirectory = await Directory.systemTemp.createTemp(
      'typed-settings-missing-model-test',
    );
    addTearDown(() async {
      if (await managedDirectory.exists()) {
        await managedDirectory.delete(recursive: true);
      }
    });
    final modelPath = '${managedDirectory.path}/ggml-base.en.bin';
    final modelFile = File(modelPath);
    await modelFile.writeAsBytes(const <int>[1, 2, 3]);
    final persistence = MemorySettingsPersistence({
      'summaryModelSource': 'managed',
      'summarySelectedModelId': 'base.en',
      'summaryModelPath': modelPath,
      'summaryManagedModelDirectoryPath': managedDirectory.path,
      'summaryDownloadedManagedModels': jsonEncode({'base.en': modelPath}),
    });
    final initialContainer = _containerFor(persistence);
    addTearDown(initialContainer.dispose);

    final initial = (await initialContainer.read(
      settingsProvider.future,
    )).videoSummary;
    expect(initial.selectedModelId, 'base.en');
    expect(initial.modelPath, modelPath);

    await modelFile.delete();
    final reloadedContainer = _containerFor(persistence);
    addTearDown(reloadedContainer.dispose);
    final reloaded = (await reloadedContainer.read(
      settingsProvider.future,
    )).videoSummary;

    expect(reloaded.selectedModelId, 'base.en');
    expect(reloaded.modelPath, isEmpty);
    expect(reloaded.downloadedManagedModels, isEmpty);
    expect(persistence.values.containsKey('summaryModelPath'), isFalse);
  });

  test(
    'managed-model transitions only publish resolved selection and path pairs',
    () async {
      final persistence = MemorySettingsPersistence();
      final container = _containerFor(persistence);
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      final published = <VideoSummaryConfiguration>[];
      final subscription = container.listen(settingsProvider, (_, next) {
        final summary = next.asData?.value.videoSummary;
        if (summary != null) {
          published.add(summary);
        }
      });
      addTearDown(subscription.close);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.installManagedSummaryModel(
        modelId: 'base.en',
        path: '/tmp/models/ggml-base.en.bin',
        managedDirectoryPath: '/tmp/models',
      );
      await notifier.selectManagedSummaryModel('missing');
      await notifier.selectManagedSummaryModel('base.en');
      await notifier.removeDownloadedManagedModel('base.en');

      expect(published, isNotEmpty);
      for (final summary in published) {
        if (summary.modelSource != SummaryModelSourceMode.managedDownload) {
          continue;
        }
        final expectedPath = summary.selectedModelId == null
            ? ''
            : summary.downloadedManagedModels[summary.selectedModelId] ?? '';
        expect(summary.modelPath, expectedPath);
      }

      final resolved = (await container.read(
        settingsProvider.future,
      )).videoSummary;
      expect(resolved.selectedModelId, 'base.en');
      expect(resolved.modelPath, isEmpty);
      expect(resolved.downloadedManagedModels, isEmpty);
    },
  );
}

ProviderContainer _containerFor(SettingsPersistence persistence) {
  return ProviderContainer(
    overrides: [
      settingsPersistenceProvider.overrideWith((ref) async => persistence),
    ],
  );
}

class MemorySettingsPersistence implements SettingsPersistence {
  MemorySettingsPersistence([Map<String, Object>? values])
    : values = {...?values};

  final Map<String, Object> values;

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  int? getInt(String key) => values[key] as int?;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    values[key] = value;
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}
