import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/settings_provider.dart';
import 'macos_preference_checkbox.dart';

class ShowOfflineMediaControl extends ConsumerWidget {
  const ShowOfflineMediaControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return settings.when(
      data: (values) {
        final showOfflineMedia = values['showOfflineMedia'] as bool? ?? true;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Show Offline Media'),
            const SizedBox(width: 6),
            MacosPreferenceCheckbox(
              key: const ValueKey('show-offline-media-checkbox'),
              value: showOfflineMedia,
              semanticLabel: 'Show Offline Media',
              onChanged: (value) => ref
                  .read(settingsProvider.notifier)
                  .updateShowOfflineMedia(value),
            ),
          ],
        );
      },
      loading: SizedBox.shrink,
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
