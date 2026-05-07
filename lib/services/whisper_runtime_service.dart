import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class WhisperRuntimeStatus {
  const WhisperRuntimeStatus({
    required this.isBundled,
    required this.status,
    required this.path,
  });

  final bool isBundled;
  final String status;
  final String path;
}

class WhisperRuntimeService {
  const WhisperRuntimeService({String? executablePath})
    : _executablePath = executablePath;

  final String? _executablePath;

  Future<WhisperRuntimeStatus> getStatus() async {
    final path = bundledRuntimePath(executablePath: _executablePath);
    final file = File(path);
    final isReady = await file.exists() && await _isExecutable(file);

    return WhisperRuntimeStatus(
      isBundled: isReady,
      status: isReady ? 'Bundled runtime ready' : 'Bundled runtime missing',
      path: path,
    );
  }

  static String bundledRuntimePath({String? executablePath}) {
    final executable = executablePath ?? Platform.resolvedExecutable;
    final contentsPath = p.dirname(p.dirname(executable));
    return p.join(contentsPath, 'Resources', 'WhisperRuntime', 'whisper-cli');
  }

  Future<bool> _isExecutable(File file) async {
    final result = await Process.run('/bin/test', ['-x', file.path]);
    return result.exitCode == 0;
  }
}

final whisperRuntimeServiceProvider = Provider<WhisperRuntimeService>((ref) {
  return const WhisperRuntimeService();
});

final whisperRuntimeStatusProvider = FutureProvider<WhisperRuntimeStatus>((
  ref,
) {
  return ref.watch(whisperRuntimeServiceProvider).getStatus();
});
