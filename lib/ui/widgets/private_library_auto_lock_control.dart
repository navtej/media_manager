import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../logic/settings_provider.dart';

const privateLibraryAutoLockValidationMessage =
    'Enter a whole number from 1 to 120.';

class PrivateLibraryAutoLockControl extends ConsumerStatefulWidget {
  const PrivateLibraryAutoLockControl({super.key});

  @override
  ConsumerState<PrivateLibraryAutoLockControl> createState() =>
      _PrivateLibraryAutoLockControlState();
}

class _PrivateLibraryAutoLockControlState
    extends ConsumerState<PrivateLibraryAutoLockControl> {
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
      unawaited(_commit());
    }
  }

  Future<void> _commit() async {
    if (_isCommitting) {
      return;
    }

    final minutes = int.tryParse(_controller.text);
    if (!PrivateLibraryAccessConfiguration.isValidAutoLockMinutes(minutes)) {
      if (mounted) {
        setState(() {
          _errorMessage = privateLibraryAutoLockValidationMessage;
        });
      }
      return;
    }

    final currentMinutes = ref
        .read(privateLibraryAccessConfigurationProvider)
        .asData
        ?.value
        .autoLockMinutes;
    if (minutes == currentMinutes) {
      if (mounted && _errorMessage != null) {
        setState(() {
          _errorMessage = null;
        });
      }
      return;
    }

    _isCommitting = true;
    try {
      await ref
          .read(settingsProvider.notifier)
          .updatePrivateLibraryAutoLockMinutes(minutes!);
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    } finally {
      _isCommitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuration = ref.watch(privateLibraryAccessConfigurationProvider);
    configuration.whenData((data) {
      if (_controller.text.isEmpty && !_focusNode.hasFocus) {
        _controller.text = data.autoLockMinutes.toString();
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 220,
              child: Text('Auto-lock private libraries after'),
            ),
            SizedBox(
              width: 72,
              child: MacosTextField(
                key: const ValueKey('private-library-auto-lock-minutes-field'),
                controller: _controller,
                focusNode: _focusNode,
                enabled: configuration.hasValue && !_isCommitting,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => unawaited(_commit()),
              ),
            ),
            const SizedBox(width: 8),
            const Text('minutes'),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 220),
            child: Text(
              _errorMessage!,
              key: const ValueKey('private-library-auto-lock-validation-error'),
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
