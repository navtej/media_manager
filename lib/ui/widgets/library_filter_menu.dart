import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../data/database.dart';
import '../../logic/library_name.dart';
import '../../logic/private_library_controller.dart';

class LibraryFilterMenu extends ConsumerWidget {
  const LibraryFilterMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(libraryFoldersProvider);
    final selectedFolderIds = ref.watch(
      selectedLibraryFoldersControllerProvider,
    );
    final effectiveFolderIds = ref.watch(effectiveLibraryFolderIdsProvider);
    final privateAccess = ref.watch(privateLibraryAccessControllerProvider);

    final title = selectedFolderIds.isEmpty
        ? 'Libraries: All'
        : 'Libraries: ${effectiveFolderIds.length}';

    return foldersAsync.when(
      loading: () => const MacosPulldownButton(title: 'Libraries', items: null),
      error: (_, _) =>
          const MacosPulldownButton(title: 'Libraries', items: null),
      data: (folders) {
        final sortedFolders = List<Folder>.from(folders)
          ..sort(
            (a, b) => libraryDisplayName(
              a,
            ).toLowerCase().compareTo(libraryDisplayName(b).toLowerCase()),
          );
        final publicFolders = sortedFolders
            .where((folder) => !folder.isPrivate)
            .toList(growable: false);
        final privateFolders = sortedFolders
            .where((folder) => folder.isPrivate)
            .toList(growable: false);
        final hasPrivateFolders = privateFolders.isNotEmpty;
        MacosPulldownMenuItem folderItem(Folder folder) {
          return MacosPulldownMenuItem(
            title: MacosTooltip(
              message: folder.path,
              child: _LibraryMenuRow(
                icon: selectedFolderIds.contains(folder.id)
                    ? CupertinoIcons.checkmark
                    : folder.isPrivate
                    ? CupertinoIcons.lock
                    : CupertinoIcons.folder,
                label: libraryDisplayName(folder),
                muted: folder.isPrivate && !privateAccess.isUnlocked,
              ),
            ),
            label: libraryDisplayName(folder),
            onTap: () => _toggleFolder(ref, folder, privateAccess),
          );
        }

        final items = <MacosPulldownMenuEntry>[
          MacosPulldownMenuItem(
            title: _LibraryMenuRow(
              icon: selectedFolderIds.isEmpty ? CupertinoIcons.checkmark : null,
              label: 'All visible libraries',
            ),
            label: 'All visible libraries',
            onTap: () => ref
                .read(selectedLibraryFoldersControllerProvider.notifier)
                .selectAllVisible(),
          ),
          const MacosPulldownMenuDivider(),
          for (final folder in publicFolders) folderItem(folder),
          if (hasPrivateFolders) const MacosPulldownMenuDivider(),
          if (hasPrivateFolders)
            MacosPulldownMenuItem(
              title: _LibraryMenuRow(
                icon: privateAccess.isUnlocked
                    ? CupertinoIcons.lock
                    : CupertinoIcons.lock_open,
                label: privateAccess.isUnlocked
                    ? 'Lock Private Libraries'
                    : privateAccess.isAuthenticating
                    ? 'Unlocking Private Libraries...'
                    : 'Unlock Private Libraries',
              ),
              label: privateAccess.isUnlocked
                  ? 'Lock Private Libraries'
                  : 'Unlock Private Libraries',
              enabled: !privateAccess.isAuthenticating,
              onTap: () => privateAccess.isUnlocked
                  ? _lockPrivateLibraries(ref)
                  : ref
                        .read(privateLibraryAccessControllerProvider.notifier)
                        .unlock(),
            ),
          for (final folder in privateFolders) folderItem(folder),
        ];

        return MacosPulldownButton(title: title, items: items);
      },
    );
  }
}

Future<void> _toggleFolder(
  WidgetRef ref,
  Folder folder,
  PrivateLibraryAccessState privateAccess,
) async {
  if (folder.isPrivate && !privateAccess.isUnlocked) {
    final unlocked = await ref
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();
    if (!unlocked) {
      return;
    }
  }

  ref.read(selectedLibraryFoldersControllerProvider.notifier).toggle(folder.id);
}

void _lockPrivateLibraries(WidgetRef ref) {
  ref.read(privateLibraryAccessControllerProvider.notifier).lock();
}

class _LibraryMenuRow extends StatelessWidget {
  const _LibraryMenuRow({required this.label, this.icon, this.muted = false});

  final String label;
  final IconData? icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          child: icon == null
              ? null
              : Icon(
                  icon,
                  size: 14,
                  color: muted
                      ? theme.typography.body.color?.withValues(alpha: 0.55)
                      : theme.typography.body.color,
                ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              color: muted
                  ? theme.typography.body.color?.withValues(alpha: 0.65)
                  : theme.typography.body.color,
            ),
          ),
        ),
      ],
    );
  }
}
