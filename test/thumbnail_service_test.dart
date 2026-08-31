import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/services/thumbnail_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'deletes only direct regular files in the managed thumbnail directory',
    () async {
      final supportDirectory = await Directory.systemTemp.createTemp(
        'thumbnail-service-test',
      );
      addTearDown(() async {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      });
      final service = ThumbnailService(
        applicationSupportDirectory: () async => supportDirectory,
      );
      final managedThumbnail = File(
        await service.saveThumbnail('managed.jpg', [1, 2, 3]),
      );
      final thumbnailDirectory = managedThumbnail.parent;
      final nestedFile = File(
        p.join(thumbnailDirectory.path, 'nested', 'keep.jpg'),
      );
      final outsideFile = File(p.join(supportDirectory.path, 'outside.jpg'));
      final link = Link(p.join(thumbnailDirectory.path, 'outside-link.jpg'));
      await nestedFile.parent.create(recursive: true);
      await nestedFile.writeAsBytes([4]);
      await outsideFile.writeAsBytes([5]);
      await link.create(outsideFile.path);

      final removed = await service.deleteManagedFiles([
        managedThumbnail.path,
        nestedFile.path,
        outsideFile.path,
        link.path,
      ]);

      expect(removed, 1);
      expect(await managedThumbnail.exists(), isFalse);
      expect(await nestedFile.exists(), isTrue);
      expect(await outsideFile.exists(), isTrue);
      expect(await link.exists(), isTrue);
    },
  );
}
