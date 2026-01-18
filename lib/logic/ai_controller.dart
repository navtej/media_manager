import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../data/database.dart';
import '../data/providers.dart';
import '../services/natural_language_service.dart';

part 'ai_controller.g.dart';

@Riverpod(keepAlive: true)
class AIStatus extends _$AIStatus {
  @override
  String build() => ''; // Empty string = Idle
  
  void setStatus(String status) => state = status;
}

@Riverpod(keepAlive: true)
class AIController extends _$AIController {
  bool _isAIWorkerRunning = false;
  bool _isDisposed = false;

  @override
  Future<void> build() async {
    ref.onDispose(() {
      _isDisposed = true;
      print('DEBUG: AIController disposed');
    });
  }

  Future<void> startWorker() async {
    if (_isAIWorkerRunning) return;
    _isAIWorkerRunning = true;
    try {
      await _runAIWorker();
    } finally {
      _isAIWorkerRunning = false;
    }
  }

  Future<void> _runAIWorker() async {
    try {
      final videoDao = ref.read(videosDaoProvider);
      final tagDao = ref.read(tagsDaoProvider);
      final db = ref.read(databaseProvider);

      while (!_isDisposed) {
        // Fetch fresh list of pending videos every loop
        final allVideos = await videoDao.getAllVideos();
        final pending = allVideos.where((v) => !v.aiProcessed).toList();
        
        if (pending.isEmpty) {
          ref.read(aIStatusProvider.notifier).setStatus('');
          break;
        }

        ref.read(aIStatusProvider.notifier).setStatus('AI Tagging: ${pending.length} remaining...');
        
        // Take a batch of up to 4
        final batchSize = pending.length >= 4 ? 4 : pending.length;
        final currentBatch = pending.take(batchSize).toList();

        // Prepare data for Isolate
        final List<Map<String, dynamic>> taskData = currentBatch.map((v) {
          final Map<String, dynamic> meta = jsonDecode(v.metadataJson ?? '{}');
          final Map<String, dynamic> raw = (meta['raw'] as Map?)?.cast<String, dynamic>() ?? {};
          final Map<String, dynamic> format = (raw['format'] as Map?)?.cast<String, dynamic>() ?? {};
          final Map<String, dynamic> tags = (format['tags'] as Map?)?.cast<String, dynamic>() ?? {};
          
          final title = tags['title'] ?? v.title;
          final description = tags['description'] ?? '';
          final synopsis = tags['synopsis'] ?? '';
          
          String promptText = [title, description, synopsis]
              .where((s) => s.toString().isNotEmpty)
              .join('\n');
          
          // Pre-processing
          promptText = promptText.replaceAll(RegExp(r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)'), '');
          promptText = promptText.replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}]', unicode: true), '');
          
          // Extract hashtags
          final hashtagRegex = RegExp(r'#([a-zA-Z][a-zA-Z0-9_]*)(?:\s|$|[^\w])');
          final extractedHashtags = hashtagRegex.allMatches(promptText)
              .map((m) => m.group(1)!)
              .take(7)
              .toList();
          
          return {
            'id': v.id,
            'title': v.title,
            'prompt': promptText,
            'extractedHashtags': extractedHashtags,
          };
        }).toList();

        // RUN IN ISOLATE
        final results = await compute(_aiIsolateWorker, {
          'tasks': taskData,
          'token': RootIsolateToken.instance!,
        });

        // Commit the batch
        final List<int> processedIds = [];
        final List<TagsCompanion> batchTags = [];

        for (final res in (results as List)) {
          final id = res['id'] as int;
          final suggestions = (res['suggestions'] as List).cast<String>();
          final extractedHashtags = (res['extractedHashtags'] as List?)?.cast<String>() ?? [];
          
          final allTags = <String>{...suggestions, ...extractedHashtags};
          
          for (final tag in allTags) {
            batchTags.add(TagsCompanion(
              videoId: drift.Value(id),
              tagText: drift.Value(tag),
              source: drift.Value('auto'),
            ));
          }
          processedIds.add(id);
        }

        if (processedIds.isNotEmpty) {
          await db.transaction(() async {
            if (batchTags.isNotEmpty) {
              await tagDao.insertTagsBatch(batchTags);
            }
            await videoDao.updateVideosAiProcessedBatch(processedIds, true);
          });
        }
      }
    } catch (e) {
      print('ERROR in AI Worker Loop: $e');
    }
  }
}

Future<List<Map<String, dynamic>>> _aiIsolateWorker(Map<String, dynamic> args) async {
  final List<Map<String, dynamic>> tasks = (args['tasks'] as List).cast<Map<String, dynamic>>();
  final RootIsolateToken token = args['token'];
  
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  
  final List<Map<String, dynamic>> results = [];
  for (final task in tasks) {
    final id = task['id'] as int;
    final title = task['title'] as String;
    final prompt = task['prompt'] as String;
    final extractedHashtags = (task['extractedHashtags'] as List?)?.cast<String>() ?? <String>[];
    
    try {
      final suggestions = await NaturalLanguageService.extractTagsStatic(prompt);
      results.add({'id': id, 'suggestions': suggestions, 'extractedHashtags': extractedHashtags});
    } catch (e) {
      print('ERROR in AI Isolate for $title: $e');
      results.add({'id': id, 'suggestions': <String>[], 'extractedHashtags': extractedHashtags});
    }
  }
  
  return results;
}
