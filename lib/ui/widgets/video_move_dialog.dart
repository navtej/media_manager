import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../logic/library_controller.dart';
import '../../logic/video_move_controller.dart';

class VideoMoveDialogResult {
  const VideoMoveDialogResult({
    required this.moveResult,
    this.scanDestinationFolder,
  });

  final VideoMoveResult moveResult;
  final Folder? scanDestinationFolder;
}

Future<void> showVideoMoveDialog({
  required BuildContext context,
  required WidgetRef ref,
  required List<int> selectedVideoIds,
}) async {
  final dialogResult = await showMacosAlertDialog<VideoMoveDialogResult>(
    context: context,
    builder: (dialogContext) =>
        _VideoMoveDialog(selectedVideoIds: selectedVideoIds),
  );
  if (!context.mounted || dialogResult == null) {
    return;
  }

  final scanFolder = dialogResult.scanDestinationFolder;
  if (scanFolder != null && dialogResult.moveResult.movedCount > 0) {
    await ref
        .read(libraryControllerProvider.notifier)
        .scanFolder(scanFolder.path, scanFolder.id);
  }

  if (!context.mounted) {
    return;
  }
  if (dialogResult.moveResult.hasFailuresOrSkips) {
    await showVideoMoveResultDialog(
      context: context,
      result: dialogResult.moveResult,
    );
  }
}

Future<void> showVideoMoveResultDialog({
  required BuildContext context,
  required VideoMoveResult result,
}) {
  return showMacosAlertDialog<void>(
    context: context,
    builder: (dialogContext) {
      final dialogBodySize = _wideCompactDialogBodySize(dialogContext);
      return MacosAlertDialog(
        appIcon: const MacosIcon(CupertinoIcons.arrow_right_arrow_left),
        title: const Text('Move Results'),
        message: SizedBox(
          width: dialogBodySize.width,
          height: dialogBodySize.height,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResultSection(title: 'Skipped', items: result.skipped),
                if (result.skipped.isNotEmpty && result.failures.isNotEmpty)
                  const SizedBox(height: 12),
                _ResultSection(title: 'Failed', items: result.failures),
              ],
            ),
          ),
        ),
        primaryButton: PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      );
    },
  );
}

@visibleForTesting
Size wideCompactMoveDialogBodySizeForTesting(Size windowSize) {
  return _wideCompactDialogBodySizeForWindow(windowSize);
}

Size _wideCompactDialogBodySize(BuildContext context) {
  return _wideCompactDialogBodySizeForWindow(MediaQuery.sizeOf(context));
}

Size _wideCompactDialogBodySizeForWindow(Size windowSize) {
  final availableWidth = math.max(0.0, windowSize.width - 96);
  final availableHeight = math.max(0.0, windowSize.height - 220);
  final width = (windowSize.width * 0.82).clamp(700.0, 1100.0);
  final height = (windowSize.height * 0.48).clamp(260.0, 360.0);

  return Size(
    math.min(width, availableWidth),
    math.min(height, availableHeight),
  );
}

class _VideoMoveDialog extends ConsumerStatefulWidget {
  const _VideoMoveDialog({required this.selectedVideoIds});

  final List<int> selectedVideoIds;

  @override
  ConsumerState<_VideoMoveDialog> createState() => _VideoMoveDialogState();
}

class _VideoMoveDialogState extends ConsumerState<_VideoMoveDialog> {
  static const double _popupLabelReservedWidth = 40;

  int? _destinationFolderId;
  int? _scanAfterMoveFolderId;
  bool _removeEmptySourceFolders = false;
  bool _isSubmitting = false;
  Object? _actionError;
  Future<VideoMovePreflight>? _preflightFuture;
  int? _preflightDestinationFolderId;
  String? _preflightSelectionKey;

