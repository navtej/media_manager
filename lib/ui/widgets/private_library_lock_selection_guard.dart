import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../logic/private_library_controller.dart';
import '../../logic/video_selection_controller.dart';

class PrivateLibraryLockSelectionGuard extends ConsumerStatefulWidget {
  const PrivateLibraryLockSelectionGuard({this.child, super.key});

  final Widget? child;

  @override
  ConsumerState<PrivateLibraryLockSelectionGuard> createState() =>
      _PrivateLibraryLockSelectionGuardState();
}

class _PrivateLibraryLockSelectionGuardState
    extends ConsumerState<PrivateLibraryLockSelectionGuard> {
  @override
  Widget build(BuildContext context) {
    ref.watch(libraryFoldersProvider);
    ref.listen(privateLibraryAccessControllerProvider, (previous, next) {
      if (previous?.isUnlocked == true && !next.isUnlocked) {
        unawaited(_removePrivateVideoSelections());
      }
    });

    return widget.child ?? const SizedBox.shrink();
  }

  Future<void> _removePrivateVideoSelections() async {
    final selectedIds = ref
        .read(videoSelectionControllerProvider)
        .selectedIds
        .toList(growable: false);
    if (selectedIds.isEmpty) {
      return;
    }

    final folders = await ref.read(foldersDaoProvider).getAllFolders();
    final publicFolderIds = folders
        .where((folder) => !folder.isPrivate)
        .map((folder) => folder.id)
        .toSet();
    final selectedVideos = await ref
        .read(videosDaoProvider)
        .getVideosByIds(selectedIds);
    final privateVideoIds = selectedVideos
        .where((video) => !publicFolderIds.contains(video.folderId))
        .map((video) => video.id);

    if (mounted) {
      ref
          .read(videoSelectionControllerProvider.notifier)
          .removeIds(privateVideoIds);
    }
  }
}
