import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/video_selection_controller.dart';

void main() {
  test('selectRandom replaces selection with the requested loaded videos', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      videoSelectionControllerProvider.notifier,
    );
    controller.selectLoaded([99]);
    controller.selectRandom([1, 2, 3, 4], 2, random: Random(7));

    final selected = container
        .read(videoSelectionControllerProvider)
        .selectedIds;
    expect(selected, hasLength(2));
    expect(selected, everyElement(isIn([1, 2, 3, 4])));
    expect(selected, isNot(contains(99)));
  });

  test('selectRandom clamps a count above the loaded videos', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(
      videoSelectionControllerProvider.notifier,
    );
    controller.selectRandom([1, 2], 8, random: Random(11));

    expect(container.read(videoSelectionControllerProvider).selectedIds, {
      1,
      2,
    });
  });
}
