import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_controller.dart';
import 'status_message_provider.dart';
import 'video_selection_controller.dart';

enum CatalogSelectionPhase { idle, loading, failed }

final class CatalogSelectionState {
  const CatalogSelectionState.idle({this.error})
    : phase = CatalogSelectionPhase.idle;

  const CatalogSelectionState.loading()
    : phase = CatalogSelectionPhase.loading,
      error = null;

  const CatalogSelectionState.failed(this.error)
    : phase = CatalogSelectionPhase.failed;

  final CatalogSelectionPhase phase;
  final Object? error;

  bool get isLoading => phase == CatalogSelectionPhase.loading;
}

/// Coordinates bounded catalog selection queries with the independent
/// selection-state controller. Query results are committed only if the user
/// intent and candidate scope are still current.
class CatalogSelectionController extends Notifier<CatalogSelectionState> {
  int _generation = 0;

  @override
  CatalogSelectionState build() {
    ref.listen<CatalogCriteria>(catalogBaseCriteriaProvider, (_, __) {
      _invalidate();
    });
    ref.listen<VideoSelectionState>(videoSelectionControllerProvider, (_, __) {
      _invalidate();
    });
    ref.onDispose(() => _generation++);
    return const CatalogSelectionState.idle();
  }

  Future<void> select(CatalogSelectionMode mode, int count) async {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    final generation = ++_generation;
    if (count == 0) {
      ref.read(videoSelectionControllerProvider.notifier).clear();
      state = const CatalogSelectionState.idle();
      return;
    }

    state = const CatalogSelectionState.loading();
    try {
      final ids = await ref.read(catalogSelectVideoIdsProvider)(
        criteria: ref.read(catalogBaseCriteriaProvider),
        mode: mode,
        count: count,
      );
      if (generation != _generation) return;
      ref.read(videoSelectionControllerProvider.notifier).replaceSelection(ids);
      state = const CatalogSelectionState.idle();
      if (ids.length < count) {
        final metric = switch (mode) {
          CatalogSelectionMode.random => 'matching',
          CatalogSelectionMode.sizeLargest ||
          CatalogSelectionMode.sizeSmallest =>
            'matching videos with a known size',
          CatalogSelectionMode.durationShortest ||
          CatalogSelectionMode.durationLongest =>
            'matching videos with a known duration',
        };
        ref
            .read(statusMessageProvider.notifier)
            .set('Selected ${ids.length} of $count $metric.');
      }
    } catch (error) {
      if (generation != _generation) return;
      state = CatalogSelectionState.failed(error);
      ref
          .read(statusMessageProvider.notifier)
          .set('Couldn’t select videos. $error');
    }
  }

  void invalidate() => _invalidate();

  void _invalidate() {
    _generation++;
    if (state.isLoading) {
      state = const CatalogSelectionState.idle();
    }
  }
}

final catalogSelectionControllerProvider =
    NotifierProvider<CatalogSelectionController, CatalogSelectionState>(
      CatalogSelectionController.new,
    );
