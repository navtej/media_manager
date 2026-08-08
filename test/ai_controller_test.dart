import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/ai_controller.dart';

void main() {
  test('shows AI tagging percentage remaining', () {
    expect(
      aiTaggingProgressStatus(remaining: 56, total: 100),
      'AI Tagging: 56 (56%) remaining',
    );
  });

  test('rounds percentage remaining to nearest whole number', () {
    expect(
      aiTaggingProgressStatus(remaining: 1, total: 6),
      'AI Tagging: 1 (17%) remaining',
    );
  });
}
