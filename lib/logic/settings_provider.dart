import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_configuration.dart';
import 'video_summary_models.dart';
import 'whisper_model_catalog.dart';

export 'settings_configuration.dart';

part 'settings_provider.g.dart';

const _scanIntervalKey = 'scanInterval';
const _batchSizeKey = 'batchSize';
const _themeModeKey = 'themeMode';
const _paginationSizeKey = 'paginationSize';
const _showOfflineMediaKey = 'showOfflineMedia';
const _privateLibraryAutoLockMinutesKey = 'privateLibraryAutoLockMinutes';
const _summaryModelSourceKey = 'summaryModelSource';
const _summaryModelPathKey = 'summaryModelPath';
const _summarySelectedModelIdKey = 'summarySelectedModelId';
const _summaryCatalogLastRefreshedAtKey = 'summaryCatalogLastRefreshedAt';
const _summaryManagedModelDirectoryPathKey = 'summaryManagedModelDirectoryPath';
const _summaryDownloadedManagedModelsKey = 'summaryDownloadedManagedModels';
const _summaryPreferVttSubtitlesKey = 'summaryPreferVttSubtitles';
const _summaryApiUrlKey = 'summaryApiUrl';
const _summaryApiKeyKey = 'summaryApiKey';

abstract interface class SettingsPersistence {
  int? getInt(String key);

  bool? getBool(String key);

  String? getString(String key);

  Future<void> setInt(String key, int value);

