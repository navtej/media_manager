const summaryManagedModelFileName = 'ggml-base.en.bin';
const summaryManagedModelDownloadUrl =
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin';

class VideoSummaryTheme {
  const VideoSummaryTheme({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  factory VideoSummaryTheme.fromJson(Map<String, dynamic> json) {
    final title = StructuredVideoSummary._normalizeText(json['title']);
    final bullets = StructuredVideoSummary._normalizeStringList(
      json['bullets'],
    );

    if (title.isEmpty || bullets.isEmpty) {
      throw const FormatException('Summary theme title and bullets required.');
    }

    return VideoSummaryTheme(title: title, bullets: bullets);
  }

  Map<String, dynamic> toJson() {
    return {'title': title, 'bullets': bullets};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is VideoSummaryTheme &&
            title == other.title &&
            _listEquals(bullets, other.bullets);
  }

  @override
  int get hashCode => Object.hash(title, Object.hashAll(bullets));
}

class StructuredVideoSummary {
  const StructuredVideoSummary({
    required this.synopsis,
    this.themes = const [],
    required this.highlights,
    required this.keywords,
  });

  final String synopsis;
  final List<VideoSummaryTheme> themes;
  final List<String> highlights;
  final List<String> keywords;

  factory StructuredVideoSummary.fromJson(Map<String, dynamic> json) {
    final synopsis = _normalizeText(json['synopsis']);
    final themes = _normalizeThemes(json['themes']);
    final highlights = _normalizeStringList(json['highlights']);
    final keywords = _normalizeStringList(json['keywords']);

    if (synopsis.isEmpty) {
      throw const FormatException('Summary synopsis is required.');
    }
    if (themes.isEmpty && highlights.isEmpty) {
      throw const FormatException('Summary themes or highlights are required.');
    }
    if (keywords.isEmpty) {
      throw const FormatException('Summary keywords are required.');
    }

    return StructuredVideoSummary(
      synopsis: synopsis,
      themes: themes,
      highlights: highlights,
      keywords: keywords,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'synopsis': synopsis,
      if (themes.isNotEmpty)
        'themes': themes.map((theme) => theme.toJson()).toList(),
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

  static List<VideoSummaryTheme> _normalizeThemes(dynamic value) {
    if (value == null) {
      return const [];
    }
    if (value is! List) {
      throw const FormatException('Summary themes must be a list.');
    }

    return value
        .map((entry) {
          if (entry is! Map) {
            throw const FormatException('Summary theme is invalid.');
          }
          return VideoSummaryTheme.fromJson(
            Map<String, dynamic>.from(entry as Map<Object?, Object?>),
          );
        })
        .toList(growable: false);
  }
}

bool _listEquals<T>(List<T> first, List<T> second) {
  if (identical(first, second)) {
    return true;
  }
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
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