  @override
  Widget build(BuildContext context) {
    final foldersStream = ref.watch(foldersDaoProvider).watchAllFolders();
    return StreamBuilder<List<Folder>>(
      stream: foldersStream,
      builder: (context, snapshot) {
        final folders = snapshot.data ?? const <Folder>[];
        final effectiveDestinationId =
            _destinationFolderId ?? folders.firstOrNull?.id;
        final preflightFuture = effectiveDestinationId == null
            ? null
            : _preflightFor(effectiveDestinationId);

        return FutureBuilder<VideoMovePreflight>(
          future: preflightFuture,
          builder: (context, preflightSnapshot) {
            return _buildDialog(
              context: context,
              folders: folders,
              effectiveDestinationId: effectiveDestinationId,
              preflightSnapshot: preflightSnapshot,
            );
          },
        );
      },
    );
  }

  MacosAlertDialog _buildDialog({
    required BuildContext context,
    required List<Folder> folders,
    required int? effectiveDestinationId,
    required AsyncSnapshot<VideoMovePreflight> preflightSnapshot,
  }) {
    final moveState = ref.watch(videoMoveControllerProvider);
    final preflight = preflightSnapshot.data;
    final isLoadingPreflight =
        effectiveDestinationId != null &&
        preflightSnapshot.connectionState != ConnectionState.done;
    final canSubmit =
        !_isSubmitting &&
        !moveState.isMoving &&
        effectiveDestinationId != null &&
        preflight?.canMove == true;
    final dialogBodySize = _wideCompactDialogBodySize(context);

    return MacosAlertDialog(
      appIcon: const MacosIcon(CupertinoIcons.arrow_right_arrow_left),
      title: const Text('Move Selected Videos'),
      message: SizedBox(
        width: dialogBodySize.width,
        height: dialogBodySize.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.selectedVideoIds.length} selected'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final labelWidth = math.max(
                        0.0,
                        constraints.maxWidth - _popupLabelReservedWidth,
                      );
                      return MacosPopupButton<int>(
                        value: effectiveDestinationId,
                        selectedItemBuilder: (_) => folders
                            .map(
                              (folder) => _FolderPopupLabel(
                                label: _folderLabel(folder),
                                width: labelWidth,
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _isSubmitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _destinationFolderId = value;
                                  _actionError = null;
                                  _clearPreflight();
                                });
                              },
                        items: folders
                            .map(
                              (folder) => MacosPopupMenuItem<int>(
                                value: folder.id,
                                child: _FolderPopupLabel(
                                  label: _folderLabel(folder),
                                  width: labelWidth,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PushButton(
                  controlSize: ControlSize.small,
                  secondary: true,
                  onPressed: _isSubmitting ? null : _addDestinationFolder,
                  child: const Text('Add Folder'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CleanupOption(
              value: _removeEmptySourceFolders,
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      setState(() {
                        _removeEmptySourceFolders = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _PreflightPreview(
                isLoading: isLoadingPreflight,
                preflight: preflight,
                error: preflightSnapshot.error ?? _actionError,
              ),
            ),
          ],
        ),
      ),
      primaryButton: PushButton(
        controlSize: ControlSize.large,
        onPressed: canSubmit ? () => _submit(effectiveDestinationId) : null,
        child: Text(_isSubmitting ? 'Moving...' : 'Move'),
      ),
      secondaryButton: PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    );
  }

  Future<VideoMovePreflight> _preflightFor(int destinationFolderId) {
    final selectionKey = widget.selectedVideoIds.join(',');
    if (_preflightFuture == null ||
        _preflightDestinationFolderId != destinationFolderId ||
        _preflightSelectionKey != selectionKey) {
      _preflightDestinationFolderId = destinationFolderId;
      _preflightSelectionKey = selectionKey;
      _preflightFuture = ref
          .read(videoMoveControllerProvider.notifier)
          .preflightMove(
            videoIds: widget.selectedVideoIds,
            destinationFolderId: destinationFolderId,
          );
    }
    return _preflightFuture!;
  }

  void _clearPreflight() {
    _preflightFuture = null;
    _preflightDestinationFolderId = null;
    _preflightSelectionKey = null;
  }

  Future<void> _addDestinationFolder() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null || selectedDirectory.isEmpty) {
      return;
    }

    try {
      final folder = await ref
          .read(videoMoveControllerProvider.notifier)
          .addManagedDestinationFolder(selectedDirectory);
      if (!mounted) {
        return;
      }
      setState(() {
        _destinationFolderId = folder.id;
        _scanAfterMoveFolderId = folder.id;
        _actionError = null;
        _clearPreflight();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = error;
      });
    }
  }

  Future<void> _submit(int destinationFolderId) async {
    setState(() {
      _isSubmitting = true;
      _actionError = null;
    });

    try {
      final result = await ref
          .read(videoMoveControllerProvider.notifier)
          .moveVideos(
            videoIds: widget.selectedVideoIds,
            destinationFolderId: destinationFolderId,
            removeEmptySourceFolders: _removeEmptySourceFolders,
          );
      if (!mounted) {
        return;
      }
      final scanFolder = _scanAfterMoveFolderId == destinationFolderId
          ? await ref
                .read(foldersDaoProvider)
                .getFolderById(destinationFolderId)
          : null;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        VideoMoveDialogResult(
          moveResult: result,
          scanDestinationFolder: scanFolder,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _actionError = error;
        _isSubmitting = false;
        _clearPreflight();
      });
    }
  }