  Future<void> setBool(String key, bool value);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

final class SharedPreferencesSettingsPersistence
    implements SettingsPersistence {
  const SharedPreferencesSettingsPersistence(this._preferences);

  final SharedPreferences _preferences;

  @override
  int? getInt(String key) => _preferences.getInt(key);

  @override
  bool? getBool(String key) => _preferences.getBool(key);

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  Future<void> setInt(String key, int value) async {
    await _preferences.setInt(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _preferences.setBool(key, value);
  }

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}

final settingsPersistenceProvider = FutureProvider<SettingsPersistence>((
  ref,
) async {
  final preferences = await SharedPreferences.getInstance();
  return SharedPreferencesSettingsPersistence(preferences);
});

final librarySynchronizationConfigurationProvider =
    Provider<AsyncValue<LibrarySynchronizationConfiguration>>((ref) {
      return ref
          .watch(settingsProvider)
          .whenData((settings) => settings.librarySynchronization);
    });

final privateLibraryAccessConfigurationProvider =
    Provider<AsyncValue<PrivateLibraryAccessConfiguration>>((ref) {
      return ref
          .watch(settingsProvider)
          .whenData((settings) => settings.privateLibraryAccess);
    });

final appearanceConfigurationProvider =
    Provider<AsyncValue<AppearanceConfiguration>>((ref) {
      return ref
          .watch(settingsProvider)
          .whenData((settings) => settings.appearance);
    });

final catalogBrowsingConfigurationProvider =
    Provider<AsyncValue<CatalogBrowsingConfiguration>>((ref) {
      return ref
          .watch(settingsProvider)
          .whenData((settings) => settings.catalogBrowsing);
    });

final showOfflineMediaProvider = Provider<bool>((ref) {
  return ref
          .watch(catalogBrowsingConfigurationProvider)
          .asData
          ?.value
          .showOfflineMedia ??
      CatalogBrowsingConfiguration.defaults.showOfflineMedia;
});

final catalogPageSizeProvider = Provider<int>((ref) {
  return ref
          .watch(catalogBrowsingConfigurationProvider)
          .asData
          ?.value
          .paginationSize ??
      CatalogBrowsingConfiguration.defaults.paginationSize;
});

final videoSummaryConfigurationProvider =
    Provider<AsyncValue<VideoSummaryConfiguration>>((ref) {
      return ref
          .watch(settingsProvider)
          .whenData((settings) => settings.videoSummary);
    });

final privateLibraryAutoLockDurationProvider = Provider<Duration>((ref) {
  return ref
          .watch(privateLibraryAccessConfigurationProvider)
          .asData
          ?.value
          .autoLockDuration ??
      PrivateLibraryAccessConfiguration.defaults.autoLockDuration;
});

@Riverpod(keepAlive: true)
class Settings extends _$Settings {
  Future<AppSettings>? _loadingSettings;

  @override
  Future<AppSettings> build() {
    return _loadingSettings = _loadSettings();
  }

  Future<AppSettings> _loadSettings() async {
    final persistence = await ref.watch(settingsPersistenceProvider.future);
    final downloadedManagedModels = await _resolveDownloadedManagedModels(
      persistence,
    );
    final videoSummary = VideoSummaryConfiguration.resolve(
      modelSourceValue: persistence.getString(_summaryModelSourceKey),
      modelPath: persistence.getString(_summaryModelPathKey),
      selectedModelId: persistence.getString(_summarySelectedModelIdKey),
      catalogLastRefreshedAtValue: persistence.getString(
        _summaryCatalogLastRefreshedAtKey,
      ),
      managedModelDirectoryPath: persistence.getString(
        _summaryManagedModelDirectoryPathKey,
      ),
      downloadedManagedModels: downloadedManagedModels,
      preferVttSubtitles: persistence.getBool(_summaryPreferVttSubtitlesKey),
      apiUrl: persistence.getString(_summaryApiUrlKey),
      apiKey: persistence.getString(_summaryApiKeyKey),
    );
    await _persistResolvedModelPath(persistence, videoSummary.modelPath);

    return AppSettings(
      librarySynchronization: LibrarySynchronizationConfiguration.resolve(
        scanIntervalMinutes: persistence.getInt(_scanIntervalKey),
        batchSize: persistence.getInt(_batchSizeKey),
      ),
      privateLibraryAccess: PrivateLibraryAccessConfiguration.resolve(
        autoLockMinutes: persistence.getInt(_privateLibraryAutoLockMinutesKey),
      ),
      appearance: AppearanceConfiguration.resolve(
        themeMode: persistence.getString(_themeModeKey),
      ),
      catalogBrowsing: CatalogBrowsingConfiguration.resolve(
        paginationSize: persistence.getInt(_paginationSizeKey),
        showOfflineMedia: persistence.getBool(_showOfflineMediaKey),
      ),
      videoSummary: videoSummary,
    );
  }

  Future<void> updateSettings(
    int scanInterval,
    int batchSize,
    int paginationSize,
  ) async {
    final current = await _currentSettings();
    final synchronization = LibrarySynchronizationConfiguration.resolve(
      scanIntervalMinutes: scanInterval,
      batchSize: batchSize,
    );
    final catalog = CatalogBrowsingConfiguration.resolve(
      paginationSize: paginationSize,
      showOfflineMedia: current.catalogBrowsing.showOfflineMedia,
    );
    final persistence = await _persistence();
    await persistence.setInt(
      _scanIntervalKey,
      synchronization.scanIntervalMinutes,
    );
    await persistence.setInt(_batchSizeKey, synchronization.batchSize);
    await persistence.setInt(_paginationSizeKey, catalog.paginationSize);
    state = AsyncData(
      current.copyWith(
        librarySynchronization: synchronization,
        catalogBrowsing: catalog,
      ),
    );
  }

  Future<void> updateShowOfflineMedia(bool value) async {
    final current = await _currentSettings();
    final catalog = CatalogBrowsingConfiguration.resolve(
      paginationSize: current.catalogBrowsing.paginationSize,
      showOfflineMedia: value,
    );
    final persistence = await _persistence();
    await persistence.setBool(_showOfflineMediaKey, value);
    state = AsyncData(current.copyWith(catalogBrowsing: catalog));
  }

  Future<void> updatePrivateLibraryAutoLockMinutes(int minutes) async {
    final validated =
        PrivateLibraryAccessConfiguration.requireValidAutoLockMinutes(minutes);
    final current = await _currentSettings();
    final configuration = PrivateLibraryAccessConfiguration.resolve(
      autoLockMinutes: validated,
    );
    final persistence = await _persistence();
    await persistence.setInt(_privateLibraryAutoLockMinutesKey, validated);
    state = AsyncData(current.copyWith(privateLibraryAccess: configuration));
  }

  Future<void> updateTheme(AppearanceThemeMode mode) async {
    final current = await _currentSettings();
    final appearance = AppearanceConfiguration.resolve(themeMode: mode.value);
    final persistence = await _persistence();
    await persistence.setString(_themeModeKey, appearance.themeMode.value);
    state = AsyncData(current.copyWith(appearance: appearance));
  }

  Future<void> updateSummaryModelSource(SummaryModelSourceMode mode) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withModelSource(mode);
    final persistence = await _persistence();
    await persistence.setString(_summaryModelSourceKey, mode.value);
    await _persistResolvedModelPath(persistence, summary.modelPath);
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> setLocalSummaryModelPath(String path) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withLocalModelPath(path);
    final persistence = await _persistence();
    await persistence.setString(
      _summaryModelSourceKey,
      SummaryModelSourceMode.localFile.value,
    );
    await _persistResolvedModelPath(persistence, summary.modelPath);
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> installManagedSummaryModel({
    required String modelId,
    required String path,
    required String managedDirectoryPath,
  }) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withManagedModelInstalled(
      modelId: modelId,
      path: path,
      managedDirectoryPath: managedDirectoryPath,
    );
    final persistence = await _persistence();
    await persistence.setString(
      _summaryModelSourceKey,
      SummaryModelSourceMode.managedDownload.value,
    );
    await persistence.setString(
      _summaryDownloadedManagedModelsKey,
      jsonEncode(summary.downloadedManagedModels),
    );
    await persistence.setString(_summarySelectedModelIdKey, modelId);
    await persistence.setString(_summaryModelPathKey, path);
    await persistence.setString(
      _summaryManagedModelDirectoryPathKey,
      managedDirectoryPath,
    );
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> removeDownloadedManagedModel(String modelId) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withoutDownloadedManagedModel(modelId);
    final persistence = await _persistence();
    await persistence.setString(
      _summaryDownloadedManagedModelsKey,
      jsonEncode(summary.downloadedManagedModels),
    );
    await _persistResolvedModelPath(persistence, summary.modelPath);
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> selectManagedSummaryModel(String? modelId) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withManagedSelection(modelId);
    final persistence = await _persistence();
    await persistence.setString(
      _summaryModelSourceKey,
      SummaryModelSourceMode.managedDownload.value,
    );
    await _persistNullableString(
      persistence,
      _summarySelectedModelIdKey,
      summary.selectedModelId,
    );
    await _persistResolvedModelPath(persistence, summary.modelPath);
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> clearSummaryModelPath() async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withoutModelPath();
    final persistence = await _persistence();
    await persistence.remove(_summaryModelPathKey);
    if (current.videoSummary.modelSource ==
        SummaryModelSourceMode.managedDownload) {
      await persistence.remove(_summarySelectedModelIdKey);
    }
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> updateSummaryCatalogLastRefreshedAt(DateTime? timestamp) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withCatalogLastRefreshedAt(timestamp);
    final persistence = await _persistence();
    await _persistNullableString(
      persistence,
      _summaryCatalogLastRefreshedAtKey,
      timestamp?.toIso8601String(),
    );
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> updateSummaryPreferVttSubtitles(bool value) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withPreferVttSubtitles(value);
    final persistence = await _persistence();
    await persistence.setBool(_summaryPreferVttSubtitlesKey, value);
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> updateSummaryApiUrl(String value) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withApiUrl(value);
    final persistence = await _persistence();
    await _persistNullableString(
      persistence,
      _summaryApiUrlKey,
      summary.apiUrl.isEmpty ? null : summary.apiUrl,
    );
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<void> updateSummaryApiKey(String value) async {
    final current = await _currentSettings();
    final summary = current.videoSummary.withApiKey(value);
    final persistence = await _persistence();
    await _persistNullableString(
      persistence,
      _summaryApiKeyKey,
      summary.apiKey.isEmpty ? null : summary.apiKey,
    );
    state = AsyncData(current.copyWith(videoSummary: summary));
  }

  Future<AppSettings> _currentSettings() async {
    final current = state.value;
    if (current != null) {
      return current;
    }
    final loading = _loadingSettings;
    if (loading != null) {
      return loading;
    }
    throw StateError('Settings have not started loading.');
  }

  Future<SettingsPersistence> _persistence() {
    return ref.read(settingsPersistenceProvider.future);
  }
}

@riverpod
Future<SummaryModelValidationResult> summaryModelValidation(Ref ref) async {
  final summary = (await ref.watch(settingsProvider.future)).videoSummary;
  final modelPath = summary.modelPath.trim();

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

Future<Map<String, String>> _resolveDownloadedManagedModels(
  SettingsPersistence persistence,
) async {
  final managedDirectoryPath =
      persistence.getString(_summaryManagedModelDirectoryPathKey) ?? '';
  final persistedModels = _readDownloadedManagedModels(persistence);
  final availableModelIds = builtInWhisperModelCatalog
      .map((entry) => entry.id)
      .toSet();

  final resolvedModels = <String, String>{};
  if (managedDirectoryPath.trim().isNotEmpty) {
    final managedDirectory = Directory(managedDirectoryPath);
    if (await managedDirectory.exists()) {
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
    }
  } else {
    for (final entry in persistedModels.entries) {
      final file = File(entry.value);
      if (await file.exists() && await file.length() > 0) {
        resolvedModels[entry.key] = entry.value;
      }
    }
  }

  await persistence.setString(
    _summaryDownloadedManagedModelsKey,
    jsonEncode(resolvedModels),
  );
  return resolvedModels;
}

Map<String, String> _readDownloadedManagedModels(
  SettingsPersistence persistence,
) {
  final raw = persistence.getString(_summaryDownloadedManagedModelsKey);
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

Future<void> _persistResolvedModelPath(
  SettingsPersistence persistence,
  String modelPath,
) {
  return _persistNullableString(
    persistence,
    _summaryModelPathKey,
    modelPath.isEmpty ? null : modelPath,
  );
}

Future<void> _persistNullableString(
  SettingsPersistence persistence,
  String key,
  String? value,
) async {
  if (value == null || value.isEmpty) {
    await persistence.remove(key);
  } else {
    await persistence.setString(key, value);
  }
}
