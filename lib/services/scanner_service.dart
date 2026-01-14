import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class ScannerService {
  // Common video extensions
  static const Set<String> _videoExtensions = {'.mp4', '.mkv', '.mov', '.avi', '.webm', '.m4v'};

  /// Scans folders and returns a stream of file path batches.
  /// Using batches reduces Isolate communication overhead.
  Stream<List<String>> scanPaths(List<String> rootPaths) {
    final receivePort = ReceivePort();
    final controller = StreamController<List<String>>();

    // Spawn the isolate
    Isolate.spawn< _ScannerMessage>(
      _scannerEntryPoint,
      _ScannerMessage(rootPaths, receivePort.sendPort),
    ).then((isolate) {
        // Handle stream from isolate
        receivePort.listen((message) {
          if (message == 'DONE') {
            controller.close();
            receivePort.close();
            isolate.kill();
          } else if (message is List<String>) {
            controller.add(message);
          } else if (message is String && message.startsWith('ERROR')) {
            controller.addError(message);
          }
        });
    });

    return controller.stream;
  }

  static void _scannerEntryPoint(_ScannerMessage message) {
    // Forward to async scanner
    _asyncScanner(message);
  }


  static Future<void> _asyncScanner(_ScannerMessage message) async {
    final sendPort = message.sendPort;
    final buffer = <String>[];
    const int batchSize = 100;

    void flush() {
      if (buffer.isNotEmpty) {
        sendPort.send(List<String>.from(buffer));
        buffer.clear();
      }
    }

    try {
      for (final rootPath in message.roots) {
        final dir = Directory(rootPath);
        if (!await dir.exists()) continue;

        try {
          // Use non-recursive stream if we want to control recursion, but recursive list() is fine 
          // as long as we process the stream.
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
               final ext = p.extension(entity.path).toLowerCase();
               if (_videoExtensions.contains(ext)) {
                 buffer.add(entity.path);
                 if (buffer.length >= batchSize) {
                   flush();
                 }
               }
            }
          }
        } catch (e) {
          print('Scanner Error in $rootPath: $e');
        }
      }
      // Final flush
      flush();
    } catch (e) {
      print('Scanner Critical Error: $e');
    } finally {
      sendPort.send('DONE');
    }
  }
}

class _ScannerMessage {
  final List<String> roots;
  final SendPort sendPort;

  _ScannerMessage(this.roots, this.sendPort);
}

final scannerServiceProvider = Provider((ref) => ScannerService());
