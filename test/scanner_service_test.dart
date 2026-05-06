import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/scanner_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'scanPaths returns real videos and skips sidecars and partials',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'scanner-service-test',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final realVideo = File(p.join(root.path, 'real.mp4'));
      await realVideo.writeAsBytes(const <int>[1, 2, 3]);
      await File(
        p.join(root.path, '._real.mp4'),
      ).writeAsBytes(const <int>[4, 5, 6]);
      await File(
        p.join(root.path, 'downloading.mp4.part'),
      ).writeAsBytes(const <int>[7, 8, 9]);
      await File(
        p.join(root.path, 'download-state.mp4.ytdl'),
      ).writeAsBytes(const <int>[10, 11, 12]);
      await File(p.join(root.path, 'subtitle.vtt')).writeAsString('WEBVTT');

      final paths = await ScannerService()
          .scanPaths(<String>[root.path])
          .expand((batch) => batch)
          .toList();

      expect(paths, <String>[realVideo.path]);
    },
  );
}
