import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/folder_storage_status.dart';

void main() {
  group('FolderStorageStatus', () {
    test('marks volumes paths with bookmarks as removable storage', () {
      final status = FolderStorageStatus.fromFolder(
        path: '/Volumes/Amz_1TB_SSD/YouTubeDL',
        securityScopedBookmark: 'bookmark',
      );

      expect(status.isRemovableStorage, isTrue);
      expect(status.needsRepair, isFalse);
      expect(status.statusLabel, 'Removable storage');
    });

    test('marks volumes paths without bookmarks as needing repair', () {
      final nullBookmarkStatus = FolderStorageStatus.fromFolder(
        path: '/Volumes/Amz_1TB_SSD/YouTubeDL',
        securityScopedBookmark: null,
      );
      final emptyBookmarkStatus = FolderStorageStatus.fromFolder(
        path: '/Volumes/Amz_1TB_SSD/YouTubeDL',
        securityScopedBookmark: '',
      );

      expect(nullBookmarkStatus.isRemovableStorage, isTrue);
      expect(nullBookmarkStatus.needsRepair, isTrue);
      expect(nullBookmarkStatus.statusLabel, 'Access repair required');

      expect(emptyBookmarkStatus.isRemovableStorage, isTrue);
      expect(emptyBookmarkStatus.needsRepair, isTrue);
      expect(emptyBookmarkStatus.statusLabel, 'Access repair required');
    });

    test('marks non-volumes paths with bookmarks as local storage', () {
      final status = FolderStorageStatus.fromFolder(
        path: '/Users/navtej/Videos',
        securityScopedBookmark: 'bookmark',
      );

      expect(status.isRemovableStorage, isFalse);
      expect(status.needsRepair, isFalse);
      expect(status.statusLabel, isNull);
    });
  });
}
