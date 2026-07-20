import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../data/database.dart';
import '../../logic/maintenance_controller.dart';
import '../../logic/library_controller.dart';
import '../widgets/video_grid.dart';
import '../widgets/status_footer.dart';
import '../widgets/filter_bar.dart';
import '../../logic/stats_provider.dart';
import '../../logic/filter_controller.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_move_controller.dart';
import '../../logic/video_selection_controller.dart';
import 'settings_screen.dart';
import 'tag_management_screen.dart';
import '../widgets/bulk_selection_toolbar.dart';
import '../widgets/library_filter_menu.dart';
import '../widgets/show_offline_media_control.dart';
import '../widgets/video_move_dialog.dart';
import '../library_result_messages.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _searchController;
  late final TextEditingController _tagFilterController;
  bool _isBulkActionRunning = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    _tagFilterController = TextEditingController();
    _tagFilterController.addListener(_onTagFilterChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tagFilterController.removeListener(_onTagFilterChanged);
    _tagFilterController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    ref.read(searchQueryProvider.notifier).set(_searchController.text);
  }

  void _onTagFilterChanged() {
    ref.read(tagFilterQueryProvider.notifier).set(_tagFilterController.text);
  }

  @override
  Widget build(BuildContext context) {
    // Force initialization of library controller
    ref.watch(libraryControllerProvider);

    // Sync search controller with state (e.g. when clicking a folder path)
    ref.listen(searchQueryProvider, (previous, next) {
      if (next != _searchController.text) {
        _searchController.text = next;
      }
    });
    final hasActiveFilters =
        ref.watch(searchQueryProvider).isNotEmpty ||
        ref.watch(combinedSelectedTagsProvider).isNotEmpty;
    final moveSelection = ref.watch(videoSelectionControllerProvider);
    final moveState = ref.watch(videoMoveControllerProvider);
    final isBulkBusy = moveState.isMoving || _isBulkActionRunning;
    final loadedVideoIds =
        ref
            .watch(filteredVideosProvider)
            .asData
            ?.value
            .map((video) => video.id)
            .toList(growable: false) ??
        const <int>[];

    return MacosWindow(
      child: Row(
        children: [
          // Custom Sidebar
          Container(
            width: 220,
            decoration: BoxDecoration(
              color: MacosTheme.of(context).canvasColor,
              border: Border(
                right: BorderSide(
                  color: MacosTheme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // FIXED TOP SECTION
                const SizedBox(height: 12),
                _SidebarNavItem(
                  label: 'All Videos',
                  icon: CupertinoIcons.film,
                  selected:
                      ref.watch(selectedCategoryProvider) ==
                      LibraryCategory.all,
                  onTap: () {
                    ref
                        .read(selectedCategoryProvider.notifier)
                        .set(LibraryCategory.all);
                    ref.read(searchQueryProvider.notifier).set('');
                    ref.read(primarySelectedTagsProvider.notifier).clear();
                  },
                ),
                _SidebarNavItem(
                  label: 'Favorites',
                  icon: CupertinoIcons.heart,
                  selected:
                      ref.watch(selectedCategoryProvider) ==
                      LibraryCategory.favorites,
                  onTap: () {
                    ref
                        .read(selectedCategoryProvider.notifier)
                        .set(LibraryCategory.favorites);
                    ref.read(searchQueryProvider.notifier).set('');
                    ref.read(primarySelectedTagsProvider.notifier).clear();
                  },
                ),
                const Divider(height: 8, indent: 16, endIndent: 16),

                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Row(
                    children: [
                      const Expanded(child: _SidebarHeader(text: 'SORT BY')),
                      MacosIconButton(
                        icon: Icon(
                          ref.watch(selectedSortDirectionProvider) ==
                                  SortDirection.asc
                              ? CupertinoIcons.sort_up
                              : CupertinoIcons.sort_down,
                          size: 16,
                        ),
                        onPressed: () => ref
                            .read(selectedSortDirectionProvider.notifier)
                            .toggle(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _GridSortItem(
                        label: 'Title',
                        icon: CupertinoIcons.textformat_abc,
                        selected:
                            ref.watch(selectedSortProvider) == SortOption.title,
                        onTap: () => ref
                            .read(selectedSortProvider.notifier)
                            .set(SortOption.title),
                      ),
                      _GridSortItem(
                        label: 'Date',
                        icon: CupertinoIcons.calendar,
                        selected:
                            ref.watch(selectedSortProvider) ==
                            SortOption.addedAt,
                        onTap: () => ref
                            .read(selectedSortProvider.notifier)
                            .set(SortOption.addedAt),
                      ),
                      _GridSortItem(
                        label: 'Duration',
                        icon: CupertinoIcons.timer,
                        selected:
                            ref.watch(selectedSortProvider) ==
                            SortOption.duration,
                        onTap: () => ref
                            .read(selectedSortProvider.notifier)
                            .set(SortOption.duration),
                      ),
                      _GridSortItem(
                        label: 'Size',
                        icon: CupertinoIcons.floppy_disk,
                        selected:
                            ref.watch(selectedSortProvider) == SortOption.size,
                        onTap: () => ref
                            .read(selectedSortProvider.notifier)
                            .set(SortOption.size),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 8, indent: 16, endIndent: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SidebarHeader(
                        text:
                            'TAGS (${ref.watch(allTagsProvider).asData?.value.length ?? 0})',
                      ),
                    ),
                    if (hasActiveFilters ||
                        ref.watch(tagFilterQueryProvider).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: MacosIconButton(
                          icon: const Icon(
                            CupertinoIcons.clear_circled,
                            size: 14,
                          ),
                          onPressed: () {
                            ref.read(searchQueryProvider.notifier).set('');
                            ref
                                .read(primarySelectedTagsProvider.notifier)
                                .clear();
                            _tagFilterController.clear();
                          },
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: MacosSearchField(
                    controller: _tagFilterController,
                    placeholder: 'Filter tags...',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 4),

                // TAGS SECTION - Split 80/20
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Consumer(
                      builder: (context, ref, _) {
                        return Column(
                          children: [
                            // TOP SECTION (All Tags) - 80%
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: ref
                                          .watch(allTagsProvider)
                                          .when(
                                            data: (tags) => TagCloud(
                                              tags: tags,
                                              selectedTags: ref
                                                  .watch(
                                                    primarySelectedTagsProvider,
                                                  )
                                                  .toSet(),
                                              onTagSelected: (tag) => ref
                                                  .read(
                                                    primarySelectedTagsProvider
                                                        .notifier,
                                                  )
                                                  .toggle(tag),
                                              enableDelete: true,
                                            ),
                                            loading: () => const Center(
                                              child: ProgressCircle(radius: 10),
                                            ),
                                            error: (_, _) =>
                                                const SizedBox.shrink(),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Divider(height: 16),

                            // BOTTOM SECTION (Related Tags) - 20%
                            Expanded(
                              flex: 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: ref
                                          .watch(relatedTagsProvider)
                                          .when(
                                            data: (tags) {
                                              if (tags.isEmpty) {
                                                return const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 4.0,
                                                  ),
                                                  child: Text(
                                                    'Select a tag above to see related tags.',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return TagCloud(
                                                tags: tags,
                                                selectedTags: ref
                                                    .watch(
                                                      secondarySelectedTagsProvider,
                                                    )
                                                    .toSet(),
                                                onTagSelected: (tag) => ref
                                                    .read(
                                                      secondarySelectedTagsProvider
                                                          .notifier,
                                                    )
                                                    .toggle(tag),
                                                enableDelete: false,
                                              );
                                            },
                                            loading: () => const Center(
                                              child: ProgressCircle(radius: 10),
                                            ),
                                            error: (err, stack) => Text(
                                              'Error: $err',
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                const Divider(height: 8, indent: 16, endIndent: 16),
                const _LibraryStatsBox(),
                const Divider(height: 8, indent: 16, endIndent: 16),
                _SidebarNavItem(
                  label: 'Tag Management',
                  icon: CupertinoIcons.tag,
                  selected: false,
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const TagManagementScreen(),
                      ),
                    );
                  },
                ),
                _SidebarNavItem(
                  label: 'Settings',
                  icon: CupertinoIcons.settings,
                  selected: false,
                  onTap: () {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // Main Content Area
          Expanded(
            child: ContentArea(
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Header
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: MacosTheme.of(context).dividerColor,
                          ),
                        ),
                        color: MacosTheme.of(context).canvasColor,
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 52,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 8),
                                  Text(
                                    'Library',
                                    style: MacosTheme.of(
                                      context,
                                    ).typography.headline,
                                  ),
                                  const Spacer(),
                                  const LibraryFilterMenu(),
                                  const SizedBox(width: 8),
                                  const ShowOfflineMediaControl(),
                                  const SizedBox(width: 8),
                                  MacosTooltip(
                                    message: 'Add Folder',
                                    child: MacosIconButton(
                                      icon: const MacosIcon(CupertinoIcons.add),
                                      onPressed: isBulkBusy
                                          ? null
                                          : _pickFolder,
                                      shape: BoxShape.rectangle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  MacosTooltip(
                                    message: 'Refresh Library',
                                    child: MacosIconButton(
                                      icon: const MacosIcon(
                                        CupertinoIcons.refresh,
                                      ),
                                      onPressed: isBulkBusy
                                          ? null
                                          : () {
                                              print('DEBUG: Refresh pressed');
                                              ref
                                                  .read(
                                                    libraryControllerProvider
                                                        .notifier,
                                                  )
                                                  .syncAll();
                                            },
                                      shape: BoxShape.rectangle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  MacosTooltip(
                                    message: 'Rebuild Index',
                                    child: MacosIconButton(
                                      icon: const MacosIcon(
                                        CupertinoIcons.trash_circle,
                                      ),
                                      onPressed: isBulkBusy
                                          ? null
                                          : () {
                                              showMacosAlertDialog(
                                                context: context,
                                                builder: (context) => MacosAlertDialog(
                                                  appIcon: const MacosIcon(
                                                    CupertinoIcons.film,
                                                  ),
                                                  title: const Text(
                                                    'Rebuild Library?',
                                                  ),
                                                  message: const Text(
                                                    'This will clear all existing tags and metadata, and re-scan everything using the new AI engine. This may take a while.',
                                                  ),
                                                  primaryButton: PushButton(
                                                    controlSize:
                                                        ControlSize.large,
                                                    child: const Text(
                                                      'Rebuild',
                                                    ),
                                                    onPressed: () {
                                                      Navigator.pop(context);
                                                      ref
                                                          .read(
                                                            libraryControllerProvider
                                                                .notifier,
                                                          )
                                                          .rebuildLibrary();
                                                    },
                                                  ),
                                                  secondaryButton: PushButton(
                                                    controlSize:
                                                        ControlSize.large,
                                                    child: const Text('Cancel'),
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                  ),
                                                ),
                                              );
                                            },
                                      shape: BoxShape.rectangle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            height: 44,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                            child: BulkSelectionToolbar(
                              selectedCount: moveSelection.count,
                              isBusy: isBulkBusy,
                              onSelectLoaded: loadedVideoIds.isEmpty
                                  ? null
                                  : () => ref
                                        .read(
                                          videoSelectionControllerProvider
                                              .notifier,
                                        )
                                        .selectLoaded(loadedVideoIds),
                              onMove: () {
                                final selectedVideoIds = _selectedVideoIds();
                                if (selectedVideoIds.isEmpty) return;
                                showVideoMoveDialog(
                                  context: context,
                                  ref: ref,
                                  selectedVideoIds: selectedVideoIds,
                                );
                              },
                              onDelete: _confirmDeleteSelectedVideos,
                              onFavorite: () => _setFavoriteForSelected(true),
                              onUnfavorite: () =>
                                  _setFavoriteForSelected(false),
                              onClearTags: _confirmClearTagsForSelected,
                              onClearSelection: () => ref
                                  .read(
                                    videoSelectionControllerProvider.notifier,
                                  )
                                  .clear(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: MacosSearchField(
                        controller: _searchController,
                        placeholder: 'Search videos...',
                      ),
                    ),
                    // Grid
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification notification) {
                          // Only respond to the main scroll view (depth 0), not nested scrollables like tag lists
                          if (notification.depth != 0) return false;

                          // Only trigger on downward scroll, not upward
                          if (notification is! ScrollUpdateNotification) {
                            return false;
                          }
                          final delta = notification.scrollDelta ?? 0;
                          if (delta <= 0) return false;

                          // Check if near the end of the scroll view
                          if (notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent - 500) {
                            // Only load more if there are more videos to load
                            final currentCount =
                                ref
                                    .read(filteredVideosProvider)
                                    .asData
                                    ?.value
                                    .length ??
                                0;
                            final totalCount =
                                ref
                                    .read(selectedVideoCountProvider)
                                    .asData
                                    ?.value ??
                                0;
                            if (currentCount < totalCount) {
                              ref.read(videoLimitProvider.notifier).loadMore();
                            }
                          }
                          return false;
                        },
                        child: CustomScrollView(
                          controller: scrollController,
                          slivers: const [
                            SliverVideoGrid(),
                            SliverPadding(padding: EdgeInsets.only(bottom: 20)),
                          ],
                        ),
                      ),
                    ),
                    // Footer (pinned)
                    const StatusFooter(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<int> _selectedVideoIds() {
    return ref
        .read(videoSelectionControllerProvider)
        .selectedIds
        .toList(growable: false);
  }

  Future<void> _runBulkAction(Future<void> Function() action) async {
    if (_isBulkActionRunning) {
      return;
    }
    setState(() {
      _isBulkActionRunning = true;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _isBulkActionRunning = false;
        });
      }
    }
  }

  Future<void> _setFavoriteForSelected(bool isFavorite) async {
    final selectedVideoIds = _selectedVideoIds();
    if (selectedVideoIds.isEmpty) {
      return;
    }

    await _runBulkAction(() async {
      final actionCompleted = await ref
          .read(maintenanceControllerProvider.notifier)
          .setFavoriteForVideos(selectedVideoIds, isFavorite);
      if (!actionCompleted) {
        ref
            .read(statusMessageProvider.notifier)
            .set('Authentication cancelled.');
        return;
      }
      ref
          .read(statusMessageProvider.notifier)
          .set(
            isFavorite
                ? 'Marked ${_videoCountText(selectedVideoIds.length)} as favorite.'
                : 'Removed favorite from ${_videoCountText(selectedVideoIds.length)}.',
          );
    });
  }

  void _confirmDeleteSelectedVideos() {
    final selectedVideoIds = _selectedVideoIds();
    if (selectedVideoIds.isEmpty) {
      return;
    }

    showMacosAlertDialog<void>(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.trash),
        title: const Text('Delete Selected Videos?'),
        message: Text(
          'This will permanently delete ${_videoCountText(selectedVideoIds.length)} from disk.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('Delete'),
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await _deleteSelectedVideos(selectedVideoIds);
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  Future<void> _deleteSelectedVideos(List<int> selectedVideoIds) async {
    await _runBulkAction(() async {
      final result = await ref
          .read(maintenanceControllerProvider.notifier)
          .deleteVideos(selectedVideoIds);
      if (result == null) {
        ref
            .read(statusMessageProvider.notifier)
            .set('Authentication cancelled.');
        return;
      }

      ref
          .read(videoSelectionControllerProvider.notifier)
          .removeIds(result.deletedVideoIds);
      ref.read(statusMessageProvider.notifier).set(result.userMessage);
    });
  }

  void _confirmClearTagsForSelected() {
    final selectedVideoIds = _selectedVideoIds();
    if (selectedVideoIds.isEmpty) {
      return;
    }

    showMacosAlertDialog<void>(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.tag),
        title: const Text('Clear Tags for Selected Videos?'),
        message: Text(
          'This will remove all tags from ${_videoCountText(selectedVideoIds.length)}. Media files will not be deleted.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('Clear Tags'),
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await _clearTagsForSelected(selectedVideoIds);
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  Future<void> _clearTagsForSelected(List<int> selectedVideoIds) async {
    await _runBulkAction(() async {
      final actionCompleted = await ref
          .read(maintenanceControllerProvider.notifier)
          .clearTagsForVideos(selectedVideoIds);
      if (!actionCompleted) {
        ref
            .read(statusMessageProvider.notifier)
            .set('Authentication cancelled.');
        return;
      }
      ref
          .read(statusMessageProvider.notifier)
          .set(
            'Cleared tags from ${_videoCountText(selectedVideoIds.length)}.',
          );
    });
  }

  String _videoCountText(int count) => count == 1 ? '1 video' : '$count videos';

  Future<void> _pickFolder() async {
    print('DEBUG: _pickFolder called');
    final String? selectedDirectory = await FilePicker.platform
        .getDirectoryPath();
    print('DEBUG: FilePicker returned: $selectedDirectory');
    if (selectedDirectory != null) {
      final result = await ref
          .read(libraryControllerProvider.notifier)
          .addFolder(selectedDirectory);
      if (!mounted) {
        return;
      }
      ref
          .read(statusMessageProvider.notifier)
          .set(libraryAddFlowResultMessage(result));
    }
  }
}

class _SidebarHeader extends StatelessWidget {
  final String text;
  const _SidebarHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          textAlign: TextAlign.left,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: MacosTheme.of(context).typography.caption1.copyWith(
            color: MacosTheme.of(
              context,
            ).typography.caption1.color?.withOpacity(0.5),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? theme.primaryColor.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? theme.primaryColor
                  : theme.typography.body.color?.withOpacity(0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.typography.body.copyWith(
                  color: selected
                      ? theme.primaryColor
                      : theme.typography.body.color?.withOpacity(0.8),
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridSortItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GridSortItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Half width minus spacing
        width: 95,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.primaryColor.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? theme.primaryColor
                  : theme.typography.body.color?.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.typography.body.copyWith(
                  fontSize: 10, // Slightly smaller font
                  color: selected
                      ? theme.primaryColor
                      : theme.typography.body.color?.withOpacity(0.8),
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryStatsBox extends ConsumerWidget {
  const _LibraryStatsBox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsSync = ref.watch(libraryStatsProvider);

    return statsSync.when(
      data: (stats) => Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: MacosTheme.of(context).canvasColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MacosTheme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatRow(label: 'Videos', value: '${stats.totalCount}'),
            const SizedBox(height: 1),
            _StatRow(label: 'Duration', value: stats.formattedDuration),
            const SizedBox(height: 1),
            _StatRow(label: 'Size', value: stats.formattedSize),
          ],
        ),
      ),
      loading: () => const Center(child: ProgressCircle(value: null)),
      error: (_, _) => const SizedBox(),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: MacosTheme.of(context).typography.caption1),
        Text(
          value,
          style: MacosTheme.of(
            context,
          ).typography.caption1.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
