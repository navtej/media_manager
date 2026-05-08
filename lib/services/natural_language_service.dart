import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/video_summary_models.dart';

class NaturalLanguageService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.moviemanager/natural_language',
  );

  Future<List<String>> extractTags(String text) async {
    return extractTagsStatic(text);
  }

  static Future<List<String>> extractTagsStatic(String text) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('analyzeText', {
        'text': text,
      });
      return result.cast<String>();
    } on PlatformException catch (e) {
      print("Failed to extract tags: '${e.message}'.");
      return [];
    }
  }

  Future<void> openInFinder(String path) async {
    try {
      await _channel.invokeMethod('openInFinder', {'path': path});
    } on PlatformException catch (e) {
      print("Failed to open in Finder: '${e.message}'.");
    }
  }

  Future<void> openFolder(String path) async {
    try {
      await _channel.invokeMethod('openFolder', {'path': path});
    } on PlatformException catch (e) {
      print("Failed to open folder: '${e.message}'.");
    }
  }

  Future<bool> playVideo(
    String path, {
    String? folderPath,
    String? folderBookmark,
  }) async {
    try {
      await _channel.invokeMethod('playVideo', {
        'path': path,
        if (folderPath != null && folderPath.isNotEmpty)
          'folderPath': folderPath,
        if (folderBookmark != null && folderBookmark.isNotEmpty)
          'folderBookmark': folderBookmark,
      });
      return true;
    } on PlatformException catch (e) {
      print("Failed to play video: '${e.message}'.");
      return false;
    }
  }

  Future<String> transcribeAudio({
    required String audioPath,
    required String modelPath,
  }) async {
    final String? transcript;
    try {
      transcript = await _channel.invokeMethod<String>('transcribeAudio', {
        'audioPath': audioPath,
        'modelPath': modelPath,
      });
    } on PlatformException catch (e) {
      final message = (e.message ?? e.code).trim();
      throw StateError('Transcription failed: $message');
    }

    if (transcript == null || transcript.trim().isEmpty) {
      throw const FormatException('Transcript is empty.');
    }

    return transcript.trim();
  }

  Future<StructuredVideoSummary> summarizeTranscript({
    required String title,
    required String metadataJson,
    required String transcript,
  }) async {
    final dynamic raw;
    try {
      raw = await _channel.invokeMethod<dynamic>('summarizeTranscript', {
        'title': title,
        'metadataJson': metadataJson,
        'transcript': transcript,
      });
    } on PlatformException catch (e) {
      if (_shouldUseExtractiveSummaryFallback(e)) {
        return _buildExtractiveSummary(title: title, transcript: transcript);
      }
      final message = (e.message ?? e.code).trim();
      throw StateError('Summary failed: $message');
    }

    if (raw is! Map) {
      throw const FormatException('Summary payload is invalid.');
    }

    return StructuredVideoSummary.fromJson(
      Map<String, dynamic>.from(raw as Map<Object?, Object?>),
    );
  }

  bool _shouldUseExtractiveSummaryFallback(PlatformException error) {
    final message = '${error.code} ${error.message ?? ''}'.toLowerCase();
    if (error.code != 'SUMMARY_ERROR') {
      return false;
    }
    return (message.contains('unsafe') && message.contains('content')) ||
        message.contains('correct format') ||
        message.contains('invalid summary');
  }

  StructuredVideoSummary _buildExtractiveSummary({
    required String title,
    required String transcript,
  }) {
    final sentences = _splitSentences(transcript);
    final highlights = sentences.take(4).toList(growable: false);
    final fallbackTitle = title.trim().isEmpty ? 'this video' : title.trim();
    final synopsis = sentences.take(2).join(' ').trim();
    final keywords = _extractKeywords('$title $transcript');
    final themeBullets = sentences.take(5).toList(growable: false);

    return StructuredVideoSummary(
      synopsis: synopsis.isEmpty
          ? 'A transcript-based summary is available for $fallbackTitle.'
          : synopsis,
      themes: themeBullets.isEmpty
          ? const []
          : [VideoSummaryTheme(title: 'Key Themes', bullets: themeBullets)],
      highlights: highlights.isEmpty
          ? ['Transcript was generated successfully.']
          : highlights,
      keywords: keywords.isEmpty
          ? ['summary', 'transcript', 'video']
          : keywords,
    );
  }

  List<String> _splitSentences(String text) {
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((sentence) => sentence.trim())
        .where((sentence) => sentence.length >= 12)
        .take(8)
        .toList(growable: false);
  }

  List<String> _extractKeywords(String text) {
    const stopWords = {
      'about',
      'after',
      'also',
      'from',
      'have',
      'into',
      'that',
      'their',
      'there',
      'this',
      'video',
      'with',
      'would',
    };
    final seen = <String>{};
    final keywords = <String>[];

    for (final match in RegExp(r"[A-Za-z][A-Za-z0-9'-]{3,}").allMatches(text)) {
      final word = match.group(0)!.trim();
      final normalized = word.toLowerCase();
      if (stopWords.contains(normalized) || !seen.add(normalized)) {
        continue;
      }
      keywords.add(word);
      if (keywords.length == 6) {
        break;
      }
    }

    return keywords;
  }
}

final naturalLanguageServiceProvider = Provider(
  (ref) => NaturalLanguageService(),
);
