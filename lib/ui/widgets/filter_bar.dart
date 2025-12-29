import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../logic/filter_controller.dart';

class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTagsAsync = ref.watch(allTagsProvider);
    final selectedTags = ref.watch(selectedTagsProvider);

    return allTagsAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(16.0),
        child: ProgressCircle(radius: 10),
      )),
      error: (_, __) => const SizedBox.shrink(),
      data: (tags) {
        if (tags.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((tag) {
              final isSelected = selectedTags.contains(tag);
              final theme = MacosTheme.of(context);

              return GestureDetector(
                onTap: () => ref.read(selectedTagsProvider.notifier).toggle(tag),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: isSelected ? MacosColors.white : theme.typography.body.color?.withOpacity(0.9),
                      fontSize: 11,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
