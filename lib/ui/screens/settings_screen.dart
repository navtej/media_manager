import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import '../../logic/maintenance_controller.dart';
import 'package:flutter/services.dart';
import '../../data/providers.dart';

import '../../logic/settings_provider.dart';
import '../../logic/status_message_provider.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/natural_language_service.dart';
import '../../logic/stats_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _intervalController;
  late TextEditingController _batchSizeController;
  late TextEditingController _paginationSizeController;
  
  @override
  void initState() {
    super.initState();
    _intervalController = TextEditingController();
    _batchSizeController = TextEditingController();
    _paginationSizeController = TextEditingController();
  }
  
  @override
  void dispose() {
    _intervalController.dispose();
    _batchSizeController.dispose();
    _paginationSizeController.dispose();
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
      if (_paginationSizeController.text.isEmpty) {
        _paginationSizeController.text = data['paginationSize'].toString();
      }
    });

    return MacosScaffold(
      backgroundColor: MacosTheme.of(context).canvasColor,
      toolBar: ToolBar(
        decoration: BoxDecoration(
          color: MacosTheme.of(context).canvasColor,
        ),
        centerTitle: false,
        title: const Text('Back'),
        leading: Transform.translate(
          offset: const Offset(-10, 0),
          child: MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      children: [
        ContentArea(
          builder: (context, controller) {
            if (settingsAsync.isLoading) {
               return const Center(child: ProgressCircle());
            }
            
            return Container(
              color: MacosTheme.of(context).canvasColor,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Library Folders', style: MacosTheme.of(context).typography.headline),
                    const SizedBox(height: 10),
                    Expanded(child: _FolderList()),
                    const SizedBox(height: 12),
                    const _OpenDataFolderWidget(),
                    
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),
                    
                    Text('Appearance', style: MacosTheme.of(context).typography.headline),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const SizedBox(width: 200, child: Text('Theme')),
                        MacosPopupButton<String>(
                          value: settingsAsync.value?['themeMode']?.toString() ?? 'system',
                          onChanged: (String? mode) {
                            if (mode != null) {
                              ref.read(settingsProvider.notifier).updateTheme(mode);
                            }
                          },
                          items: const [
                            MacosPopupMenuItem(value: 'system', child: Text('System')),
                            MacosPopupMenuItem(value: 'light', child: Text('Light')),
                            MacosPopupMenuItem(value: 'dark', child: Text('Dark')),
                          ],
                        ),
                      ],
                    ),

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
                            final pagination = int.tryParse(_paginationSizeController.text) ?? 50;
                            
                            ref.read(settingsProvider.notifier).updateSettings(interval, batch, pagination);
                            
                            // Show status message and return
                            ref.read(statusMessageProvider.notifier).set('Preferences saved');
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildPreferenceRow(context, 'Scan Interval (min)', _intervalController)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildPreferenceRow(context, 'DB Batch Size', _batchSizeController)),
                        const SizedBox(width: 20),
                        Expanded(child: _buildPreferenceRow(context, 'Pagination Size', _paginationSizeController)),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPreferenceRow(BuildContext context, String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: MacosTheme.of(context).typography.subheadline),
        const SizedBox(height: 4),
        MacosTextField(
          controller: controller,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }
}


class _OpenDataFolderWidget extends ConsumerWidget {
  const _OpenDataFolderWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sizeAsync = ref.watch(dataFolderSizeProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Row(
        children: [
          Text(
            'Open Data Folder in Finder',
            style: MacosTheme.of(context).typography.body.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 8),
          MacosIconButton(
            icon: const MacosIcon(
              CupertinoIcons.folder,
              size: 18,
            ),
            onPressed: () async {
              final directory = await getApplicationSupportDirectory();
              await NaturalLanguageService().openFolder(directory.path);
            },
          ),
          const SizedBox(width: 8),
          sizeAsync.when(
            data: (size) => Text(
              LibraryStats.formatSize(size),
              style: MacosTheme.of(context).typography.body.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            loading: () => const SizedBox(
              width: 12,
              height: 12,
              child: ProgressCircle(),
            ),
            error: (_, __) => const SizedBox(),
          ),
        ],
      ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.folder, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(folder.path, style: const TextStyle(fontSize: 13))),
                    MacosIconButton(
                      icon: const Icon(CupertinoIcons.trash, color: MacosColors.appleRed, size: 16),
                      onPressed: () {
                         ref.read(maintenanceControllerProvider.notifier).removeFolder(folder.id);
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
