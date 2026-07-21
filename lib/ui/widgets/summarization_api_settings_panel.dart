import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../movie_manager_visual_system.dart';

typedef SummarizationApiSaveCallback =
    FutureOr<void> Function({required String apiUrl, required String apiKey});

class SummarizationApiSettingsPanel extends StatefulWidget {
  const SummarizationApiSettingsPanel({
    super.key,
    required this.apiUrl,
    required this.apiKey,
    required this.statusMessage,
    required this.onSave,
  });

  final String apiUrl;
  final String apiKey;
  final String? statusMessage;
  final SummarizationApiSaveCallback onSave;

  @override
  State<SummarizationApiSettingsPanel> createState() =>
      _SummarizationApiSettingsPanelState();
}

class _SummarizationApiSettingsPanelState
    extends State<SummarizationApiSettingsPanel> {
  late final TextEditingController _apiUrlController;
  late final TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: widget.apiUrl);
    _apiKeyController = TextEditingController(text: widget.apiKey);
  }

  @override
  void didUpdateWidget(SummarizationApiSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiUrl != widget.apiUrl &&
        _apiUrlController.text != widget.apiUrl) {
      _apiUrlController.text = widget.apiUrl;
    }
    if (oldWidget.apiKey != widget.apiKey &&
        _apiKeyController.text != widget.apiKey) {
      _apiKeyController.text = widget.apiKey;
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OpenAI-Compatible API', style: theme.typography.headline),
            const SizedBox(height: 16),
            _SettingsField(
              label: 'API URL',
              child: MovieManagerLabeledField(
                label: 'API URL',
                controller: _apiUrlController,
                hasVisibleLabel: true,
                builder: (focusNode) => MacosTextField(
                  key: const ValueKey('summarization-api-url-field'),
                  controller: _apiUrlController,
                  focusNode: focusNode,
                  placeholder: 'https://api.openai.com/v1/chat/completions',
                ),
              ),
            ),
            const SizedBox(height: 14),
            _SettingsField(
              label: 'API Key',
              trailingLabel: 'Optional',
              child: MovieManagerLabeledField(
                label: 'API Key',
                controller: _apiKeyController,
                hasVisibleLabel: true,
                obscured: true,
                builder: (focusNode) => MacosTextField(
                  key: const ValueKey('summarization-api-key-field'),
                  controller: _apiKeyController,
                  focusNode: focusNode,
                  placeholder: 'sk-...',
                  obscureText: true,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                PushButton(
                  controlSize: ControlSize.regular,
                  onPressed: () => widget.onSave(
                    apiUrl: _apiUrlController.text.trim(),
                    apiKey: _apiKeyController.text.trim(),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MacosIcon(CupertinoIcons.checkmark, size: 16),
                      SizedBox(width: 6),
                      Text('Save'),
                    ],
                  ),
                ),
                if (widget.statusMessage != null &&
                    widget.statusMessage!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      widget.statusMessage!,
                      style: theme.typography.caption1.copyWith(
                        color: MacosColors.systemGreenColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.child,
    this.trailingLabel,
  });

  final String label;
  final String? trailingLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.typography.subheadline),
            if (trailingLabel != null) ...[
              const SizedBox(width: 8),
              Text(trailingLabel!, style: theme.typography.caption1),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
