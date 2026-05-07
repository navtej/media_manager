import 'dart:io';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'video_summary_models.dart';
import 'whisper_model_catalog.dart';

part 'settings_provider.g.dart';

@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  @override
  FutureOr<Map<String, dynamic>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final summaryModelSource =
        prefs.getString('summaryModelSource') ??
        SummaryModelSourceMode.managedDownload.value;
    final selectedModelId = prefs.getString('summarySelectedModelId');
    final downloadedManagedModels = await _resolveDownloadedManagedModels(
      prefs,
    );
    final summaryModelPath = _resolveSummaryModelPath(
      sourceValue: summaryModelSource,
      selectedModelId: selectedModelId,
      downloadedManagedModels: downloadedManagedModels,
      localModelPath: prefs.getString('summaryModelPath') ?? '',
    );

    return {
      'scanInterval': prefs.getInt('scanInterval') ?? 5,
      'batchSize': prefs.getInt('batchSize') ?? 4,
      'themeMode': prefs.getString('themeMode') ?? 'system',
      'paginationSize': prefs.getInt('paginationSize') ?? 50,
      'showOfflineMedia': prefs.getBool('showOfflineMedia') ?? true,
      'summaryModelSource': summaryModelSource,
      'summaryModelPath': summaryModelPath,
      'summarySelectedModelId': selectedModelId,
      'summaryCatalogLastRefreshedAt': prefs.getString(
        'summaryCatalogLastRefreshedAt',
      ),
      'summaryManagedModelDirectoryPath': prefs.getString(
        'summaryManagedModelDirectoryPath',
      ),
      'summaryDownloadedManagedModels': downloadedManagedModels,
      'summaryPreferVttSubtitles':
          prefs.getBool('summaryPreferVttSubtitles') ?? true,
    };
  }

  Future<void> updateSettings(
    int scanInterval,
    int batchSize,
    int paginationSize,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('scanInterval', scanInterval);
    await prefs.setInt('batchSize', batchSize);
    await prefs.setInt('paginationSize', paginationSize);

    state = AsyncData({
      ...state.value ?? {},
      'scanInterval': scanInterval,
      'batchSize': batchSize,
      'paginationSize': paginationSize,
    });
  }

  Future<void> updateShowOfflineMedia(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showOfflineMedia', value);

    final currentData = state.value ?? {};
    state = AsyncValue.data({...currentData, 'showOfflineMedia': value});
  }

  Future<void> updateTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode);

    final currentData = state.value ?? {};
    state = AsyncValue.data({...currentData, 'themeMode': mode});
  }

  Future<void> updateSummaryModelSource(SummaryModelSourceMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('summaryModelSource', mode.value);

    final currentData = state.value ?? {};
    state = AsyncValue.data({...currentData, 'summaryModelSource': mode.value});
  }

  Future<void> updateSummaryModelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('summaryModelPath', path);

    final currentData = state.value ?? {};
    state = AsyncValue.data({...currentData, 'summaryModelPath': path});
  }

  Future<void> updateSummarySelectedModelId(String? modelId) async {
    final prefs = await SharedPreferences.getInstance();
    if (modelId == null || modelId.isEmpty) {
      await prefs.remove('summarySelectedModelId');
    } else {
      await prefs.setString('summarySelectedModelId', modelId);
    }

    final currentData = state.value ?? {};
    state = AsyncValue.data({
      ...currentData,
      'summarySelectedModelId': modelId,
    });
  }

  Future<void> updateSummaryCatalogLastRefreshedAt(DateTime? timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    if (timestamp == null) {
      await prefs.remove('summaryCatalogLastRefreshedAt');
    } else {
      await prefs.setString(
        'summaryCatalogLastRefreshedAt',
        timestamp.toIso8601String(),
      );
    }

    final currentData = state.value ?? {};
    state = AsyncValue.data({
      ...currentData,
      'summaryCatalogLastRefreshedAt': timestamp?.toIso8601String(),
    });
  }

  Future<void> updateSummaryManagedModelDirectoryPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove('summaryManagedModelDirectoryPath');
    } else {
      await prefs.setString('summaryManagedModelDirectoryPath', path);
    }

    final currentData = state.value ?? {};
    state = AsyncValue.data({
      ...currentData,
      'summaryManagedModelDirectoryPath': path,
    });
  }

  Future<void> registerDownloadedManagedModel({
    required String modelId,
    required String path,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final models = _coerceDownloadedManagedModels(state.value);
    models[modelId] = path;
    await prefs.setString('summaryDownloadedManagedModels', jsonEncode(models));

    final currentData = state.value ?? {};
    state = AsyncValue.data({
      ...currentData,
      'summaryDownloadedManagedModels': models,
    });
  }

  Future<void> removeDownloadedManagedModel(String modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final models = _coerceDownloadedManagedModels(state.value);
    models.remove(modelId);
    await prefs.setString('summaryDownloadedManagedModels', jsonEncode(models));

    final currentData = state.value ?? {};
    final currentSelectedModelId = currentData['summarySelectedModelId']
        ?.toString();
    final nextModelPath = currentSelectedModelId == modelId
        ? ''
        : (currentData['summaryModelPath']?.toString() ?? '');
    if (currentSelectedModelId == modelId) {
      await prefs.remove('summaryModelPath');
    }

    state = AsyncValue.data({
      ...currentData,
      'summaryDownloadedManagedModels': models,
      'summaryModelPath': nextModelPath,
    });
  }

  Future<void> selectManagedSummaryModel(String? modelId) async {
    final prefs = await SharedPreferences.getInstance();
    final currentData = state.value ?? {};
    final models = _coerceDownloadedManagedModels(currentData);
    final nextModelPath = modelId == null || modelId.isEmpty
        ? ''
        : (models[modelId] ?? '');

    if (modelId == null || modelId.isEmpty) {
      await prefs.remove('summarySelectedModelId');
      await prefs.remove('summaryModelPath');
    } else {
      await prefs.setString('summarySelectedModelId', modelId);
      if (nextModelPath.isEmpty) {
        await prefs.remove('summaryModelPath');
      } else {
        await prefs.setString('summaryModelPath', nextModelPath);
      }
    }

    state = AsyncValue.data({
      ...currentData,
      'summarySelectedModelId': modelId,
      'summaryModelPath': nextModelPath,
    });
  }

  Future<void> clearSummaryModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('summaryModelPath');

    final currentData = state.value ?? {};
    state = AsyncValue.data({...currentData, 'summaryModelPath': ''});
  }

  Future<void> updateSummaryPreferVttSubtitles(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('summaryPreferVttSubtitles', value);

    final currentData = state.value ?? {};
    state = AsyncValue.data({
      ...currentData,
      'summaryPreferVttSubtitles': value,
    });
  }
}

