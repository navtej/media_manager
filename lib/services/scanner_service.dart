import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class ScannerService {
  final Set<String> _videoExtensions = {'.mp4', '.mkv', '.mov', '.avi', '.webm', '.m4v'};

  Future<void> scanFolders(List<String> rootPaths, Function(String) onVideoFound) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(_scannerEntryPoint, _ScannerMessage(rootPaths, receivePort.sendPort));

    await for (final message in receivePort) {
      if (message == 'DONE') {
        break;
      } else if (message is String) {
        onVideoFound(message);
      }
    }
  }

  static void _scannerEntryPoint(_ScannerMessage message) {
    try {
      print('DEBUG ISOLATE: Scanner started for ${message.roots}');
      final extensions = {'.mp4', '.mkv', '.mov', '.avi', '.webm', '.m4v'};
      
      for (final rootPath in message.roots) {
        final dir = Directory(rootPath);
        print('DEBUG ISOLATE: Checking directory $rootPath, exists: ${dir.existsSync()}');
        if (!dir.existsSync()) continue;

        try {
          print('DEBUG ISOLATE: Listing files in $rootPath...');
          final entities = dir.listSync(recursive: true, followLinks: false);
          for (final entity in entities) {
            if (entity is File) {
              if (extensions.contains(p.extension(entity.path).toLowerCase())) {
                 message.sendPort.send(entity.path);
              }
            }
          }
        } catch (e) {
          print('Error scanning $rootPath: $e');
        }
      }
    } finally {
      message.sendPort.send('DONE');
    }
  }
}

class _ScannerMessage {
  final List<String> roots;
  final SendPort sendPort;

  _ScannerMessage(this.roots, this.sendPort);
}

final scannerServiceProvider = Provider((ref) => ScannerService());
