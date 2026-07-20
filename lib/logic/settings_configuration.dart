import 'video_summary_models.dart';

final class LibrarySynchronizationConfiguration {
  const LibrarySynchronizationConfiguration._({
    required this.scanIntervalMinutes,
    required this.batchSize,
  });

  static const defaultScanIntervalMinutes = 5;
  static const defaultBatchSize = 4;
  static const defaults = LibrarySynchronizationConfiguration._(
    scanIntervalMinutes: defaultScanIntervalMinutes,
    batchSize: defaultBatchSize,
  );

  factory LibrarySynchronizationConfiguration.resolve({
    int? scanIntervalMinutes,
    int? batchSize,
  }) {
    return LibrarySynchronizationConfiguration._(
      scanIntervalMinutes: _positiveOrDefault(
        scanIntervalMinutes,
        defaultScanIntervalMinutes,
      ),
      batchSize: _positiveOrDefault(batchSize, defaultBatchSize),
    );
  }

  final int scanIntervalMinutes;
  final int batchSize;
}

final class EmptyFolderCleanupConfiguration {
  const EmptyFolderCleanupConfiguration._({
    required this.enabled,
    required this.intervalDays,
  });

  static const defaultEnabled = true;
  static const defaultIntervalDays = 7;
  static const minimumIntervalDays = 1;
  static const maximumIntervalDays = 90;
  static const defaults = EmptyFolderCleanupConfiguration._(
    enabled: defaultEnabled,
    intervalDays: defaultIntervalDays,
  );

  factory EmptyFolderCleanupConfiguration.resolve({
    bool? enabled,
    int? intervalDays,
  }) {
    return EmptyFolderCleanupConfiguration._(
      enabled: enabled ?? defaultEnabled,
      intervalDays: isValidIntervalDays(intervalDays)
          ? intervalDays!
          : defaultIntervalDays,
    );
  }

  final bool enabled;
  final int intervalDays;

  Duration get interval => Duration(days: intervalDays);

  static bool isValidIntervalDays(int? days) {
    return days != null &&
        days >= minimumIntervalDays &&
        days <= maximumIntervalDays;
  }

  static int requireValidIntervalDays(int days) {
    if (!isValidIntervalDays(days)) {
      throw RangeError.range(
        days,
        minimumIntervalDays,
        maximumIntervalDays,
        'days',
      );
    }
    return days;
  }
}

final class PrivateLibraryAccessConfiguration {
  const PrivateLibraryAccessConfiguration._({required this.autoLockMinutes});

  static const defaultAutoLockMinutes = 10;
  static const minimumAutoLockMinutes = 1;
  static const maximumAutoLockMinutes = 120;
  static const defaults = PrivateLibraryAccessConfiguration._(
    autoLockMinutes: defaultAutoLockMinutes,
  );

  factory PrivateLibraryAccessConfiguration.resolve({int? autoLockMinutes}) {
    return PrivateLibraryAccessConfiguration._(
      autoLockMinutes: isValidAutoLockMinutes(autoLockMinutes)
          ? autoLockMinutes!
          : defaultAutoLockMinutes,
    );
  }

  final int autoLockMinutes;

  Duration get autoLockDuration => Duration(minutes: autoLockMinutes);

  static bool isValidAutoLockMinutes(int? minutes) {
    return minutes != null &&
        minutes >= minimumAutoLockMinutes &&
        minutes <= maximumAutoLockMinutes;
  }

  static int requireValidAutoLockMinutes(int minutes) {
    if (!isValidAutoLockMinutes(minutes)) {
      throw RangeError.range(
        minutes,
        minimumAutoLockMinutes,
        maximumAutoLockMinutes,
        'minutes',
      );
    }
    return minutes;
  }
}

enum AppearanceThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const AppearanceThemeMode(this.value);

  final String value;

  static AppearanceThemeMode fromValue(String? value) {
    return AppearanceThemeMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => AppearanceThemeMode.system,
    );
  }
}

final class AppearanceConfiguration {
  const AppearanceConfiguration._({required this.themeMode});

  static const defaultThemeMode = AppearanceThemeMode.system;
  static const defaults = AppearanceConfiguration._(
    themeMode: defaultThemeMode,
  );

  factory AppearanceConfiguration.resolve({String? themeMode}) {
    return AppearanceConfiguration._(
      themeMode: AppearanceThemeMode.fromValue(themeMode),
    );
  }

  final AppearanceThemeMode themeMode;
}

final class CatalogBrowsingConfiguration {
  const CatalogBrowsingConfiguration._({
    required this.paginationSize,
    required this.showOfflineMedia,
  });

  static const defaultPaginationSize = 50;
  static const defaultShowOfflineMedia = true;
  static const defaults = CatalogBrowsingConfiguration._(
    paginationSize: defaultPaginationSize,
    showOfflineMedia: defaultShowOfflineMedia,
  );