@riverpod
Future<SummaryModelValidationResult> summaryModelValidation(Ref ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final modelPath = (settings['summaryModelPath'] as String? ?? '').trim();

  if (modelPath.isEmpty) {
    return const SummaryModelValidationResult.invalid('Not configured');
  }

  final file = File(modelPath);
  if (!await file.exists()) {
    return const SummaryModelValidationResult.invalid('Missing');
  }

  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    return const SummaryModelValidationResult.invalid('Invalid');
  }

  if (!modelPath.toLowerCase().endsWith('.bin')) {
    return const SummaryModelValidationResult.invalid('Invalid');
  }

  if (await file.length() <= 0) {
    return const SummaryModelValidationResult.invalid('Invalid');
  }

  return const SummaryModelValidationResult.valid('Ready');
}

Map<String, String> _readDownloadedManagedModels(SharedPreferences prefs) {
  final raw = prefs.getString('summaryDownloadedManagedModels');
  if (raw == null || raw.isEmpty) {
    return <String, String>{};
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, String>{};
    }

    return decoded.map<String, String>((key, value) {
      return MapEntry(key.toString(), value.toString());
    });
  } catch (_) {
    return <String, String>{};
  }
}

Map<String, String> _coerceDownloadedManagedModels(
  Map<String, dynamic>? state,
) {
  final raw = state?['summaryDownloadedManagedModels'];
  if (raw is Map) {
    return raw.map<String, String>((key, value) {
      return MapEntry(key.toString(), value.toString());
    });
  }

  return <String, String>{};
}

Future<Map<String, String>> _resolveDownloadedManagedModels(
  SharedPreferences prefs,
) async {
  final managedDirectoryPath =
      prefs.getString('summaryManagedModelDirectoryPath') ?? '';
  final persistedModels = _readDownloadedManagedModels(prefs);
  final availableModelIds = builtInWhisperModelCatalog
      .map((entry) => entry.id)
      .toSet();

  Map<String, String> resolvedModels;
  if (managedDirectoryPath.trim().isNotEmpty) {
    final managedDirectory = Directory(managedDirectoryPath);
    if (await managedDirectory.exists()) {
      resolvedModels = <String, String>{};
      await for (final entity in managedDirectory.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }

        final normalizedPath = entity.path.replaceAll('\\', '/');
        final fileName = normalizedPath.split('/').last;
        final match = RegExp(r'^ggml-(.+)\.bin$').firstMatch(fileName);
        final modelId = match?.group(1);
        if (modelId == null || !availableModelIds.contains(modelId)) {
          continue;
        }

        if (await entity.length() > 0) {
          resolvedModels[modelId] = entity.path;
        }
      }
    } else {
      resolvedModels = <String, String>{};
    }
  } else {
    resolvedModels = <String, String>{};
    for (final entry in persistedModels.entries) {
      final file = File(entry.value);
      if (await file.exists() && await file.length() > 0) {
        resolvedModels[entry.key] = entry.value;
      }
    }
  }

  await prefs.setString(
    'summaryDownloadedManagedModels',
    jsonEncode(resolvedModels),
  );

  final sourceValue =
      prefs.getString('summaryModelSource') ??
      SummaryModelSourceMode.managedDownload.value;
  if (sourceValue == SummaryModelSourceMode.managedDownload.value) {
    final selectedModelId = prefs.getString('summarySelectedModelId');
    final managedModelPath = selectedModelId == null
        ? ''
        : (resolvedModels[selectedModelId] ?? '');
    if (managedModelPath.isEmpty) {
      await prefs.remove('summaryModelPath');
    } else {
      await prefs.setString('summaryModelPath', managedModelPath);
    }
  }

  return resolvedModels;
}

String _resolveSummaryModelPath({
  required String sourceValue,
  required String? selectedModelId,
  required Map<String, String> downloadedManagedModels,
  required String localModelPath,
}) {
  if (sourceValue == SummaryModelSourceMode.managedDownload.value) {
    if (selectedModelId == null || selectedModelId.isEmpty) {
      return '';
    }

    return downloadedManagedModels[selectedModelId] ?? '';
  }

  return localModelPath;
}
