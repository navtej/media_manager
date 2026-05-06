import 'package:flutter/services.dart';
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

  Future<void> playVideo(String path) async {
    try {
      await _channel.invokeMethod('playVideo', {'path': path});
    } on PlatformException catch (e) {
      print("Failed to play video: '${e.message}'.");
    }
  }

  Future<String> transcribeAudio({
    required String audioPath,
    required String modelPath,
  }) async {
    final transcript = await _channel.invokeMethod<String>('transcribeAudio', {
      'audioPath': audioPath,
      'modelPath': modelPath,
    });

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
    final raw = await _channel.invokeMethod<dynamic>('summarizeTranscript', {
      'title': title,
      'metadataJson': metadataJson,
      'transcript': transcript,
    });

    if (raw is! Map) {
      throw const FormatException('Summary payload is invalid.');
    }

    return StructuredVideoSummary.fromJson(
      Map<String, dynamic>.from(raw as Map<Object?, Object?>),
    );
  }
}
