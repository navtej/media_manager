import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart'
    show FutureProvider, Provider;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'settings_provider.dart';
import 'video_summary_models.dart';
import 'whisper_model_catalog.dart';

part 'model_download_controller.g.dart';

typedef ManagedModelDownloadClientFactory =
    ManagedModelDownloadClient Function();

final applicationSupportDirectoryProvider = FutureProvider<Directory>((ref) {
  return getApplicationSupportDirectory();
});

final managedModelDownloadClientFactoryProvider =
    Provider<ManagedModelDownloadClientFactory>((ref) {
      return HttpManagedModelDownloadClient.new;
    });

abstract class ManagedModelDownloadClient {
  Future<void> download({
    required Uri uri,
    required File destination,
    required void Function(int receivedBytes, int? totalBytes) onProgress,
  });

  Future<void> cancel();
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException();

  @override
  String toString() => 'DownloadCancelledException';
}

class HttpManagedModelDownloadClient implements ManagedModelDownloadClient {
  HttpClient? _client;
  IOSink? _sink;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _completer;
  File? _destination;
  bool _cancelRequested = false;

  @override
  Future<void> download({
    required Uri uri,
    required File destination,
    required void Function(int receivedBytes, int? totalBytes) onProgress,
  }) async {
    _cancelRequested = false;
    _destination = destination;
    _client = HttpClient();

    final request = await _client!.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Model download failed with status ${response.statusCode}.',
      );
    }

    final totalBytes = response.contentLength > 0
        ? response.contentLength
        : null;
    final sink = destination.openWrite();
    _sink = sink;

    final completer = Completer<void>();
    _completer = completer;
    var receivedBytes = 0;

    _subscription = response.listen(
      (chunk) {
        if (_cancelRequested) {
          return;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress(receivedBytes, totalBytes);
      },
      onError: (Object error, StackTrace stackTrace) async {
        await sink.close();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () async {
        await sink.flush();
        await sink.close();
        if (!completer.isCompleted) {
          if (_cancelRequested) {
            completer.completeError(const DownloadCancelledException());
          } else {
            completer.complete();
          }
        }
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _sink = null;
      _client?.close(force: true);
      _client = null;
      _completer = null;
      _destination = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    await _subscription?.cancel();
    await _sink?.close();
    _client?.close(force: true);

    final destination = _destination;
    if (destination != null && await destination.exists()) {
      await destination.delete();
    }

    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError(const DownloadCancelledException());
    }
  }
}

@Riverpod(keepAlive: true)
class ModelDownloadController extends _$ModelDownloadController {
  ManagedModelDownloadClient? _activeClient;
  File? _activeDestination;

  @override
  ModelDownloadState build() => const ModelDownloadState.idle();

  Future<void> downloadManagedModel(WhisperModelCatalogEntry entry) async {
    final downloadUrl = entry.downloadUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      state = const ModelDownloadState.idle().copyWith(
        phase: ModelDownloadPhase.failed,
        modelId: entry.id,
        error: 'No managed download URL is available for ${entry.id}.',
      );
      return;
    }

    state = const ModelDownloadState.idle().copyWith(
      phase: ModelDownloadPhase.downloading,
      modelId: entry.id,
      clearError: true,
      clearEta: true,
      clearTotalBytes: true,
    );

    final supportDirectory = await ref.read(
      applicationSupportDirectoryProvider.future,
    );
    final managedDirectory = Directory(p.join(supportDirectory.path, 'models'));
    if (!await managedDirectory.exists()) {
      await managedDirectory.create(recursive: true);
    }

    final destination = File(
      p.join(managedDirectory.path, 'ggml-${entry.id}.bin'),
    );
    final stopwatch = Stopwatch()..start();
    final client = ref.read(managedModelDownloadClientFactoryProvider)();
    _activeClient = client;
    _activeDestination = destination;

    try {
      await client.download(
        uri: Uri.parse(downloadUrl),
        destination: destination,
        onProgress: (receivedBytes, totalBytes) {
          final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000;
          final bytesPerSecond = elapsedSeconds > 0
              ? receivedBytes / elapsedSeconds
              : 0.0;
          final eta = totalBytes != null && bytesPerSecond > 0
              ? Duration(
                  seconds:
                      (((totalBytes - receivedBytes) / bytesPerSecond)
                              .ceil()
                              .clamp(0, 1 << 31))
                          .toInt(),
                )
              : null;

          state = state.copyWith(
            phase: ModelDownloadPhase.downloading,
            modelId: entry.id,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            bytesPerSecond: bytesPerSecond,
            eta: eta,
            clearError: true,
          );
        },
      );

      await ref
          .read(settingsProvider.notifier)
          .updateSummaryModelSource(SummaryModelSourceMode.managedDownload);
      await ref
          .read(settingsProvider.notifier)
          .registerDownloadedManagedModel(
            modelId: entry.id,
            path: destination.path,
          );
      await ref
          .read(settingsProvider.notifier)
          .selectManagedSummaryModel(entry.id);
      await ref
          .read(settingsProvider.notifier)
          .updateSummaryManagedModelDirectoryPath(managedDirectory.path);
      ref.invalidate(summaryModelValidationProvider);

      state = state.copyWith(
        phase: ModelDownloadPhase.completed,
        modelId: entry.id,
        clearError: true,
        eta: Duration.zero,
      );
    } on DownloadCancelledException {
      state = const ModelDownloadState.idle();
    } catch (error) {
      if (await destination.exists()) {
        await destination.delete();
      }

      state = state.copyWith(
        phase: ModelDownloadPhase.failed,
        error: error.toString(),
        clearEta: true,
      );
    } finally {
      stopwatch.stop();
      _activeClient = null;
      _activeDestination = null;
    }
  }

  Future<void> cancelDownload() async {
    final client = _activeClient;
    if (client == null) {
      state = const ModelDownloadState.idle();
      return;
    }

    await client.cancel();
    final destination = _activeDestination;
    if (destination != null && await destination.exists()) {
      await destination.delete();
    }
    _activeClient = null;
    _activeDestination = null;
    state = const ModelDownloadState.idle();
  }

  Future<void> deleteManagedModel({
    required String? modelId,
    required String modelPath,
    required String managedDirectoryPath,
  }) async {
    if (!isManagedModelPath(
      modelPath: modelPath,
      managedDirectoryPath: managedDirectoryPath,
    )) {
      state = state.copyWith(
        phase: ModelDownloadPhase.failed,
        error: 'Only app-managed model files can be deleted.',
      );
      return;
    }

    final file = File(modelPath);
    if (await file.exists()) {
      await file.delete();
    }

    if (modelId != null && modelId.isNotEmpty) {
      await ref
          .read(settingsProvider.notifier)
          .removeDownloadedManagedModel(modelId);
    } else {
      await ref.read(settingsProvider.notifier).clearSummaryModelPath();
    }
    ref.invalidate(summaryModelValidationProvider);

    state = const ModelDownloadState.idle();
  }

  Future<void> clearLocalSelection() async {
    await ref.read(settingsProvider.notifier).clearSummaryModelPath();
    ref.invalidate(summaryModelValidationProvider);

    state = const ModelDownloadState.idle();
  }
}
