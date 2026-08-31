import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/video_summary_models.dart';

typedef SummaryHttpPost =
    Future<SummaryHttpResponse> Function(
      Uri url, {
      required Map<String, String> headers,
      required String body,
    });

class SummaryHttpResponse {
  const SummaryHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class NaturalLanguageService {
  NaturalLanguageService({SummaryHttpPost? summaryHttpPost})
    : _summaryHttpPost = summaryHttpPost ?? _defaultSummaryHttpPost;

  static const MethodChannel _channel = MethodChannel(
    'com.example.moviemanager/natural_language',
  );
  static const _defaultSummaryModel = 'gpt-4o-mini';

  final SummaryHttpPost _summaryHttpPost;

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
    required String apiUrl,
    required String apiKey,
  }) async {
    final trimmedUrl = apiUrl.trim();
    if (trimmedUrl.isEmpty) {
      throw StateError('Summarization API URL is not configured.');
    }

    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError('Summarization API URL is invalid.');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
    };

    try {
      final response = await _summaryHttpPost(
        uri,
        headers: headers,
        body: jsonEncode(
          _buildSummaryRequestPayload(
            title: title,
            metadataJson: metadataJson,
            transcript: transcript,
          ),
        ),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Summarization API failed with status ${response.statusCode}.',
        );
      }

      return _parseOpenAiSummaryResponse(response.body);
    } on FormatException {
      return _buildExtractiveSummary(title: title, transcript: transcript);
    } on StateError {
      rethrow;
    } catch (e) {
      final message = e.toString().trim();
      throw StateError('Summary failed: $message');
    }
  }

  static Future<SummaryHttpResponse> _defaultSummaryHttpPost(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(url);
      headers.forEach(request.headers.set);
      request.write(body);
      final response = await request.close();
      return SummaryHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decoder.bind(response).join(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _buildSummaryRequestPayload({
    required String title,
    required String metadataJson,
    required String transcript,
  }) {
    return {
      'model': _defaultSummaryModel,
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content':
              'Summarize video transcripts as strict JSON with keys '
              'synopsis, themes, highlights, and keywords. '
              'themes must be an array of objects with title and bullets.',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'title': title,
            'metadata': _decodeMetadata(metadataJson),
            'transcript': transcript,
          }),
        },
      ],
    };
  }

  Object _decodeMetadata(String metadataJson) {
    if (metadataJson.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return jsonDecode(metadataJson);
    } catch (_) {
      return metadataJson;
    }
  }

  StructuredVideoSummary _parseOpenAiSummaryResponse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Summary response is invalid.');
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Summary response has no choices.');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw const FormatException('Summary response choice is invalid.');
    }

    final message = firstChoice['message'];
    if (message is! Map) {
      throw const FormatException('Summary response message is invalid.');
    }

    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Summary response content is empty.');
    }

    final summaryJson = jsonDecode(content);
    if (summaryJson is! Map) {
      throw const FormatException('Summary payload is invalid.');
    }

    return StructuredVideoSummary.fromJson(
      Map<String, dynamic>.from(summaryJson as Map<Object?, Object?>),
    );
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
