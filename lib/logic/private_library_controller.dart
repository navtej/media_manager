import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../services/private_library_auth_service.dart';

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
  @override
  PrivateLibraryAccessState build() => const PrivateLibraryAccessState();

  Future<bool> unlock() async {
    if (state.isUnlocked) {
      return true;
    }
    state = state.copyWith(isAuthenticating: true, clearError: true);
    final authenticated = await ref
        .read(privateLibraryAuthServiceProvider)
        .authenticate();
    if (authenticated) {
      state = const PrivateLibraryAccessState(isUnlocked: true);
      return true;
    }

    state = const PrivateLibraryAccessState(
      errorMessage: 'Authentication cancelled.',
    );
    return false;
  }

  void lock() {
    state = const PrivateLibraryAccessState();
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

final effectiveLibraryFolderIdsProvider = Provider<List<int>>((ref) {
  final folders = ref.watch(libraryFoldersProvider).value;
  if (folders == null) {
    return const <int>[];
  }

  final selectedFolderIds = ref.watch(selectedLibraryFoldersControllerProvider);
  final privateAccess = ref.watch(privateLibraryAccessControllerProvider);
  final publicFolderIds = folders
      .where((folder) => !folder.isPrivate)
      .map((folder) => folder.id)
      .toList(growable: false);
  final accessibleFolderIds = folders
      .where((folder) => !folder.isPrivate || privateAccess.isUnlocked)
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
