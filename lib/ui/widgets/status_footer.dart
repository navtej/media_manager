import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../logic/library_controller.dart';
import '../../logic/status_message_provider.dart';

class StatusFooter extends ConsumerWidget {
  const StatusFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanStatus = ref.watch(scanStatusProvider);
    final aiStatus = ref.watch(aIStatusProvider);
    final statusMsg = ref.watch(statusMessageProvider);
    
    // If we have a transient status message, show it with high priority
    if (statusMsg != null) {
      return Container(
        height: 32,
        width: double.infinity,
        color: MacosTheme.of(context).primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            const Icon(CupertinoIcons.check_mark_circled, color: MacosColors.white, size: 14),
            const SizedBox(width: 8),
            Text(
              statusMsg,
              style: const TextStyle(fontSize: 11, color: MacosColors.white),
            ),
          ],
        ),
      );
    }
    
    if (scanStatus.isEmpty && aiStatus.isEmpty) return const SizedBox.shrink();

    final statusText = [
      if (scanStatus.isNotEmpty) scanStatus,
      if (aiStatus.isNotEmpty) aiStatus,
    ].join(' | ');

    return Container(
      height: 32,
      width: double.infinity,
      color: MacosTheme.of(context).primaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const CupertinoActivityIndicator(radius: 7, color: MacosColors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: MacosColors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