  String _folderLabel(Folder folder) {
    final alias = folder.alias;
    if (alias != null && alias.isNotEmpty) {
      return '$alias (${folder.path})';
    }
    return folder.path;
  }
}

class _FolderPopupLabel extends StatelessWidget {
  const _FolderPopupLabel({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _PreflightPreview extends StatelessWidget {
  const _PreflightPreview({
    required this.isLoading,
    required this.preflight,
    required this.error,
  });

  final bool isLoading;
  final VideoMovePreflight? preflight;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: ProgressCircle());
    }
    if (error != null) {
      return Text(
        error.toString(),
        style: const TextStyle(color: MacosColors.appleRed),
      );
    }
    if (preflight == null) {
      return const Text('Choose a destination folder.');
    }
    final currentPreflight = preflight!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentPreflight.items.isNotEmpty) ...[
            Text(
              'Preview',
              style: MacosTheme.of(context).typography.subheadline,
            ),
            const SizedBox(height: 6),
            ...currentPreflight.items.take(5).map((item) {
              final destination = item.isNoOp
                  ? 'Already in destination'
                  : p.relative(item.destinationPath);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${item.video.title} -> $destination',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MacosTheme.of(context).typography.caption1,
                ),
              );
            }),
            if (currentPreflight.items.length > 5)
              Text(
                '+ ${currentPreflight.items.length - 5} more',
                style: MacosTheme.of(context).typography.caption1,
              ),
          ],
          if (currentPreflight.errors.isNotEmpty ||
              currentPreflight.conflicts.isNotEmpty)
            const SizedBox(height: 12),
          ...currentPreflight.errors.map(
            (message) => _ProblemLine(message: message),
          ),
          ...currentPreflight.conflicts.map(
            (conflict) => _ProblemLine(
              message: '${conflict.message} ${conflict.destinationPath}',
            ),
          ),
        ],
      ),
    );
  }
}

class _ProblemLine extends StatelessWidget {
  const _ProblemLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(message, style: const TextStyle(color: MacosColors.appleRed)),
    );
  }
}

class _CleanupOption extends StatelessWidget {
  const _CleanupOption({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        children: [
          _SmallCheckbox(value: value),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Remove empty source folders after move',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MacosTheme.of(context).typography.caption1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallCheckbox extends StatelessWidget {
  const _SmallCheckbox({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: value ? theme.primaryColor : MacosColors.transparent,
        border: Border.all(
          color: value
              ? theme.primaryColor
              : MacosColors.systemGrayColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: value
          ? const Icon(
              CupertinoIcons.checkmark,
              size: 12,
              color: MacosColors.white,
            )
          : null,
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.items});

  final String title;
  final List<VideoMoveItemResult> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: MacosTheme.of(context).typography.subheadline),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${item.title}: ${item.message}',
              style: MacosTheme.of(context).typography.caption1,
            ),
          ),
        ),
      ],
    );
  }
}
