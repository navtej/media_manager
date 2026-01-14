import 'package:flutter/services.dart';

class NaturalLanguageService {
  static const MethodChannel _channel = MethodChannel('com.example.moviemanager/natural_language');

  Future<List<String>> extractTags(String text) async {
    return extractTagsStatic(text);
  }

  static Future<List<String>> extractTagsStatic(String text) async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('analyzeText', {'text': text});
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
}
