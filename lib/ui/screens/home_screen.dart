import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../logic/maintenance_controller.dart';
import '../../logic/library_controller.dart';
import '../../logic/settings_provider.dart';
import '../widgets/video_grid.dart';
import '../widgets/status_footer.dart';
import '../widgets/filter_bar.dart';
import '../../logic/catalog_controller.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_move_controller.dart';
import '../../logic/video_selection_controller.dart';
import 'settings_screen.dart';
import 'tag_management_screen.dart';
import '../widgets/bulk_selection_toolbar.dart';
import '../widgets/catalog_presentation.dart';
import '../widgets/library_filter_menu.dart';
import '../widgets/show_offline_media_control.dart';
import '../widgets/video_move_dialog.dart';
import '../library_result_messages.dart';
import '../movie_manager_visual_system.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _searchController;
  late final TextEditingController _tagFilterController;
  late final ScrollController _catalogScrollController;
  bool _isBulkActionRunning = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    _tagFilterController = TextEditingController();
    _tagFilterController.addListener(_onTagFilterChanged);
    _catalogScrollController = ScrollController();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tagFilterController.removeListener(_onTagFilterChanged);
    _tagFilterController.dispose();
    _catalogScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    ref
        .read(catalogControllerProvider.notifier)
        .setSearchQuery(_searchController.text);
  }

  void _onTagFilterChanged() {
    ref
        .read(catalogControllerProvider.notifier)
        .setTagFilterQuery(_tagFilterController.text);
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
    final catalogPresentation = ref.watch(catalogViewPresentationProvider);

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
                  onTap: () => ref
                      .read(catalogControllerProvider.notifier)
                      .showCategory(LibraryCategory.all),
                ),
                _SidebarNavItem(
                  label: 'Favorites',
                  icon: CupertinoIcons.heart,
                  selected:
                      ref.watch(selectedCategoryProvider) ==
                      LibraryCategory.favorites,
                  onTap: () => ref
                      .read(catalogControllerProvider.notifier)
                      .showCategory(LibraryCategory.favorites),
                ),
                const Divider(height: 8, indent: 16, endIndent: 16),

                Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Row(
                    children: [
                      const Expanded(child: _SidebarHeader(text: 'SORT BY')),
                      MovieManagerIconButton(
                        label: 'Reverse sort direction',
                        icon:
                            ref.watch(selectedSortDirectionProvider) ==
                                SortDirection.asc
                            ? CupertinoIcons.sort_up
                            : CupertinoIcons.sort_down,
                        onPressed: () => ref
                            .read(catalogControllerProvider.notifier)
                            .toggleSortDirection(),
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
                            .read(catalogControllerProvider.notifier)
                            .setSort(SortOption.title),
                      ),
                      _GridSortItem(
                        label: 'Date',
                        icon: CupertinoIcons.calendar,
                        selected:
                            ref.watch(selectedSortProvider) ==
                            SortOption.addedAt,
                        onTap: () => ref
                            .read(catalogControllerProvider.notifier)
                            .setSort(SortOption.addedAt),
                      ),
                      _GridSortItem(
                        label: 'Duration',
                        icon: CupertinoIcons.timer,
                        selected:
                            ref.watch(selectedSortProvider) ==
                            SortOption.duration,
                        onTap: () => ref
                            .read(catalogControllerProvider.notifier)
                            .setSort(SortOption.duration),
                      ),
                      _GridSortItem(
                        label: 'Size',
                        icon: CupertinoIcons.floppy_disk,
                        selected:
                            ref.watch(selectedSortProvider) == SortOption.size,
                        onTap: () => ref
                            .read(catalogControllerProvider.notifier)
                            .setSort(SortOption.size),
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
                        child: MovieManagerIconButton(
                          label: 'Clear tag filters',
                          icon: CupertinoIcons.clear_circled,
                          onPressed: () {
                            ref
                                .read(catalogControllerProvider.notifier)
                                .clearSearchAndTags();
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
                  child: MovieManagerLabeledField(
                    label: 'Filter tags',
                    controller: _tagFilterController,
                    builder: (focusNode) => MacosSearchField(
                      controller: _tagFilterController,
                      focusNode: focusNode,
                      placeholder: 'Filter tags...',
                      style: const TextStyle(fontSize: 11),
                    ),
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
                                                    catalogControllerProvider
                                                        .notifier,
                                                  )
                                                  .togglePrimaryTag(tag),
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
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 4.0,
                                                      ),
                                                  child: Text(
                                                    'Select a tag above to see related tags.',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color:
                                                          MovieManagerVisuals.secondaryLabelColor(
                                                            context,
                                                          ),
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
                                                      catalogControllerProvider
                                                          .notifier,
                                                    )
                                                    .toggleRelatedTag(tag),
                                                enableDelete: false,
                                              );
                                            },
                                            loading: () => const Center(
                                              child: ProgressCircle(radius: 10),
                                            ),
                                            error: (err, stack) => Text(
                                              'Error: $err',
                                              style: TextStyle(
                                                color:
                                                    MovieManagerVisuals.errorColor(
                                                      context,
                                                    ),
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
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, constraints) => Column(
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
                              height: constraints.maxWidth < 760 ? 92 : 52,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    if (constraints.maxWidth >= 760) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        'Library',
                                        style: MacosTheme.of(
                                          context,
                                        ).typography.headline,
                                      ),
                                      const SizedBox(width: 16),
                                    ],
                                    Expanded(
                                      child: Wrap(
                                        alignment: WrapAlignment.end,
                                        runAlignment: WrapAlignment.center,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          const LibraryFilterMenu(),
                                          const ShowOfflineMediaControl(),
                                          CatalogPresentationControl(
                                            presentation: catalogPresentation,
                                            onChanged: (next) =>
                                                _changeCatalogPresentation(
                                                  next: next,
                                                  current: catalogPresentation,
                                                  scrollController:
                                                      _catalogScrollController,
                                                  viewportWidth:
                                                      constraints.maxWidth,
                                                ),
                                          ),
                                          MovieManagerIconButton(
                                            label: 'Add Folder',
                                            icon: CupertinoIcons.add,
                                            onPressed: isBulkBusy
                                                ? null
                                                : _pickFolder,
                                          ),
                                          MovieManagerIconButton(
                                            label: 'Refresh Library',
                                            icon: CupertinoIcons.refresh,
                                            onPressed: isBulkBusy
                                                ? null
                                                : () {
                                                    ref
                                                        .read(
                                                          libraryControllerProvider
                                                              .notifier,
                                                        )
                                                        .syncAll();
                                                  },
                                          ),
                                          MovieManagerIconButton(
                                            label: 'Rebuild Index',
                                            icon: CupertinoIcons.trash_circle,
                                            color:
                                                MovieManagerVisuals.errorColor(
                                                  context,
                                                ),
                                            onPressed: isBulkBusy
                                                ? null
                                                : () => _confirmRebuildLibrary(
                                                    context,
                                                  ),
                                          ),
                                        ],
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
                        child: MovieManagerLabeledField(
                          label: 'Search videos',
                          controller: _searchController,
                          builder: (focusNode) => MacosSearchField(
                            controller: _searchController,
                            focusNode: focusNode,
                            placeholder: 'Search videos...',
                          ),
                        ),
                      ),
                      // Grid
                      Expanded(
                        child: CatalogScrollView(
                          scrollController: _catalogScrollController,
                        ),
                      ),
                      // Footer (pinned)
                      const StatusFooter(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCatalogPresentation({
    required CatalogPresentation next,
    required CatalogPresentation current,
    required ScrollController scrollController,
    required double viewportWidth,
  }) async {
    if (next == current) return;
    final currentVideoIds =
        ref
            .read(filteredVideosProvider)
            .asData
            ?.value
            .map((video) => video.id)
            .toList(growable: false) ??
        const <int>[];
    final anchor = scrollController.hasClients && currentVideoIds.isNotEmpty
        ? CatalogScrollAnchor.capture(
            presentation: current,
            orderedVideoIds: currentVideoIds,
            scrollOffset: scrollController.offset,
            viewportWidth: viewportWidth,
          )
        : null;

    await ref.read(settingsProvider.notifier).updateCatalogPresentation(next);
    if (!mounted || anchor == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !scrollController.hasClients) return;

    final nextVideoIds =
        ref
            .read(filteredVideosProvider)
            .asData
            ?.value
            .map((video) => video.id)
            .toList(growable: false) ??
        const <int>[];
    final position = scrollController.position;
    final target = anchor
        .offsetFor(
          presentation: next,
          orderedVideoIds: nextVideoIds,
          viewportWidth: viewportWidth,
        )
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    scrollController.jumpTo(target);
  }

  void _confirmRebuildLibrary(BuildContext context) {
    showMacosAlertDialog<void>(
      context: context,
      builder: (dialogContext) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.film),
        title: const Text('Rebuild Library?'),
        message: const Text(
          'This will clear all existing tags and metadata, and re-scan everything using the new AI engine. This may take a while.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () {
            Navigator.pop(dialogContext);
            ref.read(libraryControllerProvider.notifier).rebuildLibrary();
          },
          child: const Text('Rebuild'),
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
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

class _SidebarNavItem extends StatefulWidget {
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
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: MovieManagerControlMetrics.minimumTarget,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: widget.selected
                  ? theme.primaryColor.withOpacity(0.1)
                  : Colors.transparent,
              border: _focused
                  ? Border.all(color: theme.primaryColor, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(MovieManagerRadii.control),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: MovieManagerIconSizes.action,
                  color: widget.selected
                      ? theme.primaryColor
                      : theme.typography.body.color?.withOpacity(0.7),
                ),
                const SizedBox(width: MovieManagerSpacing.medium),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.typography.body.copyWith(
                      color: widget.selected
                          ? theme.primaryColor
                          : theme.typography.body.color?.withOpacity(0.8),
                      fontWeight: widget.selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridSortItem extends StatefulWidget {
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
  State<_GridSortItem> createState() => _GridSortItemState();
}

class _GridSortItemState extends State<_GridSortItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: 'Sort by ${widget.label}',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 95,
            constraints: const BoxConstraints(
              minHeight: MovieManagerControlMetrics.minimumTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: widget.selected
                  ? theme.primaryColor.withOpacity(0.1)
                  : Colors.transparent,
              border: _focused
                  ? Border.all(color: theme.primaryColor, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(MovieManagerRadii.control),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: MovieManagerIconSizes.inline,
                  color: widget.selected
                      ? theme.primaryColor
                      : theme.typography.body.color?.withOpacity(0.7),
                ),
                const SizedBox(width: MovieManagerSpacing.small),
                Expanded(
                  child: Text(
                    widget.label,
                    style: theme.typography.body.copyWith(
                      fontSize: 10,
                      color: widget.selected
                          ? theme.primaryColor
                          : theme.typography.body.color?.withOpacity(0.8),
                      fontWeight: widget.selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
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
