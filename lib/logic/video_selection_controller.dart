import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class VideoSelectionState {
  const VideoSelectionState({
    this.selectedIds = const <int>{},
    this.anchorVideoId,
    this.showSelectedOnly = false,
  });

  final Set<int> selectedIds;
  final int? anchorVideoId;
  final bool showSelectedOnly;

  bool get hasSelection => selectedIds.isNotEmpty;
  int get count => selectedIds.length;

  bool isSelected(int videoId) => selectedIds.contains(videoId);

  VideoSelectionState copyWith({
    Set<int>? selectedIds,
    int? anchorVideoId,
    bool clearAnchor = false,
    bool? showSelectedOnly,
  }) {
    return VideoSelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
      anchorVideoId: clearAnchor ? null : anchorVideoId ?? this.anchorVideoId,
      showSelectedOnly: showSelectedOnly ?? this.showSelectedOnly,
    );
  }
}

class VideoSelectionController extends Notifier<VideoSelectionState> {
  @override
  VideoSelectionState build() => const VideoSelectionState();

  void toggle(int videoId) {
    final next = Set<int>.from(state.selectedIds);
    if (!next.add(videoId)) {
      next.remove(videoId);
    }
    state = next.isEmpty
        ? const VideoSelectionState()
        : state.copyWith(selectedIds: next, anchorVideoId: videoId);
  }

  void setSelected(int videoId, bool selected) {
    final next = Set<int>.from(state.selectedIds);
    if (selected) {
      next.add(videoId);
    } else {
      next.remove(videoId);
    }
    state = next.isEmpty
        ? const VideoSelectionState()
        : state.copyWith(selectedIds: next, anchorVideoId: videoId);
  }

  void selectWithIntent({
    required int videoId,
    required List<int> orderedVisibleVideoIds,
    required bool isRangeSelection,
    required bool isToggleSelection,
  }) {
    if (isRangeSelection) {
      _selectRange(videoId, orderedVisibleVideoIds);
      return;
    }

    if (isToggleSelection) {
      toggle(videoId);
      return;
    }

    state = VideoSelectionState(selectedIds: {videoId}, anchorVideoId: videoId);
  }

  void _selectRange(int videoId, List<int> orderedVisibleVideoIds) {
    final anchor = state.anchorVideoId;
    final anchorIndex = anchor == null
        ? -1
        : orderedVisibleVideoIds.indexOf(anchor);
    final targetIndex = orderedVisibleVideoIds.indexOf(videoId);
    if (anchorIndex < 0 || targetIndex < 0) {
      setSelected(videoId, true);
      return;
    }

    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    final next = Set<int>.from(state.selectedIds)
      ..addAll(orderedVisibleVideoIds.sublist(start, end + 1));
    state = state.copyWith(selectedIds: next, anchorVideoId: videoId);
  }

  Future<void> selectLoaded(Iterable<int> videoIds) async {
    final ids = videoIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final next = Set<int>.from(state.selectedIds)..addAll(ids);
    state = state.copyWith(selectedIds: next, anchorVideoId: ids.last);
  }

  void selectRandom(Iterable<int> videoIds, int count, {Random? random}) {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    if (count == 0) {
      state = const VideoSelectionState();
      return;
    }
    final ids = videoIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final requestedCount = count.clamp(0, ids.length).toInt();

    final shuffled = List<int>.from(ids)..shuffle(random);
    final selectedIds = shuffled.take(requestedCount).toSet();
    state = VideoSelectionState(
      selectedIds: selectedIds,
      anchorVideoId: shuffled[requestedCount - 1],
    );
  }

  /// Replaces the current selection with a bounded catalog result.
  void replaceSelection(Iterable<int> videoIds) {
    final ids = videoIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      state = const VideoSelectionState();
      return;
    }
    state = VideoSelectionState(
      selectedIds: ids.toSet(),
      anchorVideoId: ids.last,
    );
  }

  void removeIds(Iterable<int> videoIds) {
    final removeSet = videoIds.toSet();
    if (removeSet.isEmpty) {
      return;
    }
    final next = state.selectedIds
        .where((videoId) => !removeSet.contains(videoId))
        .toSet();
    if (next.isEmpty) {
      state = const VideoSelectionState();
      return;
    }
    state = state.copyWith(
      selectedIds: next,
      clearAnchor:
          state.anchorVideoId != null &&
          removeSet.contains(state.anchorVideoId),
    );
  }

  void retainIds(Iterable<int> videoIds) {
    final retainSet = videoIds.toSet();
    final next = state.selectedIds
        .where((videoId) => retainSet.contains(videoId))
        .toSet();
    if (next.isEmpty) {
      state = const VideoSelectionState();
      return;
    }
    state = state.copyWith(
      selectedIds: next,
      clearAnchor:
          state.anchorVideoId != null &&
          !retainSet.contains(state.anchorVideoId),
    );
  }

  void toggleShowSelectedOnly() {
    state = state.copyWith(showSelectedOnly: !state.showSelectedOnly);
  }

  void setShowSelectedOnly(bool value) {
    if (state.showSelectedOnly == value) return;
    state = state.copyWith(showSelectedOnly: value);
  }

  void clear() {
    state = const VideoSelectionState();
  }
}

final videoSelectionControllerProvider =
    NotifierProvider<VideoSelectionController, VideoSelectionState>(
      VideoSelectionController.new,
    );
