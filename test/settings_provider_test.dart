import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      await notifier.registerDownloadedManagedModel(
        modelId: 'base.en',
        path: baseModelPath,
      );
      await notifier.registerDownloadedManagedModel(
        modelId: 'medium',
        path: mediumModelPath,
      );
      await notifier.updateSummaryManagedModelDirectoryPath(
        managedDirectory.path,
      );
      await notifier.selectManagedSummaryModel('medium');

      final settings = await container.read(settingsProvider.future);
      expect(settings['summaryDownloadedManagedModels'], <String, String>{
        'base.en': baseModelPath,
        'medium': mediumModelPath,
      });
      expect(settings['summarySelectedModelId'], 'medium');
      expect(settings['summaryModelPath'], mediumModelPath);

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      final reloadedSettings = await reloaded.read(settingsProvider.future);
      expect(
        reloadedSettings['summaryDownloadedManagedModels'],
        <String, String>{'base.en': baseModelPath, 'medium': mediumModelPath},
      );
      expect(reloadedSettings['summarySelectedModelId'], 'medium');
      expect(reloadedSettings['summaryModelPath'], mediumModelPath);
    },
  );

  test(
    'removing a downloaded managed model clears its active path but keeps selection',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.registerDownloadedManagedModel(
        modelId: 'base.en',
        path: '/tmp/models/ggml-base.en.bin',
      );
      await notifier.selectManagedSummaryModel('base.en');
      await notifier.removeDownloadedManagedModel('base.en');

      final settings = await container.read(settingsProvider.future);
      expect(settings['summaryDownloadedManagedModels'], <String, String>{});
      expect(settings['summarySelectedModelId'], 'base.en');
      expect(settings['summaryModelPath'], '');
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
      expect(settings['summaryDownloadedManagedModels'], <String, String>{
        'base.en': baseModelPath,
        'medium': mediumModelPath,
      });
      expect(settings['summarySelectedModelId'], 'medium');
      expect(settings['summaryModelPath'], mediumModelPath);
    },
  );
}
