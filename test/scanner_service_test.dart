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
      final transportStreamVideo = File(p.join(root.path, 'clip.ts'));
      await transportStreamVideo.writeAsBytes(const <int>[4, 5, 6]);
      final uppercaseTransportStreamVideo = File(p.join(root.path, 'UPPER.TS'));
      await uppercaseTransportStreamVideo.writeAsBytes(const <int>[7, 8, 9]);
      await File(
        p.join(root.path, '._real.mp4'),
      ).writeAsBytes(const <int>[10, 11, 12]);
      await File(
        p.join(root.path, '._clip.ts'),
      ).writeAsBytes(const <int>[13, 14, 15]);
      await File(
        p.join(root.path, 'downloading.mp4.part'),
      ).writeAsBytes(const <int>[16, 17, 18]);
      await File(
        p.join(root.path, 'downloading.ts.part'),
      ).writeAsBytes(const <int>[19, 20, 21]);
      await File(
        p.join(root.path, 'download-state.mp4.ytdl'),
      ).writeAsBytes(const <int>[22, 23, 24]);
      await File(
        p.join(root.path, 'download-state.ts.ytdl'),
      ).writeAsBytes(const <int>[25, 26, 27]);
      await File(p.join(root.path, 'subtitle.vtt')).writeAsString('WEBVTT');

      final paths = await ScannerService()
          .scanPaths(<String>[root.path])
          .expand((batch) => batch)
          .toList();

      expect(paths, hasLength(3));
      expect(
        paths,
        containsAll(<String>[
          realVideo.path,
          transportStreamVideo.path,
          uppercaseTransportStreamVideo.path,
        ]),
      );
    },
  );
}
