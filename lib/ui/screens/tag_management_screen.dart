import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Material, Divider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../logic/catalog_controller.dart';
import '../../logic/private_library_controller.dart';
import '../movie_manager_visual_system.dart';
import '../widgets/macos_preference_checkbox.dart';

enum TagSortOption { name, count }

enum TagSortDirection { asc, desc }

class TagManagementScreen extends ConsumerStatefulWidget {
  const TagManagementScreen({super.key});

  @override
  ConsumerState<TagManagementScreen> createState() =>
      _TagManagementScreenState();
}

class _TagManagementScreenState extends ConsumerState<TagManagementScreen> {
  final Set<String> _selectedTags = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  TagStatistics? _stats;

  // Sort State
  TagSortOption _sortOption = TagSortOption.name;
  TagSortDirection _sortDirection = TagSortDirection.asc;

  // Filter State
  bool _showUserTags = true;
  bool _showAutoTags = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    final folderIds = ref.read(effectiveLibraryFolderIdsProvider);
    final stats = await ref
        .read(tagsDaoProvider)
        .getTagStatistics(folderIds: folderIds);
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  List<TagInfo> _processTags(List<TagInfo> tags) {
    // 1. Filter by Search
    var filtered = tags;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where((t) => t.tagText.contains(_searchQuery))
          .toList();
    }

    // 2. Filter by Type (User/Auto)
    // Assuming sourceType can be checked. If strict 'user'/'auto' strings are used:
    filtered = filtered.where((t) {
      final isAuto = t.sourceType.toLowerCase() == 'auto';
      if (isAuto && !_showAutoTags) return false;
      if (!isAuto && !_showUserTags) return false;
      return true;
    }).toList();

    // 3. Sort
    filtered.sort((a, b) {
      int cmp;
      switch (_sortOption) {
        case TagSortOption.name:
          cmp = a.tagText.compareTo(b.tagText);
          break;
        case TagSortOption.count:
          cmp = a.videoCount.compareTo(b.videoCount);
          break;
      }
      return _sortDirection == TagSortDirection.asc ? cmp : -cmp;
    });