  factory CatalogBrowsingConfiguration.resolve({
    int? paginationSize,
    bool? showOfflineMedia,
  }) {
    return CatalogBrowsingConfiguration._(
      paginationSize: _positiveOrDefault(paginationSize, defaultPaginationSize),
      showOfflineMedia: showOfflineMedia ?? defaultShowOfflineMedia,
    );
  }

  final int paginationSize;
  final bool showOfflineMedia;
}

final class VideoSummaryConfiguration {
  const VideoSummaryConfiguration._({
    required this.modelSource,
    required this.modelPath,
    required this.selectedModelId,
    required this.catalogLastRefreshedAt,
    required this.managedModelDirectoryPath,
    required this.downloadedManagedModels,
    required this.preferVttSubtitles,
    required this.apiUrl,
    required this.apiKey,
  });

  static const defaultModelSource = SummaryModelSourceMode.managedDownload;
  static const defaultPreferVttSubtitles = true;
  static const defaults = VideoSummaryConfiguration._(
    modelSource: defaultModelSource,
    modelPath: '',
    selectedModelId: null,
    catalogLastRefreshedAt: null,
    managedModelDirectoryPath: '',
    downloadedManagedModels: <String, String>{},
    preferVttSubtitles: defaultPreferVttSubtitles,
    apiUrl: '',
    apiKey: '',
  );

  factory VideoSummaryConfiguration.resolve({
    String? modelSourceValue,
    String? modelPath,
    String? selectedModelId,
    String? catalogLastRefreshedAtValue,
    String? managedModelDirectoryPath,
    Map<String, String>? downloadedManagedModels,
    bool? preferVttSubtitles,
    String? apiUrl,
    String? apiKey,
  }) {
    final source = SummaryModelSourceMode.fromValue(
      modelSourceValue ?? defaultModelSource.value,
    );
    final models = Map<String, String>.unmodifiable(
      downloadedManagedModels ?? const <String, String>{},
    );
    final normalizedSelectedModelId = _nonEmptyOrNull(selectedModelId);
    final resolvedModelPath = source == SummaryModelSourceMode.managedDownload
        ? normalizedSelectedModelId == null
              ? ''
              : models[normalizedSelectedModelId] ?? ''
        : modelPath ?? '';

    return VideoSummaryConfiguration._(
      modelSource: source,
      modelPath: resolvedModelPath,
      selectedModelId: normalizedSelectedModelId,
      catalogLastRefreshedAt: catalogLastRefreshedAtValue == null
          ? null
          : DateTime.tryParse(catalogLastRefreshedAtValue),
      managedModelDirectoryPath: managedModelDirectoryPath ?? '',
      downloadedManagedModels: models,
      preferVttSubtitles: preferVttSubtitles ?? defaultPreferVttSubtitles,
      apiUrl: (apiUrl ?? '').trim(),
      apiKey: (apiKey ?? '').trim(),
    );
  }

  final SummaryModelSourceMode modelSource;
  final String modelPath;
  final String? selectedModelId;
  final DateTime? catalogLastRefreshedAt;
  final String managedModelDirectoryPath;
  final Map<String, String> downloadedManagedModels;
  final bool preferVttSubtitles;
  final String apiUrl;
  final String apiKey;

  VideoSummaryConfiguration withModelSource(SummaryModelSourceMode source) {
    final nextPath = switch (source) {
      SummaryModelSourceMode.managedDownload =>
        selectedModelId == null
            ? ''
            : downloadedManagedModels[selectedModelId] ?? '',
      SummaryModelSourceMode.localFile =>
        modelSource == SummaryModelSourceMode.localFile ? modelPath : '',
    };
    return _copy(modelSource: source, modelPath: nextPath);
  }

  VideoSummaryConfiguration withLocalModelPath(String path) {
    return _copy(
      modelSource: SummaryModelSourceMode.localFile,
      modelPath: path,
    );
  }

  VideoSummaryConfiguration withManagedModelInstalled({
    required String modelId,
    required String path,
    required String managedDirectoryPath,
  }) {
    final models = <String, String>{...downloadedManagedModels, modelId: path};
    return _copy(
      modelSource: SummaryModelSourceMode.managedDownload,
      modelPath: path,
      selectedModelId: modelId,
      replaceSelectedModelId: true,
      managedModelDirectoryPath: managedDirectoryPath,
      downloadedManagedModels: models,
    );
  }

  VideoSummaryConfiguration withManagedSelection(String? modelId) {
    final normalizedModelId = _nonEmptyOrNull(modelId);
    return _copy(
      modelSource: SummaryModelSourceMode.managedDownload,
      modelPath: normalizedModelId == null
          ? ''
          : downloadedManagedModels[normalizedModelId] ?? '',
      selectedModelId: normalizedModelId,
      replaceSelectedModelId: true,
    );
  }

