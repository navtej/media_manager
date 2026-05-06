import 'dart:convert';

enum WhisperModelVariantType { englishOnly, multilingual }

class WhisperModelCatalogEntry {
  const WhisperModelCatalogEntry({
    required this.id,
    required this.displayName,
    required this.variantType,
    required this.family,
    required this.diskSizeLabel,
    required this.diskSizeBytes,
    required this.downloadUrl,
  });

  final String id;
  final String displayName;
  final WhisperModelVariantType variantType;
  final String family;
  final String diskSizeLabel;
  final int diskSizeBytes;
  final String? downloadUrl;
}

class WhisperModelCatalogMetadata {
  const WhisperModelCatalogMetadata({required this.entries});

  final List<WhisperModelCatalogEntry> entries;
}

class WhisperModelCatalogState {
  const WhisperModelCatalogState({
    required this.entries,
    required this.lastRefreshedAt,
    required this.isRefreshing,
    required this.refreshError,
  });

  final List<WhisperModelCatalogEntry> entries;
  final DateTime? lastRefreshedAt;
  final bool isRefreshing;
  final String? refreshError;

  const WhisperModelCatalogState.initial()
    : entries = builtInWhisperModelCatalog,
      lastRefreshedAt = null,
      isRefreshing = false,
      refreshError = null;

  WhisperModelCatalogState copyWith({
    List<WhisperModelCatalogEntry>? entries,
    DateTime? lastRefreshedAt,
    bool? isRefreshing,
    String? refreshError,
  }) {
    return WhisperModelCatalogState(
      entries: entries ?? this.entries,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshError: refreshError,
    );
  }
}

enum ModelDownloadPhase { idle, downloading, completed, failed }

class ModelDownloadState {
  const ModelDownloadState({
    required this.phase,
    required this.modelId,
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.eta,
    required this.error,
  });

  const ModelDownloadState.idle()
    : phase = ModelDownloadPhase.idle,
      modelId = null,
      receivedBytes = 0,
      totalBytes = null,
      bytesPerSecond = 0,
      eta = null,
      error = null;

  final ModelDownloadPhase phase;
  final String? modelId;
  final int receivedBytes;
  final int? totalBytes;
  final double bytesPerSecond;
  final Duration? eta;
  final String? error;

  bool get hasDeterminateProgress =>
      totalBytes != null &&
      totalBytes! > 0 &&
      phase == ModelDownloadPhase.downloading;

  double? get progressFraction {
    if (!hasDeterminateProgress) {
      return null;
    }

    return receivedBytes / totalBytes!;
  }

  int? get percentage {
    final fraction = progressFraction;
    if (fraction == null) {
      return null;
    }

    return (fraction * 100).round().clamp(0, 100);
  }

  String? get percentLabel {
    final value = percentage;
    if (value == null) {
      return null;
    }

    return '$value%';
  }

  String get formattedReceivedBytes => formatBinarySize(receivedBytes);

  String get formattedTotalBytes =>
      totalBytes == null ? 'Unknown' : formatBinarySize(totalBytes!);

  String get formattedBytesPerSecond => formatTransferRate(bytesPerSecond);

  String get formattedEta => eta == null ? 'Unknown' : formatEta(eta!);

