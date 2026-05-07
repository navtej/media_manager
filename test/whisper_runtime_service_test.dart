import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/whisper_runtime_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test('reports bundled runtime ready from app bundle resources', () async {
    final root = await Directory.systemTemp.createTemp('whisper-runtime-test');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final executable = File(
      p.join(
        root.path,
        'Media Manager.app',
        'Contents',
        'MacOS',
        'Media Manager',
      ),
    );
    await executable.parent.create(recursive: true);
    await executable.writeAsString('');

    final runtime = File(
      p.join(
        root.path,
        'Media Manager.app',
        'Contents',
        'Resources',
        'WhisperRuntime',
        'whisper-cli',
      ),
    );
    await runtime.parent.create(recursive: true);
    await runtime.writeAsString('#!/bin/bash\n');
    await Process.run('/bin/chmod', ['755', runtime.path]);

    final status = await WhisperRuntimeService(
      executablePath: executable.path,
    ).getStatus();

    expect(status.isBundled, isTrue);
    expect(status.status, 'Bundled runtime ready');
    expect(status.path, runtime.path);
  });

  test('reports bundled runtime missing when executable is absent', () async {
    final root = await Directory.systemTemp.createTemp('whisper-runtime-test');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final executable = p.join(
      root.path,
      'Media Manager.app',
      'Contents',
      'MacOS',
      'Media Manager',
    );

    final status = await WhisperRuntimeService(
      executablePath: executable,
    ).getStatus();

    expect(status.isBundled, isFalse);
    expect(status.status, 'Bundled runtime missing');
  });
}