  VideoSummaryConfiguration withoutDownloadedManagedModel(String modelId) {
    final models = <String, String>{...downloadedManagedModels}
      ..remove(modelId);
    return _copy(
      modelPath: selectedModelId == modelId
          ? ''
          : modelSource == SummaryModelSourceMode.managedDownload
          ? selectedModelId == null
                ? ''
                : models[selectedModelId] ?? ''
          : modelPath,
      downloadedManagedModels: models,
    );
  }

  VideoSummaryConfiguration withoutModelPath() {
    return _copy(
      modelPath: '',
      selectedModelId: modelSource == SummaryModelSourceMode.managedDownload
          ? null
          : selectedModelId,
      replaceSelectedModelId: true,
    );
  }

  VideoSummaryConfiguration withCatalogLastRefreshedAt(DateTime? timestamp) {
    return _copy(
      catalogLastRefreshedAt: timestamp,
      replaceCatalogLastRefreshedAt: true,
    );
  }

  VideoSummaryConfiguration withPreferVttSubtitles(bool value) {
    return _copy(preferVttSubtitles: value);
  }

  VideoSummaryConfiguration withApiUrl(String value) {
    return _copy(apiUrl: value.trim());
  }

  VideoSummaryConfiguration withApiKey(String value) {
    return _copy(apiKey: value.trim());
  }

  VideoSummaryConfiguration _copy({
    SummaryModelSourceMode? modelSource,
    String? modelPath,
    String? selectedModelId,
    bool replaceSelectedModelId = false,
    DateTime? catalogLastRefreshedAt,
    bool replaceCatalogLastRefreshedAt = false,
    String? managedModelDirectoryPath,
    Map<String, String>? downloadedManagedModels,
    bool? preferVttSubtitles,
    String? apiUrl,
    String? apiKey,
  }) {
    return VideoSummaryConfiguration._(
      modelSource: modelSource ?? this.modelSource,
      modelPath: modelPath ?? this.modelPath,
      selectedModelId: replaceSelectedModelId
          ? selectedModelId
          : this.selectedModelId,
      catalogLastRefreshedAt: replaceCatalogLastRefreshedAt
          ? catalogLastRefreshedAt
          : this.catalogLastRefreshedAt,
      managedModelDirectoryPath:
          managedModelDirectoryPath ?? this.managedModelDirectoryPath,
      downloadedManagedModels: Map<String, String>.unmodifiable(
        downloadedManagedModels ?? this.downloadedManagedModels,
      ),
      preferVttSubtitles: preferVttSubtitles ?? this.preferVttSubtitles,
      apiUrl: apiUrl ?? this.apiUrl,
      apiKey: apiKey ?? this.apiKey,
    );
  }
}

final class AppSettings {
  const AppSettings({
    required this.librarySynchronization,
    required this.emptyFolderCleanup,
    required this.privateLibraryAccess,
    required this.appearance,
    required this.catalogBrowsing,
    required this.videoSummary,
  });

  static const defaults = AppSettings(
    librarySynchronization: LibrarySynchronizationConfiguration.defaults,
    emptyFolderCleanup: EmptyFolderCleanupConfiguration.defaults,
    privateLibraryAccess: PrivateLibraryAccessConfiguration.defaults,
    appearance: AppearanceConfiguration.defaults,
    catalogBrowsing: CatalogBrowsingConfiguration.defaults,
    videoSummary: VideoSummaryConfiguration.defaults,
  );

  final LibrarySynchronizationConfiguration librarySynchronization;
  final EmptyFolderCleanupConfiguration emptyFolderCleanup;
  final PrivateLibraryAccessConfiguration privateLibraryAccess;
  final AppearanceConfiguration appearance;
  final CatalogBrowsingConfiguration catalogBrowsing;
  final VideoSummaryConfiguration videoSummary;

  AppSettings copyWith({
    LibrarySynchronizationConfiguration? librarySynchronization,
    EmptyFolderCleanupConfiguration? emptyFolderCleanup,
    PrivateLibraryAccessConfiguration? privateLibraryAccess,
    AppearanceConfiguration? appearance,
    CatalogBrowsingConfiguration? catalogBrowsing,
    VideoSummaryConfiguration? videoSummary,
  }) {
    return AppSettings(
      librarySynchronization:
          librarySynchronization ?? this.librarySynchronization,
      emptyFolderCleanup: emptyFolderCleanup ?? this.emptyFolderCleanup,
      privateLibraryAccess: privateLibraryAccess ?? this.privateLibraryAccess,
      appearance: appearance ?? this.appearance,
      catalogBrowsing: catalogBrowsing ?? this.catalogBrowsing,
      videoSummary: videoSummary ?? this.videoSummary,
    );
  }
}

int _positiveOrDefault(int? value, int fallback) {
  return value != null && value > 0 ? value : fallback;
}

String? _nonEmptyOrNull(String? value) {
  return value == null || value.isEmpty ? null : value;
}
