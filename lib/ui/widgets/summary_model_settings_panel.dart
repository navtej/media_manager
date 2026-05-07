import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../logic/video_summary_models.dart';
import '../../logic/whisper_model_catalog.dart';

class SummaryModelSettingsPanel extends StatelessWidget {
  const SummaryModelSettingsPanel({
    super.key,
    required this.sourceMode,
    required this.modelPath,
    required this.selectedModelId,
    required this.downloadedManagedModels,
    required this.validation,
    required this.runtimeStatus,
    required this.catalogState,
    required this.downloadState,
    required this.canDeleteManagedModel,
    required this.preferVttSubtitles,
    required this.statusMessage,
    required this.onSourceModeChanged,
    required this.onSelectedModelChanged,
    required this.onPreferVttSubtitlesChanged,
    required this.onDownloadPressed,
    required this.onStopDownloadPressed,
    required this.onDeletePressed,
    required this.onBrowsePressed,
    required this.onRevealPressed,
    required this.onRefreshCatalogPressed,
    required this.onClearSelectionPressed,
  });

  final SummaryModelSourceMode sourceMode;
  final String modelPath;
  final String? selectedModelId;
  final Map<String, String> downloadedManagedModels;
  final SummaryModelValidationResult validation;
  final String runtimeStatus;
  final WhisperModelCatalogState catalogState;
  final ModelDownloadState downloadState;
  final bool canDeleteManagedModel;
  final bool preferVttSubtitles;
  final String? statusMessage;
  final ValueChanged<SummaryModelSourceMode> onSourceModeChanged;
  final ValueChanged<String?> onSelectedModelChanged;
  final ValueChanged<bool> onPreferVttSubtitlesChanged;
  final VoidCallback onDownloadPressed;
  final VoidCallback onStopDownloadPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onBrowsePressed;
  final VoidCallback onRevealPressed;
  final VoidCallback onRefreshCatalogPressed;
  final VoidCallback onClearSelectionPressed;

