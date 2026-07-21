import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'visual_review_fixture.dart';

// Capture every screen, theme, and size into build/visual-review:
//   flutter test tool/visual_review/capture_test.dart
//
// Capture one state directly:
//   flutter test tool/visual_review/capture_test.dart \
//     --dart-define=VISUAL_REVIEW_SCREEN=move \
//     --dart-define=VISUAL_REVIEW_THEME=dark \
//     --dart-define=VISUAL_REVIEW_SIZE=800x600
//
// Screen: all, grid, selection, settings, move.
// Theme: all, light, dark. Size: all, 1200x800, 800x600.
// VISUAL_REVIEW_OUTPUT optionally replaces build/visual-review.

const _screen = String.fromEnvironment(
  'VISUAL_REVIEW_SCREEN',
  defaultValue: 'all',
);
const _theme = String.fromEnvironment(
  'VISUAL_REVIEW_THEME',
  defaultValue: 'all',
);
const _size = String.fromEnvironment('VISUAL_REVIEW_SIZE', defaultValue: 'all');
const _output = String.fromEnvironment(
  'VISUAL_REVIEW_OUTPUT',
  defaultValue: 'build/visual-review',
);

void main() {
  testWidgets('capture selected visual review fixtures', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.view.resetDevicePixelRatio();
    });
    final selection = VisualReviewCaptureSelection.parse(
      screen: _screen,
      theme: _theme,
      size: _size,
    );
    final outputDirectory = Directory(_output).absolute;

    for (final capture in selection.cases) {
      final file = await captureVisualReviewCase(
        tester: tester,
        capture: capture,
        outputDirectory: outputDirectory,
      );
      expect(file.lengthSync(), greaterThan(0), reason: file.path);
      stdout.writeln('Captured ${file.path}');
    }
  });
}
