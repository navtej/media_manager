import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../logic/settings_provider.dart';
import '../movie_manager_visual_system.dart';
import 'macos_preference_checkbox.dart';

const emptyFolderCleanupValidationMessage =
    'Enter a whole number from 1 to 90.';

class EmptyFolderCleanupControl extends ConsumerStatefulWidget {
  const EmptyFolderCleanupControl({super.key});

  @override
  ConsumerState<EmptyFolderCleanupControl> createState() =>
      _EmptyFolderCleanupControlState();
}

class _EmptyFolderCleanupControlState
    extends ConsumerState<EmptyFolderCleanupControl> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _errorMessage;
  bool _isCommitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      unawaited(_commitInterval());
    }
  }

  Future<void> _commitInterval() async {
    if (_isCommitting) {
      return;
    }
    final days = int.tryParse(_controller.text);
    if (!EmptyFolderCleanupConfiguration.isValidIntervalDays(days)) {
      if (mounted) {
        setState(() => _errorMessage = emptyFolderCleanupValidationMessage);
      }
      return;
    }
    final current = ref
        .read(emptyFolderCleanupConfigurationProvider)
        .asData
        ?.value;
    if (current == null || current.intervalDays == days) {
      if (mounted) {
        setState(() => _errorMessage = null);
      }
      return;
    }

    _isCommitting = true;
    try {
      await ref
          .read(settingsProvider.notifier)
          .updateEmptyFolderCleanup(
            enabled: current.enabled,
            intervalDays: days!,
          );
      if (mounted) {
        setState(() => _errorMessage = null);
      }
    } finally {
      _isCommitting = false;
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    final current = ref
        .read(emptyFolderCleanupConfigurationProvider)
        .asData
        ?.value;
    if (current == null) {
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .updateEmptyFolderCleanup(
          enabled: enabled,
          intervalDays: current.intervalDays,
        );
  }

  @override
  Widget build(BuildContext context) {
    final configuration = ref.watch(emptyFolderCleanupConfigurationProvider);
    configuration.whenData((data) {
      if (_controller.text.isEmpty && !_focusNode.hasFocus) {
        _controller.text = data.intervalDays.toString();
      }
    });
    final value = configuration.asData?.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 150, child: Text('Remove empty folders')),
            MacosPreferenceCheckbox(
              key: const ValueKey('empty-folder-cleanup-checkbox'),
              value: value?.enabled ?? true,
              semanticLabel: 'Remove empty folders automatically',
              onChanged: (enabled) {
                if (value != null) {
                  unawaited(_setEnabled(enabled));
                }
              },
            ),
            const SizedBox(width: 16),
            const Text('Every'),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: MovieManagerLabeledField(
                label: 'Empty folder cleanup interval in days',
                controller: _controller,
                focusNode: _focusNode,
                enabled: value != null && !_isCommitting,
                builder: (focusNode) => MacosTextField(
                  key: const ValueKey(
                    'empty-folder-cleanup-interval-days-field',
                  ),
                  controller: _controller,
                  focusNode: focusNode,
                  enabled: value != null && !_isCommitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_commitInterval()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('days'),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 150),
            child: Text(
              _errorMessage!,
              key: const ValueKey('empty-folder-cleanup-validation-error'),
              style: const TextStyle(
                color: CupertinoColors.systemRed,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
