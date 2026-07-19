import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:flutter/services.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

import '../../logic/model_download_controller.dart';
import '../../logic/maintenance_controller.dart';
import '../../logic/folder_storage_status.dart';
import '../../logic/library_controller.dart';
import '../../logic/library_name.dart';
import '../../logic/managed_library_service.dart';
import '../../logic/settings_provider.dart';
import '../../logic/status_message_provider.dart';
import '../../logic/video_summary_models.dart';
import '../../logic/whisper_model_catalog.dart';
import '../../logic/whisper_model_catalog_controller.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/natural_language_service.dart';
import '../../services/whisper_runtime_service.dart';
import '../../logic/stats_provider.dart';
import '../library_result_messages.dart';
import '../widgets/summary_model_settings_panel.dart';
import '../widgets/summarization_api_settings_panel.dart';
import '../widgets/private_library_auto_lock_control.dart';

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
  String? _libraryActionMessage;

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

    await ref.read(settingsProvider.notifier).setLocalSummaryModelPath(path);
    ref.invalidate(summaryModelValidationProvider);

    if (!mounted) {
      return;
    }

    setState(() {
      _summaryActionMessage = 'Using local model file.';
    });
  }

  Future<void> _pickLibraryFolder() async {
    final selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null || selectedDirectory.isEmpty) {
      return;
    }

    final result = await ref
        .read(libraryControllerProvider.notifier)
        .addFolder(selectedDirectory);
    if (!mounted) {
      return;
    }
    setState(() {
      _libraryActionMessage = libraryAddFlowResultMessage(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    // Update controllers when data is loaded
    settingsAsync.whenData((data) {
      if (_intervalController.text.isEmpty) {
        _intervalController.text = data
            .librarySynchronization
            .scanIntervalMinutes
            .toString();
      }
      if (_batchSizeController.text.isEmpty) {
        _batchSizeController.text = data.librarySynchronization.batchSize
            .toString();
      }
      if (_paginationSizeController.text.isEmpty) {
        _paginationSizeController.text = data.catalogBrowsing.paginationSize
            .toString();
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

  Widget _buildGeneralSettings(
    BuildContext context,
    AsyncValue<AppSettings> settingsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Libraries',
              style: MacosTheme.of(context).typography.headline,
            ),
            const Spacer(),
            MacosTooltip(
              message: 'Add Folder',
              child: MacosIconButton(
                key: const ValueKey('settings-add-library-folder-button'),
                icon: const MacosIcon(CupertinoIcons.add),
                onPressed: () {
                  _pickLibraryFolder();
                },
                shape: BoxShape.rectangle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _FolderList()),
        if (_libraryActionMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _libraryActionMessage!,
            key: const ValueKey('settings-library-action-message'),
            style: MacosTheme.of(context).typography.caption1,
          ),
        ],
        const SizedBox(height: 12),
        const PrivateLibraryAutoLockControl(),
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
            MacosPopupButton<AppearanceThemeMode>(
              value:
                  settingsAsync.value?.appearance.themeMode ??
                  AppearanceConfiguration.defaults.themeMode,
              onChanged: (AppearanceThemeMode? mode) {
                if (mode != null) {
                  ref.read(settingsProvider.notifier).updateTheme(mode);
                }
              },
              items: const [
                MacosPopupMenuItem(
                  value: AppearanceThemeMode.system,
                  child: Text('System'),
                ),
                MacosPopupMenuItem(
                  value: AppearanceThemeMode.light,
                  child: Text('Light'),
                ),
                MacosPopupMenuItem(
                  value: AppearanceThemeMode.dark,
                  child: Text('Dark'),
                ),
              ],
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
                final interval =
                    int.tryParse(_intervalController.text) ??
                    LibrarySynchronizationConfiguration
                        .defaultScanIntervalMinutes;
                final batch =
                    int.tryParse(_batchSizeController.text) ??
                    LibrarySynchronizationConfiguration.defaultBatchSize;
                final pagination =
                    int.tryParse(_paginationSizeController.text) ??
                    CatalogBrowsingConfiguration.defaultPaginationSize;

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
    AsyncValue<AppSettings> settingsAsync,
  ) {
    final configuration =
        settingsAsync.value?.videoSummary ?? VideoSummaryConfiguration.defaults;
    final sourceMode = configuration.modelSource;
    final modelPath = configuration.modelPath;
    final selectedModelId = configuration.selectedModelId;
    final managedDirectoryPath = configuration.managedModelDirectoryPath;
    final downloadedManagedModels = configuration.downloadedManagedModels;
    final preferVttSubtitles = configuration.preferVttSubtitles;
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

  Widget _buildSummarizationSettings(AsyncValue<AppSettings> settingsAsync) {
    final configuration =
        settingsAsync.value?.videoSummary ?? VideoSummaryConfiguration.defaults;
    return SummarizationApiSettingsPanel(
      apiUrl: configuration.apiUrl,
      apiKey: configuration.apiKey,
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LibraryNameField(folder: folder),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(
                                    folder.path,
                                    style: MacosTheme.of(
                                      context,
                                    ).typography.caption1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
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
                          final result = await ref
                              .read(managedLibraryServiceProvider)
                              .setPrivacy(folder.id, isPrivate: nextIsPrivate);
                          ref.read(statusMessageProvider.notifier).set(
                            switch (result.status) {
                              ManagedLibraryPrivacyStatus.madePrivate =>
                                'Library is now private.',
                              ManagedLibraryPrivacyStatus.madePublic =>
                                'Library is now visible by default.',
                              ManagedLibraryPrivacyStatus
                                  .authenticationCancelled =>
                                'Authentication cancelled. Library remains private.',
                              ManagedLibraryPrivacyStatus.notFound =>
                                'Library no longer exists.',
                              ManagedLibraryPrivacyStatus.unchanged =>
                                folder.isPrivate
                                    ? 'Library remains private.'
                                    : 'Library remains visible by default.',
                            },
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
                          final result = await ref
                              .read(managedLibraryServiceProvider)
                              .repairAccess(folder.id, selectedDirectory);
                          ref.read(statusMessageProvider.notifier).set(
                            switch (result.status) {
                              ManagedLibraryRepairStatus.repaired =>
                                'Folder access repaired.',
                              ManagedLibraryRepairStatus.pathMismatch =>
                                'Select the same folder to repair access.',
                              ManagedLibraryRepairStatus.bookmarkUnavailable =>
                                'Could not repair folder access.',
                              ManagedLibraryRepairStatus.notFound =>
                                'Library no longer exists.',
                            },
                          );
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
                        onPressed: () async {
                          final result = await ref
                              .read(maintenanceControllerProvider.notifier)
                              .removeFolder(folder.id);
                          ref
                              .read(statusMessageProvider.notifier)
                              .set(
                                result.status ==
                                        ManagedLibraryRemoveStatus.removed
                                    ? 'Library removed. Files remain on disk.'
                                    : 'Library no longer exists.',
                              );
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

class _LibraryNameField extends ConsumerStatefulWidget {
  const _LibraryNameField({required this.folder});

  final Folder folder;

  @override
  ConsumerState<_LibraryNameField> createState() => _LibraryNameFieldState();
}

class _LibraryNameFieldState extends ConsumerState<_LibraryNameField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _errorText;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: libraryDisplayName(widget.folder),
    );
    _focusNode = FocusNode(debugLabel: 'library-name-${widget.folder.id}');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(_LibraryNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder != widget.folder && !_focusNode.hasFocus) {
      _controller.text = libraryDisplayName(widget.folder);
      _errorText = null;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _saveName();
    }
  }

  Future<void> _saveName() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    final result = await ref
        .read(managedLibraryServiceProvider)
        .rename(widget.folder.id, _controller.text);
    if (!mounted) {
      return;
    }
    final errorText = switch (result.status) {
      ManagedLibraryRenameStatus.blankName => libraryNameRequiredMessage,
      ManagedLibraryRenameStatus.duplicateName => libraryNameUniqueMessage,
      ManagedLibraryRenameStatus.notFound => 'Library no longer exists.',
      ManagedLibraryRenameStatus.renamed ||
      ManagedLibraryRenameStatus.unchanged => null,
    };
    final updatedFolder = result.folder;
    if (errorText == null && updatedFolder != null) {
      _controller.text = libraryDisplayName(updatedFolder);
    }
    setState(() {
      _isSaving = false;
      _errorText = errorText;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 260,
          child: MacosTextField(
            key: ValueKey('library-name-field-${widget.folder.id}'),
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_isSaving,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_errorText != null) {
                setState(() {
                  _errorText = null;
                });
              }
            },
            onSubmitted: (_) => _saveName(),
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            _errorText!,
            style: theme.typography.caption1.copyWith(
              color: MacosColors.systemRedColor,
            ),
          ),
        ],
      ],
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
