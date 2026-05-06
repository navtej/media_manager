import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/model_download_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/video_summary_models.dart';
import 'package:movie_manager/logic/whisper_model_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'downloadManagedModel registers the model and selects it for summarization',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final supportDirectory = await Directory.systemTemp.createTemp(
        'model-download-success-test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });

      final container = ProviderContainer(
        overrides: [
          applicationSupportDirectoryProvider.overrideWith(
            (ref) async => supportDirectory,
          ),
          managedModelDownloadClientFactoryProvider.overrideWith(
            (ref) => _SuccessfulManagedModelDownloadClient.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      const entry = WhisperModelCatalogEntry(
        id: 'base.en',
        displayName: 'base.en',
        variantType: WhisperModelVariantType.englishOnly,
        family: 'base',
        diskSizeLabel: '142 MiB',
        diskSizeBytes: 148897792,
        downloadUrl: 'https://example.com/ggml-base.en.bin',
      );

      await container
          .read(modelDownloadControllerProvider.notifier)
          .downloadManagedModel(entry);

      final settings = await container.read(settingsProvider.future);
      final expectedPath = '${supportDirectory.path}/models/ggml-base.en.bin';
      expect(settings['summarySelectedModelId'], 'base.en');
      expect(settings['summaryModelPath'], expectedPath);
      expect(settings['summaryDownloadedManagedModels'], <String, String>{
        'base.en': expectedPath,
      });
    },
  );

  test(
    'cancelDownload deletes the partial file and keeps settings clean',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final supportDirectory = await Directory.systemTemp.createTemp(
        'model-download-test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });

      final fakeClient = _FakeManagedModelDownloadClient();
      final container = ProviderContainer(
        overrides: [
          applicationSupportDirectoryProvider.overrideWith(
            (ref) async => supportDirectory,
          ),
          managedModelDownloadClientFactoryProvider.overrideWith(
            (ref) =>
                () => fakeClient,
          ),
        ],
      );
      addTearDown(container.dispose);

      const entry = WhisperModelCatalogEntry(
        id: 'base.en',
        displayName: 'base.en',
        variantType: WhisperModelVariantType.englishOnly,
        family: 'base',
        diskSizeLabel: '142 MiB',
        diskSizeBytes: 148897792,
        downloadUrl: 'https://example.com/ggml-base.en.bin',
      );

      final notifier = container.read(modelDownloadControllerProvider.notifier);
      final downloadFuture = notifier.downloadManagedModel(entry);

      await fakeClient.waitUntilStarted();

      final partialFile = File(
        '${supportDirectory.path}/models/ggml-base.en.bin',
      );
      await partialFile.parent.create(recursive: true);
      await partialFile.writeAsBytes(const <int>[1, 2, 3, 4]);

      await notifier.cancelDownload();
      await downloadFuture;

      expect(
        container.read(modelDownloadControllerProvider).phase,
        ModelDownloadPhase.idle,
      );
      expect(await partialFile.exists(), isFalse);

      final settings = await container.read(settingsProvider.future);
      expect(settings['summaryModelPath'], '');
      expect(
        settings['summaryModelSource'],
        SummaryModelSourceMode.managedDownload.value,
      );
    },
  );
}

class _FakeManagedModelDownloadClient implements ManagedModelDownloadClient {
  final Completer<void> _started = Completer<void>();
  bool _cancelled = false;

  @override
  Future<void> download({
    required Uri uri,
    required File destination,
    required void Function(int receivedBytes, int? totalBytes) onProgress,
  }) async {
    if (!_started.isCompleted) {
      _started.complete();
    }

    while (!_cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    throw const DownloadCancelledException();
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
  }

  Future<void> waitUntilStarted() => _started.future;
}

class _SuccessfulManagedModelDownloadClient
    implements ManagedModelDownloadClient {
  @override
  Future<void> cancel() async {}

  @override
  Future<void> download({
    required Uri uri,
    required File destination,
    required void Function(int receivedBytes, int? totalBytes) onProgress,
  }) async {
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(const <int>[1, 2, 3, 4]);
    onProgress(4, 4);
  }
}
