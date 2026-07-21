import 'package:flutter_test/flutter_test.dart';

import '../tool/visual_review/visual_review_fixture.dart';

void main() {
  test('capture selection expands deterministic review matrix', () {
    final selection = VisualReviewCaptureSelection.parse(
      screen: 'all',
      theme: 'dark',
      size: '800x600',
    );

    expect(selection.cases, hasLength(4));
    expect(selection.cases.map((capture) => capture.fileName), <String>[
      'grid-dark-800x600.png',
      'selection-dark-800x600.png',
      'settings-dark-800x600.png',
      'move-dark-800x600.png',
    ]);
  });

  test('capture selection rejects unsupported Dart define values', () {
    expect(
      () => VisualReviewCaptureSelection.parse(
        screen: 'catalog',
        theme: 'light',
        size: '1200x800',
      ),
      throwsArgumentError,
    );
  });

  test(
    'fixture uses fixed synthetic data with privacy and error states',
    () async {
      final fixture = await VisualReviewFixture.create();
      addTearDown(fixture.dispose);

      expect(fixture.folders, hasLength(4));
      expect(fixture.videos, hasLength(8));
      expect(fixture.folders.any((folder) => folder.isPrivate), isTrue);
      expect(
        fixture.folders.any((folder) => folder.securityScopedBookmark == null),
        isTrue,
      );
      expect(fixture.videos.any((video) => video.isOffline), isTrue);
      expect(
        fixture.folders.every(
          (folder) => folder.path.contains('VisualReviewFixture'),
        ),
        isTrue,
      );
      expect(
        fixture.videos.every(
          (video) => video.absolutePath.contains('VisualReviewFixture'),
        ),
        isTrue,
      );
    },
  );
}
