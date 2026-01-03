import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../logic/library_controller.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/stats_provider.dart';
import '../../logic/filter_controller.dart';

class StatusFooter extends ConsumerWidget {
  const StatusFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanStatus = ref.watch(scanStatusProvider);
    final aiStatus = ref.watch(aIStatusProvider);
    final statusMsg = ref.watch(statusMessageProvider);
    
    final totalVideosSync = ref.watch(libraryStatsProvider);
    final visibleVideosSync = ref.watch(filteredVideosProvider);

    final totalCount = totalVideosSync.when(data: (s) => s.totalCount, error: (_, __) => 0, loading: () => 0);
    final visibleCount = visibleVideosSync.when(data: (v) => v.length, error: (_, __) => 0, loading: () => 0);

    return Container(
      height: 32,
      width: double.infinity,
      color: MacosTheme.of(context).primaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Left side: Status messages or indicators
          if (statusMsg != null) ...[
            const Icon(CupertinoIcons.check_mark_circled, color: MacosColors.white, size: 14),
            const SizedBox(width: 8),
            Text(
              statusMsg,
              style: const TextStyle(fontSize: 11, color: MacosColors.white),
            ),
          ] else if (scanStatus.isNotEmpty || aiStatus.isNotEmpty) ...[
            const CupertinoActivityIndicator(radius: 7, color: MacosColors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [scanStatus, aiStatus].where((s) => s.isNotEmpty).join(' | '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: MacosColors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else
            const Spacer(),

          // Right side: Video counts
          if (statusMsg == null) ...[
            const Spacer(),
            Text(
              'Videos : $visibleCount / $totalCount',
              style: const TextStyle(
                fontSize: 11, 
                color: MacosColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