    return filtered;
  }

  void _setSort(TagSortOption option) {
    setState(() {
      if (_sortOption == option) {
        // Toggle direction if clicking same option
        _sortDirection = _sortDirection == TagSortDirection.asc
            ? TagSortDirection.desc
            : TagSortDirection.asc;
      } else {
        // Switch option, default to Ascending (or Descending for count if preferred, but Asc is standard reset)
        _sortOption = option;
        _sortDirection = option == TagSortOption.count
            ? TagSortDirection.desc
            : TagSortDirection.asc;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    ref.listen(effectiveLibraryFolderIdsProvider, (previous, next) {
      if (previous != next) {
        _loadStats();
      }
    });

    return MacosScaffold(
      backgroundColor: theme.canvasColor,
      toolBar: ToolBar(
        decoration: BoxDecoration(color: theme.canvasColor),
        title: const Text('Tag Management'),
        leading: MovieManagerIconButton(
          label: 'Back',
          icon: CupertinoIcons.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Container(
              color: theme.canvasColor,
              child: Column(
                children: [
                  // Control and Stats Bar
                  _buildControlAndStatsBar(theme),

                  const Divider(height: 1),

                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: MovieManagerLabeledField(
                      label: 'Search tags',
                      controller: _searchController,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value.toLowerCase()),
                      builder: (focusNode) => MacosTextField(
                        controller: _searchController,
                        focusNode: focusNode,
                        placeholder: 'Search tags...',
                        prefix: const MacosIcon(CupertinoIcons.search),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value.toLowerCase()),
                      ),
                    ),
                  ),

                  // Tag Cloud
                  Expanded(child: _buildTagCloud(theme)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildControlAndStatsBar(MacosThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: theme.canvasColor),
      child: Row(
        children: [
          // --- LEFT: CONTROLS (Flexible to allow Stats on right) ---
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Merge Button
                  MovieManagerIconButton(
                    label: 'Merge selected tags',
                    icon: CupertinoIcons.arrow_merge,
                    onPressed: _selectedTags.length >= 2
                        ? _showMergeDialog
                        : null,
                  ),

                  const SizedBox(width: 16),

                  // Sort Buttons
                  const Text(
                    'Sort:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 8),

                  _SortButton(
                    label: 'Name',
                    isActive: _sortOption == TagSortOption.name,
                    isAscending: _sortDirection == TagSortDirection.asc,
                    onPressed: () => _setSort(TagSortOption.name),
                  ),
                  const SizedBox(width: 4),
                  _SortButton(
                    label: 'Count',
                    isActive: _sortOption == TagSortOption.count,
                    isAscending: _sortDirection == TagSortDirection.asc,
                    onPressed: () => _setSort(TagSortOption.count),
                  ),

                  const SizedBox(width: 16),

                  // Filters
                  const Text(
                    'Show:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 8),

                  _FilterCheckbox(
                    label: 'User',
                    isChecked: _showUserTags,
                    onChanged: (v) => setState(() => _showUserTags = v),
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  _FilterCheckbox(
                    label: 'Auto',
                    isChecked: _showAutoTags,
                    onChanged: (v) => setState(() => _showAutoTags = v),
                    theme: theme,
                  ),

                  // Clear Selection/Search
                  if (_searchQuery.isNotEmpty || _selectedTags.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    PushButton(
                      controlSize: ControlSize.small,
                      secondary: true,
                      child: const Text('Reset'),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                          _selectedTags.clear();
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // --- RIGHT: STATS (On the same row, aligned right) ---
          if (_stats != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MiniStat(label: 'Total', value: '${_stats!.uniqueTagCount}'),
                const SizedBox(width: 12),
                _MiniStat(label: 'User', value: '${_stats!.userTags}'),
                const SizedBox(width: 12),
                _MiniStat(label: 'Auto', value: '${_stats!.autoTags}'),
                const SizedBox(width: 12),
                _MiniStat(
                  label: 'Avg/Vid',
                  value: _stats!.avgTagsPerVideo.toStringAsFixed(1),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ... existing _buildTagCloud ...

  // ... existing dialogs ...

  // ... existing _TagChip and _ActionButton ...

  Widget _buildTagCloud(MacosThemeData theme) {
    final folderIds = ref.watch(effectiveLibraryFolderIdsProvider);
    final tagsStream = ref
        .watch(tagsDaoProvider)
        .watchAllTagsWithInfo(folderIds: folderIds);

    return StreamBuilder<List<TagInfo>>(
      stream: tagsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: ProgressCircle());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final allTags = snapshot.data ?? [];
        final processedTags = _processTags(List.from(allTags));

        if (processedTags.isEmpty) {
          return Center(
            child: Text(
              allTags.isEmpty
                  ? 'No tags found in library'
                  : 'No tags match current filters',
              style: TextStyle(
                color: theme.typography.body.color?.withValues(alpha: 0.6),
              ),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 44,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: processedTags.length,
          itemBuilder: (context, index) {
            final tag = processedTags[index];
            final isSelected = _selectedTags.contains(tag.tagText);
            return _TagChip(
              tag: tag,
              isSelected: isSelected,
              theme: theme,
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedTags.remove(tag.tagText);
                  } else {
                    _selectedTags.add(tag.tagText);
                  }
                });
              },
              onRename: () => _showRenameDialog(tag),
              onDelete: () => _confirmDelete(tag),
              onViewVideos: () {
                ref
                    .read(catalogControllerProvider.notifier)
                    .setPrimaryTag(tag.tagText);
                Navigator.of(context).pop();
              },
            );
          },
        );
      },
    );
  }

  // Dialogs remain largely the same, just keeping them for completeness
  void _showRenameDialog(TagInfo tag) {
    final controller = TextEditingController(text: tag.tagText);

    showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.pencil),
        title: const Text('Rename Tag'),
        message: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Renaming "${tag.tagText}" (used in ${tag.videoCount} videos)',
            ),
            const SizedBox(height: 12),
            MovieManagerLabeledField(
              label: 'New tag name',
              controller: controller,
              builder: (focusNode) => MacosTextField(
                controller: controller,
                focusNode: focusNode,
                placeholder: 'New tag name',
                autofocus: true,
              ),
            ),
          ],
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('Rename'),
          onPressed: () async {
            final newName = controller.text.trim();
            if (newName.isEmpty) {
              Navigator.pop(context);
              return;
            }

            Navigator.pop(context);

            try {
              final result = await ref
                  .read(tagsDaoProvider)
                  .renameTag(tag.tagText, newName);
              if (mounted) {
                _showResultToast(
                  'Renamed "${tag.tagText}" to "$newName": ${result.updated} updated',
                );
                _loadStats();
              }
            } catch (e) {
              if (mounted) {
                _showResultToast('Error: $e', isError: true);
              }
            }
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _showMergeDialog() {
    final controller = TextEditingController(
      text: _selectedTags.isNotEmpty ? _selectedTags.first : '',
    );

    showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.arrow_merge),
        title: const Text('Merge Tags'),
        message: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Merging ${_selectedTags.length} tags: ${_selectedTags.join(", ")}',
            ),
            const SizedBox(height: 8),
            const Text('Enter the target tag name:'),
            const SizedBox(height: 12),
            MovieManagerLabeledField(
              label: 'Target tag name',
              controller: controller,
              builder: (focusNode) => MacosTextField(
                controller: controller,
                focusNode: focusNode,
                placeholder: 'Target tag name',
                autofocus: true,
              ),
            ),
          ],
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          child: const Text('Merge'),
          onPressed: () async {
            final targetName = controller.text.trim();
            if (targetName.isEmpty) {
              Navigator.pop(context);
              return;
            }

            Navigator.pop(context);

            try {
              final result = await ref
                  .read(tagsDaoProvider)
                  .mergeTags(_selectedTags.toList(), targetName);
              if (mounted) {
                _showResultToast(
                  'Merged ${result.tagsRemoved} tags into "$targetName"',
                );
                setState(() => _selectedTags.clear());
                _loadStats();
              }
            } catch (e) {
              if (mounted) {
                _showResultToast('Error: $e', isError: true);
              }
            }
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _confirmDelete(TagInfo tag) {
    showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: MacosIcon(
          CupertinoIcons.trash,
          color: MacosColors.systemRedColor,
        ),
        title: const Text('Delete Tag?'),
        message: Text(
          'Delete "${tag.tagText}" from all ${tag.videoCount} videos?\nCannot be undone.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: MacosColors.systemRedColor,
          child: const Text('Delete'),
          onPressed: () async {
            Navigator.pop(context);
            await ref.read(tagsDaoProvider).deleteTagFromAllVideos(tag.tagText);
            if (mounted) {
              _showResultToast('Deleted "${tag.tagText}"');
              _loadStats();
            }
          },
        ),
        secondaryButton: PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _showResultToast(String message, {bool isError = false}) {
    final overlay = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 50,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isError
                    ? MacosColors.systemRedColor.withValues(alpha: 0.9)
                    : MacosColors.systemGrayColor.darkColor.withValues(
                        alpha: 0.9,
                      ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message,
                style: const TextStyle(color: MacosColors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(overlay);
    Future.delayed(const Duration(seconds: 3), () => overlay.remove());
  }
}

class _TagChip extends StatefulWidget {
  final TagInfo tag;
  final bool isSelected;
  final MacosThemeData theme;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onViewVideos;

  const _TagChip({
    required this.tag,
    required this.isSelected,
    required this.theme,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onViewVideos,
  });

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _isHovered = false;
  bool _isFocused = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.tag.tagText);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    // Matches the visual style of Sidebar tags approx
    return Semantics(
      label: '${widget.tag.tagText}, ${widget.tag.videoCount} videos',
      button: true,
      selected: widget.isSelected,
      focusable: true,
      focused: _focusNode.hasFocus,
      onFocus: _focusNode.requestFocus,
      onTap: widget.onTap,
      customSemanticsActions: {
        CustomSemanticsAction(label: 'View videos'): widget.onViewVideos,
        CustomSemanticsAction(label: 'Rename tag'): widget.onRename,
        CustomSemanticsAction(label: 'Delete tag'): widget.onDelete,
      },
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        onShowFocusHighlight: (value) => setState(() => _isFocused = value),
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
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? theme.primaryColor
                    : MacosColors.systemGrayColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(MovieManagerRadii.panel),
                border: Border.all(
                  color: widget.isSelected || _isFocused
                      ? theme.primaryColor
                      : MovieManagerVisuals.isHighContrast(context)
                      ? MovieManagerVisuals.secondaryLabelColor(context)
                      : MacosColors.systemGrayColor.withValues(alpha: 0.2),
                  width:
                      _isFocused || MovieManagerVisuals.isHighContrast(context)
                      ? 2
                      : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ExcludeSemantics(
                      child: Text(
                        '${widget.tag.tagText} (${widget.tag.videoCount})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.isSelected
                              ? MacosColors.white
                              : theme.typography.body.color?.withValues(
                                  alpha: 0.9,
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (_isHovered || widget.isSelected || _isFocused) ...[
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: CupertinoIcons.play_circle,
                      onTap: widget.onViewVideos,
                      isSelected: widget.isSelected,
                      tooltip: 'View videos with this tag',
                    ),
                    const SizedBox(width: 4),
                    _ActionButton(
                      icon: CupertinoIcons.pencil,
                      onTap: widget.onRename,
                      isSelected: widget.isSelected,
                      tooltip: 'Rename tag',
                    ),
                    const SizedBox(width: 4),
                    _ActionButton(
                      icon: CupertinoIcons.trash,
                      onTap: widget.onDelete,
                      isSelected: widget.isSelected,
                      isDestructive: true,
                      tooltip: 'Delete tag',
                    ),
                  ],
                  if (!_isHovered && !widget.isSelected && !_isFocused) ...[
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: CupertinoIcons.ellipsis,
                      onTap: widget.onViewVideos,
                      isSelected: false,
                      tooltip: 'View videos and tag actions',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isDestructive;
  final String? tooltip;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.isSelected,
    this.isDestructive = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return MovieManagerIconButton(
      label: tooltip ?? 'Tag action',
      icon: icon,
      color: isSelected
          ? MacosColors.white
          : isDestructive
          ? MovieManagerVisuals.errorColor(context)
          : null,
      onPressed: onTap,
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: theme.typography.body.color?.withValues(alpha: 0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: theme.primaryColor,
          ),
        ),
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isAscending;
  final VoidCallback onPressed;

  const _SortButton({
    required this.label,
    required this.isActive,
    required this.isAscending,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return PushButton(
      controlSize: ControlSize.small,
      secondary: true,
      onPressed: onPressed,
      child: Semantics(
        selected: isActive,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                isAscending
                    ? CupertinoIcons.arrow_up
                    : CupertinoIcons.arrow_down,
                size: 12,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterCheckbox extends StatelessWidget {
  final String label;
  final bool isChecked;
  final ValueChanged<bool> onChanged;
  final MacosThemeData theme;

  const _FilterCheckbox({
    required this.label,
    required this.isChecked,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MacosPreferenceCheckbox(
          value: isChecked,
          semanticLabel: 'Show $label tags',
          onChanged: onChanged,
        ),
        const SizedBox(width: MovieManagerSpacing.compact),
        ExcludeSemantics(
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
