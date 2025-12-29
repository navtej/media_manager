import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../logic/library_controller.dart';
import 'package:flutter/services.dart';
import '../../data/providers.dart';

import '../../logic/settings_provider.dart';
import '../../logic/status_message_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _intervalController;
  late TextEditingController _batchSizeController;
  
  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController();
    _batchSizeController = TextEditingController();
  }
  
  @override
  void dispose() {
    _intervalController.dispose();
    _batchSizeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    
    // Update controllers when data is loaded
    settingsAsync.whenData((data) {
      if (_intervalController.text.isEmpty) {
        _intervalController.text = data['scanInterval'].toString();
      }
      if (_batchSizeController.text.isEmpty) {
        _batchSizeController.text = data['batchSize'].toString();
      }
    });

    return MacosWindow(
      child: MacosScaffold(
        toolBar: ToolBar(
          title: const Text('Settings'),
          leading: MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        children: [
          ContentArea(
            builder: (context, controller) {
              if (settingsAsync.isLoading) {
                 return const Center(child: ProgressCircle());
              }
              
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Library Folders', style: MacosTheme.of(context).typography.headline),
                    const SizedBox(height: 10),
                    Expanded(child: _FolderList()),
                    
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),
                    
                    Row(
                      children: [
                        Text('Advanced Preferences', style: MacosTheme.of(context).typography.headline),
                        const SizedBox(width: 12),
                        MacosIconButton(
                          icon: const MacosIcon(CupertinoIcons.floppy_disk),
                          onPressed: () {
                            final interval = int.tryParse(_intervalController.text) ?? 5;
                            final batch = int.tryParse(_batchSizeController.text) ?? 4;
                            ref.read(settingsProvider.notifier).updateSettings(interval, batch);
                            
                            // Show status message and return
                            ref.read(statusMessageProvider.notifier).set('Preferences saved');
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildPreferenceRow(context, 'Scanning Interval (minutes)', _intervalController),
                    const SizedBox(height: 10),
                    _buildPreferenceRow(context, 'Batch Processing Size', _batchSizeController),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreferenceRow(BuildContext context, String label, TextEditingController controller) {
    return Row(
      children: [
        SizedBox(width: 200, child: Text(label)),
        SizedBox(
          width: 100,
          child: MacosTextField(
            controller: controller,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
      ],
    );
  }
}

class _FolderList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersDaoProvider).watchAllFolders();

    return StreamBuilder(
      stream: foldersAsync,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: ProgressCircle());
        
        final folders = snapshot.data ?? [];
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: MacosTheme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            itemCount: folders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final folder = folders[index];
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.folder),
                    const SizedBox(width: 12),
                    Expanded(child: Text(folder.path)),
                    MacosIconButton(
                      icon: const Icon(CupertinoIcons.trash, color: MacosColors.appleRed),
                      onPressed: () {
                         ref.read(libraryControllerProvider.notifier).removeFolder(folder.id);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
