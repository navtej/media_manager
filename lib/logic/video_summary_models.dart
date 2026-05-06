const summaryManagedModelFileName = 'ggml-base.en.bin';
const summaryManagedModelDownloadUrl =
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin';

class StructuredVideoSummary {
  StructuredVideoSummary({
    required this.synopsis,
    required this.highlights,
    required this.keywords,
  });

  final String synopsis;
  final List<String> highlights;
  final List<String> keywords;

  factory StructuredVideoSummary.fromJson(Map<String, dynamic> json) {
    final synopsis = _normalizeText(json['synopsis']);
    final highlights = _normalizeStringList(json['highlights']);
    final keywords = _normalizeStringList(json['keywords']);

    if (synopsis.isEmpty) {
      throw const FormatException('Summary synopsis is required.');
    }
    if (highlights.isEmpty) {
      throw const FormatException('Summary highlights are required.');
    }
    if (keywords.isEmpty) {
      throw const FormatException('Summary keywords are required.');
    }

    return StructuredVideoSummary(
      synopsis: synopsis,
      highlights: highlights,
      keywords: keywords,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'synopsis': synopsis,
      'highlights': highlights,
      'keywords': keywords,
    };
  }

  static String _normalizeText(dynamic value) {
    if (value is! String) {
      return '';
    }
    return value.trim();
  }

  static List<String> _normalizeStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }
}

class VideoSummaryFreshnessKey {
  const VideoSummaryFreshnessKey({
    required this.sourceVideoSize,
    required this.sourceVideoModifiedAt,
    required this.transcriptModel,
  });

  final int sourceVideoSize;
  final DateTime sourceVideoModifiedAt;
  final String transcriptModel;

  bool matches({
    required int fileSize,
    required DateTime fileModifiedAt,
    required String transcriptModel,
  }) {
    return sourceVideoSize == fileSize &&
        sourceVideoModifiedAt == fileModifiedAt &&
        this.transcriptModel == transcriptModel;
  }
}

enum SummaryModelSourceMode {
  managedDownload('managed'),
  localFile('local');

  const SummaryModelSourceMode(this.value);

  final String value;

  static SummaryModelSourceMode fromValue(String value) {
    return SummaryModelSourceMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => SummaryModelSourceMode.managedDownload,
    );
  }
}

class SummaryModelValidationResult {
  const SummaryModelValidationResult._({
    required this.isValid,
    required this.status,
  });

  const SummaryModelValidationResult.valid(String status)
    : this._(isValid: true, status: status);

  const SummaryModelValidationResult.invalid(String status)
    : this._(isValid: false, status: status);

  final bool isValid;
  final String status;
}

String transcriptModelNameFromPath(String modelPath) {
  if (modelPath.trim().isEmpty) {
    return '';
  }

  final normalized = modelPath.replaceAll('\\', '/');
  final parts = normalized.split('/');
  return parts.isEmpty ? normalized : parts.last.trim();
}
