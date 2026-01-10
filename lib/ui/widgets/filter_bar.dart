import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../logic/filter_controller.dart';
import '../../data/providers.dart';

class TagCloud extends ConsumerWidget {
  final List<MapEntry<String, int>> tags;
  final Set<String> selectedTags;
  final bool enableDelete;
  final Function(String) onTagSelected;

  const TagCloud({
    super.key,
    required this.tags,
    required this.selectedTags,
    required this.onTagSelected,
    this.enableDelete = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: tags.map((entry) {
          final tag = entry.key;
          final count = entry.value;
          final isSelected = selectedTags.contains(tag);
          final theme = MacosTheme.of(context);

          return GestureDetector(
            onTap: () => onTagSelected(tag),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              constraints: const BoxConstraints(maxWidth: 160), // Prevent overflow
              decoration: BoxDecoration(
                color: isSelected 
                  ? theme.primaryColor 
                  : MacosColors.systemGrayColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected 
                    ? theme.primaryColor 
                    : MacosColors.systemGrayColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '$tag ($count)',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: isSelected ? MacosColors.white : theme.typography.body.color?.withOpacity(0.9),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (enableDelete) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        // Show confirmation dialog before deleting from all videos
                        showMacosAlertDialog(
                          context: context,
                          builder: (context) => MacosAlertDialog(
                            appIcon: const MacosIcon(CupertinoIcons.tag),
                            title: const Text('Delete Tag?'),
                            message: Text('Are you sure you want to delete the tag "$tag" from all $count associated videos?'),
                            primaryButton: PushButton(
                              controlSize: ControlSize.large,
                              child: const Text('Delete'),
                              onPressed: () {
                                Navigator.pop(context);
                                ref.read(tagsDaoProvider).deleteTagFromAllVideos(tag);
                              },
                            ),
                            secondaryButton: PushButton(
                              controlSize: ControlSize.large,
                              child: const Text('Cancel'),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        );
                      },
                      child: Icon(
                        CupertinoIcons.trash,
                        size: 9, // Slightly smaller
                        color: isSelected ? MacosColors.white.withOpacity(0.8) : theme.typography.body.color?.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
