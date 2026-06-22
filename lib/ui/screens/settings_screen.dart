import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:flutter/services.dart';
import '../../data/providers.dart';

import '../../logic/model_download_controller.dart';
import '../../logic/maintenance_controller.dart';
import '../../logic/folder_storage_status.dart';
import '../../logic/settings_provider.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_summary_models.dart';
import '../../logic/whisper_model_catalog.dart';
import '../../logic/whisper_model_catalog_controller.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/natural_language_service.dart';
import '../../services/folder_access_service.dart';
import '../../services/private_library_auth_service.dart';
import '../../services/whisper_runtime_service.dart';
import '../../logic/stats_provider.dart';
import '../widgets/summary_model_settings_panel.dart';
import '../widgets/summarization_api_settings_panel.dart';

enum _SettingsTab { general, transcribe, summarization }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _intervalController;
  late TextEditingController _batchSizeController;
  late TextEditingController _paginationSizeController;
  _SettingsTab _selectedTab = _SettingsTab.general;
  String? _summaryActionMessage;
  String? _summarizationActionMessage;

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

  Future<void> _pickSummaryModel() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    await ref
        .read(settingsProvider.notifier)
        .updateSummaryModelSource(SummaryModelSourceMode.localFile);
    await ref.read(settingsProvider.notifier).updateSummaryModelPath(path);
    ref.invalidate(summaryModelValidationProvider);

    if (!mounted) {
      return;
    }

    setState(() {
      _summaryActionMessage = 'Using local model file.';
    });
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
        decoration: BoxDecoration(color: MacosTheme.of(context).canvasColor),
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
                    CupertinoSlidingSegmentedControl<_SettingsTab>(
                      groupValue: _selectedTab,
                      children: const {
                        _SettingsTab.general: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text('General'),
                        ),
                        _SettingsTab.transcribe: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text('Transcribe'),
                        ),
                        _SettingsTab.summarization: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text('Summarization'),
                        ),
                      },
                      onValueChanged: (_SettingsTab? value) {
                        if (value != null) {
                          setState(() {
                            _selectedTab = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: switch (_selectedTab) {
                        _SettingsTab.general => _buildGeneralSettings(
                          context,
                          settingsAsync,
                        ),
                        _SettingsTab.transcribe => _buildTranscribeSettings(
                          context,
                          settingsAsync,
                        ),
                        _SettingsTab.summarization =>
                          _buildSummarizationSettings(settingsAsync),
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPreferenceRow(
    BuildContext context,
    String label,
    TextEditingController controller,
  ) {
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

  Widget _buildCustomCheckbox(
    BuildContext context,
    bool isChecked,
    ValueChanged<bool> onChanged,
  ) {
    final theme = MacosTheme.of(context);
    return GestureDetector(
      onTap: () => onChanged(!isChecked),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: isChecked ? theme.primaryColor : Colors.transparent,
          border: Border.all(
            color: isChecked
                ? theme.primaryColor
                : MacosColors.systemGrayColor.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: isChecked
            ? const Icon(
                CupertinoIcons.checkmark,
                size: 12,
                color: MacosColors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildGeneralSettings(
    BuildContext context,
    AsyncValue<Map<String, dynamic>> settingsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Library Folders',
          style: MacosTheme.of(context).typography.headline,
        ),
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
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(width: 200, child: Text('Show Offline Media')),
            _buildCustomCheckbox(
              context,
              settingsAsync.value?['showOfflineMedia'] ?? true,
              (bool value) {
                ref
                    .read(settingsProvider.notifier)
                    .updateShowOfflineMedia(value);
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              'Advanced Preferences',
              style: MacosTheme.of(context).typography.headline,
            ),
            const SizedBox(width: 12),
            MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.floppy_disk),
              onPressed: () {
                final interval = int.tryParse(_intervalController.text) ?? 5;
                final batch = int.tryParse(_batchSizeController.text) ?? 4;
                final pagination =
                    int.tryParse(_paginationSizeController.text) ?? 50;

                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(interval, batch, pagination);

                ref
                    .read(statusMessageProvider.notifier)
                    .set('Preferences saved');
                Navigator.pop(context);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildPreferenceRow(
                context,
                'Scan Interval (min)',
                _intervalController,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildPreferenceRow(
                context,
                'DB Batch Size',
                _batchSizeController,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildPreferenceRow(
                context,
                'Pagination Size',
                _paginationSizeController,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTranscribeSettings(
    BuildContext context,
    AsyncValue<Map<String, dynamic>> settingsAsync,
  ) {
    final sourceMode = SummaryModelSourceMode.fromValue(
      settingsAsync.value?['summaryModelSource']?.toString() ??
          SummaryModelSourceMode.managedDownload.value,
    );
    final modelPath =
        settingsAsync.value?['summaryModelPath']?.toString() ?? '';
    final selectedModelId = settingsAsync.value?['summarySelectedModelId']
        ?.toString();
    final managedDirectoryPath =
        settingsAsync.value?['summaryManagedModelDirectoryPath']?.toString() ??
        '';
    final downloadedManagedModels =
        (settingsAsync.value?['summaryDownloadedManagedModels'] as Map?)
            ?.map<String, String>(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ) ??
        <String, String>{};
    final preferVttSubtitles =
        settingsAsync.value?['summaryPreferVttSubtitles'] as bool? ?? true;
    final validationAsync = ref.watch(summaryModelValidationProvider);
    final runtimeStatusAsync = ref.watch(whisperRuntimeStatusProvider);
    final catalogState = ref.watch(whisperModelCatalogControllerProvider);
    final downloadState = ref.watch(modelDownloadControllerProvider);

    return validationAsync.when(
      data: (validation) {
        final runtimeStatus = runtimeStatusAsync.when(
          data: (status) => status.status,
          loading: () => 'Checking bundled runtime...',
          error: (_, _) => 'Bundled runtime missing',
        );

        return SummaryModelSettingsPanel(
          sourceMode: sourceMode,
          modelPath: modelPath,
          selectedModelId: selectedModelId,
          downloadedManagedModels: downloadedManagedModels,
          validation: validation,
          runtimeStatus: runtimeStatus,
          catalogState: catalogState,
          downloadState: downloadState,
          preferVttSubtitles: preferVttSubtitles,
          canDeleteManagedModel:
              sourceMode == SummaryModelSourceMode.managedDownload &&
              isManagedModelPath(
                modelPath: modelPath,
                managedDirectoryPath: managedDirectoryPath,
              ),
          statusMessage: _summaryActionMessage,
          onSourceModeChanged: (mode) async {
            await ref
                .read(settingsProvider.notifier)
                .updateSummaryModelSource(mode);
            setState(() {
              _summaryActionMessage = null;
            });
          },
          onSelectedModelChanged: (modelId) async {
            await ref
                .read(settingsProvider.notifier)
                .selectManagedSummaryModel(modelId);
            ref.invalidate(summaryModelValidationProvider);
            setState(() {
              _summaryActionMessage =
                  modelId != null &&
                      downloadedManagedModels.containsKey(modelId)
                  ? 'Switched summarization model.'
                  : null;
            });
          },
          onPreferVttSubtitlesChanged: (value) async {
            await ref
                .read(settingsProvider.notifier)
                .updateSummaryPreferVttSubtitles(value);
          },
          onDownloadPressed: () async {
            final effectiveSelectedModelId =
                selectedModelId ?? catalogState.entries.firstOrNull?.id;
            if (effectiveSelectedModelId == null) {
              setState(() {
                _summaryActionMessage = 'No model is available to download.';
              });
              return;
            }

            final entry = catalogState.entries.firstWhere(
              (item) => item.id == effectiveSelectedModelId,
              orElse: () => catalogState.entries.first,
            );
            setState(() {
              _summaryActionMessage = null;
            });
            await ref
                .read(modelDownloadControllerProvider.notifier)
                .downloadManagedModel(entry);
          },
          onStopDownloadPressed: () async {
            await ref
                .read(modelDownloadControllerProvider.notifier)
                .cancelDownload();
            setState(() {
              _summaryActionMessage = 'Download stopped.';
            });
          },
          onDeletePressed: () async {
            await ref
                .read(modelDownloadControllerProvider.notifier)
                .deleteManagedModel(
                  modelId: selectedModelId,
                  modelPath: modelPath,
                  managedDirectoryPath: managedDirectoryPath,
                );
            setState(() {
              _summaryActionMessage = 'Managed model removed.';
            });
          },
          onBrowsePressed: _pickSummaryModel,
          onRevealPressed: () =>
              NaturalLanguageService().openInFinder(modelPath),
          onRefreshCatalogPressed: () async {
            await ref
                .read(whisperModelCatalogControllerProvider.notifier)
                .refresh();
          },
          onClearSelectionPressed: () async {
            await ref
                .read(modelDownloadControllerProvider.notifier)
                .clearLocalSelection();
            setState(() {
              _summaryActionMessage = 'Local model selection cleared.';
            });
          },
        );
      },
      loading: () => const Center(child: ProgressCircle()),
      error: (error, _) => Center(child: Text(error.toString())),
    );
  }

  Widget _buildSummarizationSettings(
    AsyncValue<Map<String, dynamic>> settingsAsync,
  ) {
    return SummarizationApiSettingsPanel(
      apiUrl: settingsAsync.value?['summaryApiUrl']?.toString() ?? '',
      apiKey: settingsAsync.value?['summaryApiKey']?.toString() ?? '',
      statusMessage: _summarizationActionMessage,
      onSave: ({required apiUrl, required apiKey}) async {
        final notifier = ref.read(settingsProvider.notifier);
        await notifier.updateSummaryApiUrl(apiUrl);
        await notifier.updateSummaryApiKey(apiKey);
        setState(() {
          _summarizationActionMessage = 'Summarization settings saved.';
        });
      },
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
            style: MacosTheme.of(
              context,
            ).typography.body.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          MacosIconButton(
            icon: const MacosIcon(CupertinoIcons.folder, size: 18),
            onPressed: () async {
              final directory = await getApplicationSupportDirectory();
              await NaturalLanguageService().openFolder(directory.path);
            },
          ),
          const SizedBox(width: 8),
          sizeAsync.when(
            data: (size) => Text(
              LibraryStats.formatSize(size),
              style: MacosTheme.of(
                context,
              ).typography.body.copyWith(fontWeight: FontWeight.bold),
            ),
            loading: () =>
                const SizedBox(width: 12, height: 12, child: ProgressCircle()),
            error: (error, stackTrace) => const SizedBox(),
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
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final folder = folders[index];
              final storageStatus = FolderStorageStatus.fromFolder(
                path: folder.path,
                securityScopedBookmark: folder.securityScopedBookmark,
              );
              final statusLabel = storageStatus.statusLabel;
              final accessTooltip = _folderAccessTooltip(storageStatus);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.folder, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            folder.path,
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (statusLabel != null)
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: storageStatus.needsRepair
                                    ? MacosColors.systemOrangeColor
                                    : MacosColors.systemBlueColor,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    MacosTooltip(
                      message: folder.isPrivate
                          ? 'Private library. Click to make videos visible by default.'
                          : 'Public library. Click to require authentication before videos appear.',
                      child: MacosIconButton(
                        icon: Icon(
                          folder.isPrivate
                              ? CupertinoIcons.lock
                              : CupertinoIcons.lock_open,
                          color: folder.isPrivate
                              ? MacosColors.systemPurpleColor
                              : MacosColors.systemGrayColor,
                          size: 16,
                        ),
                        onPressed: () async {
                          final nextIsPrivate = !folder.isPrivate;
                          if (!nextIsPrivate) {
                            final authenticated = await ref
                                .read(privateLibraryAuthServiceProvider)
                                .authenticate();
                            if (!authenticated) {
                              ref
                                  .read(statusMessageProvider.notifier)
                                  .set(
                                    'Authentication cancelled. Library remains private.',
                                  );
                              return;
                            }
                          }

                          await ref
                              .read(foldersDaoProvider)
                              .updateFolderPrivacy(folder.id, nextIsPrivate);
                          ref
                              .read(statusMessageProvider.notifier)
                              .set(
                                nextIsPrivate
                                    ? 'Library is now private.'
                                    : 'Library is now visible by default.',
                              );
                        },
                      ),
                    ),
                    MacosTooltip(
                      message: accessTooltip,
                      child: MacosIconButton(
                        icon: Icon(
                          CupertinoIcons.exclamationmark_shield,
                          color: storageStatus.needsRepair
                              ? MacosColors.systemOrangeColor
                              : storageStatus.isRemovableStorage
                              ? MacosColors.systemBlueColor
                              : MacosColors.systemGrayColor,
                          size: 16,
                        ),
                        onPressed: () async {
                          final selectedDirectory = await FilePicker.platform
                              .getDirectoryPath();
                          if (selectedDirectory == null) {
                            return;
                          }
                          if (selectedDirectory != folder.path) {
                            ref
                                .read(statusMessageProvider.notifier)
                                .set(
                                  'Select the same folder to repair access.',
                                );
                            return;
                          }

                          final bookmark = await ref
                              .read(folderAccessServiceProvider)
                              .createBookmark(selectedDirectory);
                          if (bookmark == null || bookmark.isEmpty) {
                            ref
                                .read(statusMessageProvider.notifier)
                                .set('Could not repair folder access.');
                            return;
                          }

                          await ref
                              .read(foldersDaoProvider)
                              .updateFolderBookmark(folder.id, bookmark);
                          ref
                              .read(statusMessageProvider.notifier)
                              .set('Folder access repaired.');
                        },
                      ),
                    ),
                    MacosTooltip(
                      message:
                          'Remove this folder from the library. Files stay on disk.',
                      child: MacosIconButton(
                        icon: const Icon(
                          CupertinoIcons.trash,
                          color: MacosColors.appleRed,
                          size: 16,
                        ),
                        onPressed: () {
                          ref
                              .read(maintenanceControllerProvider.notifier)
                              .removeFolder(folder.id);
                        },
                      ),
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

String _folderAccessTooltip(FolderStorageStatus status) {
  if (status.needsRepair) {
    return 'Access repair required. Click to reselect this folder and restore access.';
  }
  if (status.isRemovableStorage) {
    return 'Removable storage. macOS keeps saved access for this folder; click to refresh or repair it.';
  }
  return 'Folder access. Click to refresh access permissions.';
}
