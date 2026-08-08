import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../services/private_library_auth_service.dart';
import 'settings_provider.dart';
import 'video_selection_controller.dart';

typedef PrivateLibraryAutoLockClock = DateTime Function();

final privateLibraryAutoLockClockProvider =
    Provider<PrivateLibraryAutoLockClock>((ref) => DateTime.now);

class PrivateLibraryAccessState {
  const PrivateLibraryAccessState({
    this.isUnlocked = false,
    this.isAuthenticating = false,
    this.errorMessage,
  });

  final bool isUnlocked;
  final bool isAuthenticating;
  final String? errorMessage;

  PrivateLibraryAccessState copyWith({
    bool? isUnlocked,
    bool? isAuthenticating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PrivateLibraryAccessState(
      isUnlocked: isUnlocked ?? this.isUnlocked,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class PrivateLibraryAccessController
    extends Notifier<PrivateLibraryAccessState> {
  Timer? _autoLockTimer;
  DateTime? _autoLockDeadline;
  int _activePrivateActionCount = 0;
  bool _lockRequested = false;
  bool _authenticationInvalidated = false;
  Completer<void>? _deferredLockCompleter;

  @override
  PrivateLibraryAccessState build() {
    ref.onDispose(_dispose);
    ref.listen(privateLibraryAccessConfigurationProvider, (previous, next) {
      final previousConfiguration = previous?.asData?.value;
      final nextConfiguration = next.asData?.value;
      if (previousConfiguration?.showPrivateLibrariesInFilter == true &&
          nextConfiguration?.showPrivateLibrariesInFilter == false) {
        _authenticationInvalidated = state.isAuthenticating;
        unawaited(lock());
        return;
      }
      final previousMinutes = previousConfiguration?.autoLockMinutes;
      final nextMinutes = nextConfiguration?.autoLockMinutes;
      if (state.isUnlocked && previousMinutes != nextMinutes) {
        _startAutoLockCountdown(
          nextConfiguration?.autoLockDuration ??
              PrivateLibraryAccessConfiguration.defaults.autoLockDuration,
        );
      }
    });
    return const PrivateLibraryAccessState();
  }

  Future<bool> unlock() async {
    if (state.isUnlocked) {
      return true;
    }
    return _authenticateAndUnlock(startCountdown: true);
  }

  Future<T?> runVideoAction<T>({
    required Iterable<int> videoIds,
    Iterable<int> libraryIds = const <int>[],
    required Future<T> Function() action,
  }) async {
    if (!await _containsPrivateTarget(videoIds, libraryIds)) {
      return action();
    }

    final needsTemporaryAccess = !state.isUnlocked;
    if (needsTemporaryAccess) {
      final authenticated = await _authenticateAndUnlock(startCountdown: false);
      if (!authenticated) {
        await _retainPublicSelections();
        return null;
      }
    }

    _activePrivateActionCount += 1;
    _cancelAutoLockTimer();
    try {
      return await action();
    } finally {
      _activePrivateActionCount -= 1;
      if (needsTemporaryAccess) {
        _lockRequested = true;
      }
      if (_activePrivateActionCount == 0) {
        if (_lockRequested) {
          await _finishRequestedLock();
        } else {
          await _resumeAutoLockCountdown();
        }
      }
    }
  }

  Future<bool> _authenticateAndUnlock({required bool startCountdown}) async {
    _authenticationInvalidated = false;
    state = state.copyWith(isAuthenticating: true, clearError: true);
    final authenticated = await ref
        .read(privateLibraryAuthServiceProvider)
        .authenticate();
    if (authenticated) {
      await ref.read(settingsProvider.future);
      if (!ref.mounted) {
        return false;
      }
      if (_authenticationInvalidated) {
        state = const PrivateLibraryAccessState();
        await _retainPublicSelections();
        return false;
      }
      state = const PrivateLibraryAccessState(isUnlocked: true);
      if (startCountdown) {
        _startAutoLockCountdown(
          ref.read(privateLibraryAutoLockDurationProvider),
        );
      }
      return true;
    }

    state = const PrivateLibraryAccessState(
      errorMessage: 'Authentication cancelled.',
    );
    return false;
  }

  Future<void> lock() {
    _lockRequested = true;
    _cancelAutoLock();
    if (_activePrivateActionCount > 0) {
      final completer = _deferredLockCompleter ??= Completer<void>();
      return completer.future;
    }
    return _finishRequestedLock();
  }

  Future<void> _finishRequestedLock() async {
    final completer = _deferredLockCompleter;
    _deferredLockCompleter = null;
    try {
      await _performLock();
      completer?.complete();
    } catch (error, stackTrace) {
      completer?.completeError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> _performLock() async {
    _lockRequested = false;
    _cancelAutoLock();
    state = const PrivateLibraryAccessState();
    await _retainPublicSelections();
  }

  Future<void> _retainPublicSelections() async {
    final selectedFolderIds = ref.read(
      selectedLibraryFoldersControllerProvider,
    );
    final selectedVideoIds = ref
        .read(videoSelectionControllerProvider)
        .selectedIds
        .toList(growable: false);
    if (selectedFolderIds.isEmpty && selectedVideoIds.isEmpty) {
      return;
    }

    final folders = await ref.read(foldersDaoProvider).getAllFolders();
    if (!ref.mounted) {
      return;
    }
    final publicFolderIds = _publicLibraryFolderIds(folders);
    ref
        .read(selectedLibraryFoldersControllerProvider.notifier)
        .retainVisible(publicFolderIds);

    if (selectedVideoIds.isEmpty) {
      return;
    }
    final selectedVideos = await ref
        .read(videosDaoProvider)
        .getVideosByIds(selectedVideoIds);
    if (!ref.mounted) {
      return;
    }
    final videosById = {for (final video in selectedVideos) video.id: video};
    final inaccessibleVideoIds = selectedVideoIds.where((videoId) {
      final video = videosById[videoId];
      return video == null || !publicFolderIds.contains(video.folderId);
    });
    ref
        .read(videoSelectionControllerProvider.notifier)
        .removeIds(inaccessibleVideoIds);
  }

  Future<void> enforceAutoLockDeadline() async {
    final deadline = _autoLockDeadline;
    if (!state.isUnlocked || deadline == null) {
      return;
    }

    final remaining = deadline.difference(
      ref.read(privateLibraryAutoLockClockProvider)(),
    );
    if (remaining <= Duration.zero) {
      await lock();
      return;
    }

    _armAutoLockTimer(remaining);
  }

  void _startAutoLockCountdown(Duration duration) {
    _autoLockDeadline = ref
        .read(privateLibraryAutoLockClockProvider)()
        .add(duration);
    _armAutoLockTimer(duration);
  }

  void _armAutoLockTimer(Duration duration) {
    _cancelAutoLockTimer();
    if (_activePrivateActionCount > 0) {
      return;
    }
    _autoLockTimer = Timer(duration, () => unawaited(lock()));
  }

  Future<void> _resumeAutoLockCountdown() async {
    final deadline = _autoLockDeadline;
    if (!state.isUnlocked || deadline == null) {
      return;
    }
    final remaining = deadline.difference(
      ref.read(privateLibraryAutoLockClockProvider)(),
    );
    if (remaining <= Duration.zero) {
      await lock();
      return;
    }
    _armAutoLockTimer(remaining);
  }

  Future<bool> _containsPrivateTarget(
    Iterable<int> videoIds,
    Iterable<int> libraryIds,
  ) async {
    final videoIdSet = videoIds.toSet();
    final libraryIdSet = libraryIds.toSet();
    if (videoIdSet.isEmpty && libraryIdSet.isEmpty) {
      return false;
    }
    final videos = videoIdSet.isEmpty
        ? const <Video>[]
        : await ref.read(videosDaoProvider).getVideosByIds(videoIdSet.toList());
    final folders = await ref.read(foldersDaoProvider).getAllFolders();
    final foldersById = {for (final folder in folders) folder.id: folder};
    if (libraryIdSet.any((id) => foldersById[id]?.isPrivate == true)) {
      return true;
    }
    final publicFolderIds = _publicLibraryFolderIds(folders);
    return videos.any((video) => !publicFolderIds.contains(video.folderId));
  }

  void _cancelAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }

  void _cancelAutoLock() {
    _cancelAutoLockTimer();
    _autoLockDeadline = null;
  }

  void _dispose() {
    _cancelAutoLock();
    final completer = _deferredLockCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

final privateLibraryAccessControllerProvider =
    NotifierProvider<PrivateLibraryAccessController, PrivateLibraryAccessState>(
      PrivateLibraryAccessController.new,
    );

class SelectedLibraryFoldersController extends Notifier<Set<int>> {
  @override
  Set<int> build() => const <int>{};

  void toggle(int folderId) {
    final next = Set<int>.from(state);
    if (!next.add(folderId)) {
      next.remove(folderId);
    }
    state = next;
  }

  void toggleGroup(Set<int> folderIds) {
    final next = Set<int>.from(state);
    if (folderIds.every(next.contains)) {
      next.removeAll(folderIds);
    } else {
      next.addAll(folderIds);
    }
    state = next;
  }

  void selectAllVisible() {
    state = const <int>{};
  }

  void clear() {
    state = const <int>{};
  }

  void retainVisible(Set<int> visibleFolderIds) {
    final next = state
        .where((folderId) => visibleFolderIds.contains(folderId))
        .toSet();
    if (next.length != state.length) {
      state = next;
    }
  }
}

final selectedLibraryFoldersControllerProvider =
    NotifierProvider<SelectedLibraryFoldersController, Set<int>>(
      SelectedLibraryFoldersController.new,
    );

final libraryFoldersProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(foldersDaoProvider).watchAllFolders();
});

final publicLibraryFolderIdsProvider = Provider<Set<int>>((ref) {
  final folders = ref.watch(libraryFoldersProvider).value;
  if (folders == null) {
    return const <int>{};
  }
  return _publicLibraryFolderIds(folders);
});

final accessibleLibraryFoldersProvider = Provider<List<Folder>>((ref) {
  final folders = ref.watch(libraryFoldersProvider).value;
  if (folders == null) {
    return const <Folder>[];
  }
  if (ref.watch(privateLibraryAccessControllerProvider).isUnlocked) {
    return folders;
  }
  return folders.where((folder) => !folder.isPrivate).toList(growable: false);
});

final effectiveLibraryFolderIdsProvider = Provider<List<int>>((ref) {
  final selectedFolderIds = ref.watch(selectedLibraryFoldersControllerProvider);
  final publicFolderIds = ref
      .watch(publicLibraryFolderIdsProvider)
      .toList(growable: false);
  final accessibleFolderIds = ref
      .watch(accessibleLibraryFoldersProvider)
      .map((folder) => folder.id)
      .toList(growable: false);

  if (selectedFolderIds.isEmpty) {
    return publicFolderIds;
  }

  return accessibleFolderIds
      .where((folderId) => selectedFolderIds.contains(folderId))
      .toList(growable: false);
});

final visibleLibraryFoldersProvider = Provider<List<Folder>>((ref) {
  final folderIds = ref.watch(effectiveLibraryFolderIdsProvider).toSet();
  final folders = ref.watch(libraryFoldersProvider).value;
  if (folders == null || folderIds.isEmpty) {
    return const <Folder>[];
  }
  return folders
      .where((folder) => folderIds.contains(folder.id))
      .toList(growable: false);
});

Set<int> _publicLibraryFolderIds(Iterable<Folder> folders) {
  return folders
      .where((folder) => !folder.isPrivate)
      .map((folder) => folder.id)
      .toSet();
}