  @override
  Widget build(BuildContext context) {
    final isDownloading = downloadState.phase == ModelDownloadPhase.downloading;
    final availableIds = catalogState.entries.map((entry) => entry.id).toSet();
    final downloadedEntries = catalogState.entries
        .where((entry) => downloadedManagedModels.containsKey(entry.id))
        .toList();
    final selectedCatalogId = availableIds.contains(selectedModelId)
        ? selectedModelId
        : (catalogState.entries.isNotEmpty
              ? catalogState.entries.first.id
              : null);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Summary Model',
            style: MacosTheme.of(context).typography.headline,
          ),
          const SizedBox(height: 10),
          const Text(
            "Video summarization uses MovieManager's bundled Whisper runtime.",
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const SizedBox(width: 200, child: Text('Model Source')),
              MacosPopupButton<String>(
                value: sourceMode.value,
                onChanged: isDownloading
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }

                        onSourceModeChanged(
                          SummaryModelSourceMode.fromValue(value),
                        );
                      },
                items: const [
                  MacosPopupMenuItem(
                    value: 'managed',
                    child: Text('Managed Download'),
                  ),
                  MacosPopupMenuItem(
                    value: 'local',
                    child: Text('Use Existing Local Model'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 200, child: Text('Available Models')),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: sourceMode == SummaryModelSourceMode.localFile
                      ? _LocalSelectedModelPathField(modelPath: modelPath)
                      : SizedBox(
                          width: 360,
                          child: _KeyboardNavigableModelPicker(
                            key: const ValueKey('available-models-picker'),
                            value: selectedCatalogId,
                            enabled: !isDownloading,
                            entries: catalogState.entries,
                            onChanged: onSelectedModelChanged,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 200, child: Text('Model Status')),
              Text(validation.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 200, child: Text('Runtime Status')),
              Text(runtimeStatus),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 200, child: Text('Model Path')),
              Expanded(
                child: SelectableText(
                  modelPath.isEmpty ? 'Not configured' : modelPath,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 200, child: Text('Subtitle Transcript')),
              _MacosPreferenceCheckbox(
                key: const ValueKey('prefer-vtt-subtitles-checkbox'),
                value: preferVttSubtitles,
                onChanged: onPreferVttSubtitlesChanged,
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Use .vtt subtitles when available')),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (sourceMode == SummaryModelSourceMode.managedDownload &&
                  !isDownloading)
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: onDownloadPressed,
                  child: const Text('Download Model'),
                ),
              if (isDownloading)
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: onStopDownloadPressed,
                  child: const Text('Stop Download'),
                ),
              PushButton(
                controlSize: ControlSize.large,
                onPressed:
                    sourceMode == SummaryModelSourceMode.localFile &&
                        !isDownloading
                    ? onBrowsePressed
                    : null,
                child: const Text('Browse Model'),
              ),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: modelPath.isNotEmpty ? onRevealPressed : null,
                child: const Text('Reveal Model'),
              ),
              PushButton(
                controlSize: ControlSize.large,
                onPressed: isDownloading ? null : onRefreshCatalogPressed,
                child: Text(
                  catalogState.isRefreshing
                      ? 'Refreshing...'
                      : 'Refresh Catalog',
                ),
              ),
              if (sourceMode == SummaryModelSourceMode.managedDownload)
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: canDeleteManagedModel && !isDownloading
                      ? onDeletePressed
                      : null,
                  child: const Text('Delete Model'),
                ),
              if (sourceMode == SummaryModelSourceMode.localFile)
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: modelPath.isNotEmpty && !isDownloading
                      ? onClearSelectionPressed
                      : null,
                  child: const Text('Clear Selection'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (downloadState.phase == ModelDownloadPhase.downloading) ...[
            SizedBox(
              height: 22,
              child: LinearProgressIndicator(
                value: downloadState.progressFraction,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ProgressMetric(
                  label: 'Downloaded',
                  value:
                      '${downloadState.formattedReceivedBytes} / ${downloadState.formattedTotalBytes}',
                ),
                _ProgressMetric(
                  label: 'Progress',
                  value: downloadState.percentLabel ?? 'Unknown',
                ),
                _ProgressMetric(
                  label: 'Speed',
                  value: downloadState.formattedBytesPerSecond,
                ),
                _ProgressMetric(
                  label: 'ETA',
                  value: downloadState.formattedEta,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (downloadState.phase == ModelDownloadPhase.failed &&
              downloadState.error != null) ...[
            Text(
              downloadState.error!,
              style: const TextStyle(color: MacosColors.appleRed),
            ),
            const SizedBox(height: 8),
          ],
          if (downloadState.phase == ModelDownloadPhase.completed) ...[
            const Text('Model download completed.'),
            const SizedBox(height: 8),
          ],
          if (statusMessage != null && statusMessage!.isNotEmpty) ...[
            Text(statusMessage!),
            const SizedBox(height: 8),
          ],
          if (catalogState.refreshError != null) ...[
            Text(
              catalogState.refreshError!,
              style: const TextStyle(color: MacosColors.appleRed),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          Text(
            'Downloaded Models',
            style: MacosTheme.of(context).typography.headline,
          ),
          const SizedBox(height: 10),
          if (downloadedEntries.isEmpty)
            const SizedBox(
              width: 360,
              child: Text('No managed models downloaded yet.'),
            )
          else
            SizedBox(
              width: 360,
              child: Column(
                children: downloadedEntries
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ManagedModelAvailabilityRow(
                          modelId: entry.id,
                          isSelected:
                              sourceMode ==
                                  SummaryModelSourceMode.managedDownload &&
                              selectedModelId == entry.id,
                          onSelectPressed:
                              sourceMode ==
                                          SummaryModelSourceMode
                                              .managedDownload &&
                                      selectedModelId == entry.id ||
                                  isDownloading
                              ? null
                              : () => onSelectedModelChanged(entry.id),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          Text(
            'Managed Download',
            style: MacosTheme.of(context).typography.headline,
          ),
          const SizedBox(height: 10),
          const Text(
            'Managed mode downloads the selected Whisper model into the app support directory.',
          ),
          const SizedBox(height: 20),
          Text('Local Mode', style: MacosTheme.of(context).typography.headline),
          const SizedBox(height: 10),
          const Text(
            'Local mode lets you point Media Manager at a Whisper model file already present on disk.',
          ),
        ],
      ),
    );
  }
}

class _MacosPreferenceCheckbox extends StatelessWidget {
  const _MacosPreferenceCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Semantics(
      checked: value,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: Container(
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
              ? const MacosIcon(
                  CupertinoIcons.checkmark,
                  size: 12,
                  color: MacosColors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _LocalSelectedModelPathField extends StatelessWidget {
  const _LocalSelectedModelPathField({required this.modelPath});

  final String modelPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Container(
        key: const ValueKey('local-selected-model-path'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: MacosColors.systemGrayColor.withValues(alpha: 0.08),
          border: Border.all(color: MacosTheme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          modelPath.isEmpty ? 'No local model selected' : modelPath,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _KeyboardNavigableModelPicker extends StatefulWidget {
  const _KeyboardNavigableModelPicker({
    Key? key,
    required this.value,
    required this.enabled,
    required this.entries,
    required this.onChanged,
  }) : pickerKey = key;

  final Key? pickerKey;
  final String? value;
  final bool enabled;
  final List<WhisperModelCatalogEntry> entries;
  final ValueChanged<String?> onChanged;

  @override
  State<_KeyboardNavigableModelPicker> createState() =>
      _KeyboardNavigableModelPickerState();
}

class _KeyboardNavigableModelPickerState
    extends State<_KeyboardNavigableModelPicker> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'available-models-picker');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled ||
        widget.entries.length < 2 ||
        event is! KeyDownEvent ||
        widget.value == null) {
      return KeyEventResult.ignored;
    }

    final currentIndex = widget.entries.indexWhere(
      (entry) => entry.id == widget.value,
    );
    if (currentIndex < 0) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final delta = switch (key) {
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.arrowLeft => -1,
      _ => 0,
    };

    if (delta == 0) {
      return KeyEventResult.ignored;
    }

    final nextIndex =
        (currentIndex + delta + widget.entries.length) % widget.entries.length;
    widget.onChanged(widget.entries[nextIndex].id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: MacosPopupButton<String>(
        key: widget.pickerKey,
        focusNode: _focusNode,
        autofocus: widget.enabled,
        value: widget.value,
        onChanged: widget.enabled ? widget.onChanged : null,
        items: widget.entries
            .map(
              (entry) => MacosPopupMenuItem(
                value: entry.id,
                child: Text('${entry.displayName} (${entry.diskSizeLabel})'),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ManagedModelAvailabilityRow extends StatelessWidget {
  const _ManagedModelAvailabilityRow({
    required this.modelId,
    required this.isSelected,
    required this.onSelectPressed,
  });

  final String modelId;
  final bool isSelected;
  final VoidCallback? onSelectPressed;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: Text(modelId)),
          _SelectionPillButton(
            label: isSelected ? 'Selected' : 'Select',
            isSelected: isSelected,
            onPressed: onSelectPressed,
          ),
        ],
      ),
    );
  }
}

class _SelectionPillButton extends StatelessWidget {
  const _SelectionPillButton({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final foregroundColor = isSelected
        ? MacosColors.systemBlueColor
        : (isEnabled
              ? MacosTheme.of(context).typography.body.color ??
                    MacosColors.labelColor
              : MacosColors.systemGrayColor);
    final backgroundColor = isSelected
        ? MacosColors.systemBlueColor.withValues(alpha: 0.12)
        : MacosColors.systemGrayColor.withValues(
            alpha: isEnabled ? 0.12 : 0.08,
          );

    return Semantics(
      button: true,
      enabled: isEnabled,
      child: MouseRegion(
        cursor: isEnabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: MacosTheme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: MacosTheme.of(context).typography.caption1),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
