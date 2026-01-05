import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Material;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../data/database.dart';
import '../../data/providers.dart';

class TagManagementScreen extends ConsumerStatefulWidget {
  const TagManagementScreen({super.key});

  @override
  ConsumerState<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends ConsumerState<TagManagementScreen> {
  final Set<String> _selectedTags = {};
  String _searchQuery = '';
  TagStatistics? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await ref.read(tagsDaoProvider).getTagStatistics();
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    
    return MacosScaffold(
      backgroundColor: theme.canvasColor,
      toolBar: ToolBar(
        decoration: BoxDecoration(
          color: theme.canvasColor,
        ),
        title: const Text('Tag Management'),
        leading: MacosBackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          ToolBarIconButton(
            label: 'Merge',
            icon: const MacosIcon(CupertinoIcons.arrow_merge),
            showLabel: true,
            onPressed: _selectedTags.length >= 2 ? _showMergeDialog : null,
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, scrollController) {
            return Container(
              color: theme.canvasColor,
              child: Column(
                children: [
                   // Statistics Panel
                  if (_stats != null) _buildStatsPanel(theme),
                  
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: MacosTextField(
                      placeholder: 'Search tags...',
                      prefix: const MacosIcon(CupertinoIcons.search),
                      onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                    ),
                  ),
                  
                  // Tag List
                  Expanded(
                    child: _buildTagList(theme),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatsPanel(MacosThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.canvasColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MacosColors.systemGrayColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(label: 'Total Tags', value: '${_stats!.uniqueTagCount}'),
          _StatItem(label: 'User Tags', value: '${_stats!.userTags}'),
          _StatItem(label: 'Auto Tags', value: '${_stats!.autoTags}'),
          _StatItem(label: 'Avg/Video', value: _stats!.avgTagsPerVideo.toStringAsFixed(1)),
        ],
      ),
    );
  }

  Widget _buildTagList(MacosThemeData theme) {
    final tagsStream = ref.watch(tagsDaoProvider).watchAllTagsWithInfo();
    
    return StreamBuilder<List<TagInfo>>(
      stream: tagsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: ProgressCircle());
        }
        
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final allTags = snapshot.data ?? [];
        final filteredTags = _searchQuery.isEmpty 
          ? allTags 
          : allTags.where((t) => t.tagText.contains(_searchQuery)).toList();
        
        if (filteredTags.isEmpty) {
          return Center(
            child: Text(
              allTags.isEmpty ? 'No tags found' : 'No tags match your search',
              style: TextStyle(color: theme.typography.body.color?.withValues(alpha: 0.6)),
            ),
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: filteredTags.length,
          itemBuilder: (context, index) {
            final tag = filteredTags[index];
            final isSelected = _selectedTags.contains(tag.tagText);
            
            return _TagListItem(
              tag: tag,
              isSelected: isSelected,
              index: index,
              theme: theme,
              onCheckboxChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedTags.add(tag.tagText);
                  } else {
                    _selectedTags.remove(tag.tagText);
                  }
                });
              },
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
            );
          },
        );
      },
    );
  }

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
            Text('Renaming "${tag.tagText}" (used in ${tag.videoCount} videos)'),
            const SizedBox(height: 12),
            MacosTextField(
              controller: controller,
              placeholder: 'New tag name',
              autofocus: true,
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
              final result = await ref.read(tagsDaoProvider).renameTag(tag.tagText, newName);
              if (mounted) {
                _showResultToast(
                  'Renamed "${tag.tagText}" to "$newName": ${result.updated} updated, ${result.skipped} skipped (conflicts)',
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
    // Pre-populate with the first selected tag
    final controller = TextEditingController(text: _selectedTags.isNotEmpty ? _selectedTags.first : '');
    
    showMacosAlertDialog(
      context: context,
      builder: (context) => MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.arrow_merge),
        title: const Text('Merge Tags'),
        message: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Merging ${_selectedTags.length} tags: ${_selectedTags.join(", ")}'),
            const SizedBox(height: 8),
            const Text('Enter the target tag name:'),
            const SizedBox(height: 12),
            MacosTextField(
              controller: controller,
              placeholder: 'Target tag name',
              autofocus: true,
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
              final result = await ref.read(tagsDaoProvider).mergeTags(
                _selectedTags.toList(),
                targetName,
              );
              if (mounted) {
                _showResultToast(
                  'Merged ${result.tagsRemoved} tags into "$targetName": ${result.videosAffected} videos affected',
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
        appIcon: MacosIcon(CupertinoIcons.trash, color: MacosColors.systemRedColor),
        title: const Text('Delete Tag?'),
        message: Text(
          'Are you sure you want to delete "${tag.tagText}" from all ${tag.videoCount} videos?\n\nThis action cannot be undone.',
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          color: MacosColors.systemRedColor,
          child: const Text('Delete'),
          onPressed: () async {
            Navigator.pop(context);
            await ref.read(tagsDaoProvider).deleteTagFromAllVideos(tag.tagText);
            if (mounted) {
              _showResultToast('Deleted "${tag.tagText}" from all videos');
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
    // Using a simple snackbar-like overlay for feedback
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
                  : MacosColors.systemGrayColor.darkColor.withValues(alpha: 0.9),
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

class _TagListItem extends StatefulWidget {
  final TagInfo tag;
  final bool isSelected;
  final int index;
  final MacosThemeData theme;
  final ValueChanged<bool?> onCheckboxChanged;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _TagListItem({
    required this.tag,
    required this.isSelected,
    required this.index,
    required this.theme,
    required this.onCheckboxChanged,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_TagListItem> createState() => _TagListItemState();
}

class _TagListItemState extends State<_TagListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    
    // Alternating colors
    final alternateColor = isDark 
        ? theme.canvasColor.withValues(alpha: 0.3)
        : MacosColors.systemGrayColor.withValues(alpha: 0.05);
    
    final baseColor = widget.index % 2 == 0 ? Colors.transparent : alternateColor;
    
    // Hover highlight
    final hoverColor = isDark
        ? theme.primaryColor.withValues(alpha: 0.15)
        : theme.primaryColor.withValues(alpha: 0.08);

    // Selected color
    final selectedColor = theme.primaryColor.withValues(alpha: 0.2);

    Color finalColor = baseColor;
    if (widget.isSelected) {
      finalColor = selectedColor;
    } else if (_isHovered) {
      finalColor = hoverColor;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: finalColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              // Custom checkbox for guaranteed visibility
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: widget.isSelected ? theme.primaryColor : theme.typography.body.color!.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  color: widget.isSelected ? theme.primaryColor : Colors.transparent,
                ),
                child: widget.isSelected 
                  ? const Center(
                      child: Icon(
                        CupertinoIcons.checkmark,
                        size: 10,
                        color: MacosColors.white,
                      ),
                    )
                  : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.tag.tagText,
                      style: theme.typography.body,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.tag.videoCount} video${widget.tag.videoCount == 1 ? '' : 's'} • ${widget.tag.sourceType}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.typography.body.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // Rename button - only visible on hover or if selected
              if (_isHovered || widget.isSelected) ...[
                MacosIconButton(
                  icon: const MacosIcon(CupertinoIcons.pencil, size: 14),
                  onPressed: widget.onRename,
                ),
                const SizedBox(width: 4),
                MacosIconButton(
                  icon: MacosIcon(
                    CupertinoIcons.trash,
                    size: 14,
                    color: MacosColors.systemRedColor,
                  ),
                  onPressed: widget.onDelete,
                ),
              ] else ...[
                const SizedBox(width: 60), // Placeholder to maintain width
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.typography.body.color?.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