  ModelDownloadState copyWith({
    ModelDownloadPhase? phase,
    String? modelId,
    int? receivedBytes,
    int? totalBytes,
    double? bytesPerSecond,
    Duration? eta,
    String? error,
    bool clearError = false,
    bool clearEta = false,
    bool clearTotalBytes = false,
  }) {
    return ModelDownloadState(
      phase: phase ?? this.phase,
      modelId: modelId ?? this.modelId,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: clearTotalBytes ? null : (totalBytes ?? this.totalBytes),
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      eta: clearEta ? null : (eta ?? this.eta),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

String formatBinarySize(num bytes) {
  const units = <String>['B', 'KiB', 'MiB', 'GiB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  return '${value.toStringAsFixed(2)} ${units[unitIndex]}';
}

String formatTransferRate(double bytesPerSecond) {
  return '${formatBinarySize(bytesPerSecond)}/s';
}

String formatEta(Duration eta) {
  final hours = eta.inHours;
  final minutes = eta.inMinutes.remainder(60);
  final seconds = eta.inSeconds.remainder(60);

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

bool isManagedModelPath({
  required String modelPath,
  required String managedDirectoryPath,
}) {
  final normalizedModelPath = modelPath.replaceAll('\\', '/').trim();
  final normalizedManagedDirectory = managedDirectoryPath
      .replaceAll('\\', '/')
      .trim()
      .replaceFirst(RegExp(r'/$'), '');

  if (normalizedModelPath.isEmpty || normalizedManagedDirectory.isEmpty) {
    return false;
  }

  return normalizedModelPath.startsWith('$normalizedManagedDirectory/');
}

WhisperModelCatalogMetadata parseWhisperCppReadmeMetadata(String readme) {
  final modelIds = <String>{};
  final sizeByFamily = <String, ({String label, int bytes})>{};

  final modelRegex = RegExp(r'make\s+-j\s+([a-z0-9\.\-]+)');
  for (final match in modelRegex.allMatches(readme)) {
    final id = match.group(1);
    if (id != null && id.isNotEmpty) {
      modelIds.add(id);
    }
  }

  final plainSizeRegex = RegExp(
    r'^(tiny|base|small|medium|large)\s+([0-9]+(?:\.[0-9]+)?)\s+(MiB|GiB)\b',
  );
  final markdownSizeRegex = RegExp(
    r'^\|\s*(tiny|base|small|medium|large)\s*\|\s*([0-9]+(?:\.[0-9]+)?)\s*(MiB|GiB)\s*\|',
  );

  for (final line in const LineSplitter().convert(readme)) {
    final trimmed = line.trim();
    final match =
        markdownSizeRegex.firstMatch(trimmed) ??
        plainSizeRegex.firstMatch(trimmed);
    if (match == null) {
      continue;
    }

    final family = match.group(1);
    final sizeValue = match.group(2);
    final sizeUnit = match.group(3);
    if (family == null || sizeValue == null || sizeUnit == null) {
      continue;
    }

    sizeByFamily[family] = (
      label: '$sizeValue $sizeUnit',
      bytes: _sizeToBytes(double.parse(sizeValue), sizeUnit),
    );
  }

  final entries =
      modelIds
          .map((id) => _catalogEntryFromId(id, sizeByFamily))
          .whereType<WhisperModelCatalogEntry>()
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  return WhisperModelCatalogMetadata(entries: entries);
}

WhisperModelCatalogEntry? _catalogEntryFromId(
  String id,
  Map<String, ({String label, int bytes})> sizeByFamily,
) {
  final family = id.startsWith('large-') ? 'large' : id.replaceAll('.en', '');
  final size = sizeByFamily[family];
  if (size == null) {
    return null;
  }

  return WhisperModelCatalogEntry(
    id: id,
    displayName: id,
    variantType: id.endsWith('.en')
        ? WhisperModelVariantType.englishOnly
        : WhisperModelVariantType.multilingual,
    family: family,
    diskSizeLabel: size.label,
    diskSizeBytes: size.bytes,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$id.bin',
  );
}

int _sizeToBytes(double size, String unit) {
  if (unit == 'GiB') {
    return (size * 1024 * 1024 * 1024).round();
  }
  return (size * 1024 * 1024).round();
}

const List<WhisperModelCatalogEntry> builtInWhisperModelCatalog = [
  WhisperModelCatalogEntry(
    id: 'tiny.en',
    displayName: 'tiny.en',
    variantType: WhisperModelVariantType.englishOnly,
    family: 'tiny',
    diskSizeLabel: '75 MiB',
    diskSizeBytes: 78643200,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'tiny',
    displayName: 'tiny',
    variantType: WhisperModelVariantType.multilingual,
    family: 'tiny',
    diskSizeLabel: '75 MiB',
    diskSizeBytes: 78643200,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'base.en',
    displayName: 'base.en',
    variantType: WhisperModelVariantType.englishOnly,
    family: 'base',
    diskSizeLabel: '142 MiB',
    diskSizeBytes: 148897792,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'base',
    displayName: 'base',
    variantType: WhisperModelVariantType.multilingual,
    family: 'base',
    diskSizeLabel: '142 MiB',
    diskSizeBytes: 148897792,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'small.en',
    displayName: 'small.en',
    variantType: WhisperModelVariantType.englishOnly,
    family: 'small',
    diskSizeLabel: '466 MiB',
    diskSizeBytes: 488636416,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'small',
    displayName: 'small',
    variantType: WhisperModelVariantType.multilingual,
    family: 'small',
    diskSizeLabel: '466 MiB',
    diskSizeBytes: 488636416,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'medium.en',
    displayName: 'medium.en',
    variantType: WhisperModelVariantType.englishOnly,
    family: 'medium',
    diskSizeLabel: '1.5 GiB',
    diskSizeBytes: 1610612736,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'medium',
    displayName: 'medium',
    variantType: WhisperModelVariantType.multilingual,
    family: 'medium',
    diskSizeLabel: '1.5 GiB',
    diskSizeBytes: 1610612736,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'large-v1',
    displayName: 'large-v1',
    variantType: WhisperModelVariantType.multilingual,
    family: 'large',
    diskSizeLabel: '2.9 GiB',
    diskSizeBytes: 3113851289,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v1.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'large-v2',
    displayName: 'large-v2',
    variantType: WhisperModelVariantType.multilingual,
    family: 'large',
    diskSizeLabel: '2.9 GiB',
    diskSizeBytes: 3113851289,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'large-v3',
    displayName: 'large-v3',
    variantType: WhisperModelVariantType.multilingual,
    family: 'large',
    diskSizeLabel: '2.9 GiB',
    diskSizeBytes: 3113851289,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin',
  ),
  WhisperModelCatalogEntry(
    id: 'large-v3-turbo',
    displayName: 'large-v3-turbo',
    variantType: WhisperModelVariantType.multilingual,
    family: 'large',
    diskSizeLabel: '2.9 GiB',
    diskSizeBytes: 3113851289,
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin',
  ),
];
