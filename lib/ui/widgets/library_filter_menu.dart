import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../data/database.dart';
import '../../logic/library_name.dart';
import '../../logic/library_groups.dart';
import '../../logic/private_library_controller.dart';
import '../../logic/settings_provider.dart';

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
    final showPrivateLibraries = ref.watch(
      showPrivateLibrariesInFilterProvider,
    );

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
            .where((folder) => showPrivateLibraries && folder.isPrivate)
            .toList(growable: false);
        final hasPrivateFolders = privateFolders.isNotEmpty;
        final publicGroups = <String, List<Folder>>{};
        for (final folder in publicFolders) {
          publicGroups
              .putIfAbsent(libraryGroupName(folder), () => [])
              .add(folder);
        }
        final publicGroupEntries = publicGroups.entries.toList()
          ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
        MacosPulldownMenuItem folderItem(
          Folder folder, {
          bool indented = false,
        }) {
          return MacosPulldownMenuItem(
            title: MacosTooltip(
              message: folder.path,
              child: _LibraryMenuRow(
                indent: indented ? 20 : 0,
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

        MacosPulldownMenuItem groupItem(String name, List<Folder> folders) {
          final ids = folders.map((folder) => folder.id).toSet();
          final isSelected =
              ids.isNotEmpty && ids.every(selectedFolderIds.contains);
          return MacosPulldownMenuItem(
            title: _LibraryMenuRow(
              icon: isSelected
                  ? CupertinoIcons.checkmark
                  : CupertinoIcons.folder_fill,
              label: name,
            ),
            label: name,
            onTap: () => ref
                .read(selectedLibraryFoldersControllerProvider.notifier)
                .toggleGroup(ids),
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
          for (final entry in publicGroupEntries) ...[
            groupItem(entry.key, entry.value),
            for (final folder in entry.value)
              folderItem(folder, indented: true),
          ],
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
                  ? ref
                        .read(privateLibraryAccessControllerProvider.notifier)
                        .lock()
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

class _LibraryMenuRow extends StatelessWidget {
  const _LibraryMenuRow({
    required this.label,
    this.icon,
    this.muted = false,
    this.indent = 0,
  });

  final String label;
  final IconData? icon;
  final bool muted;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: indent),
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
