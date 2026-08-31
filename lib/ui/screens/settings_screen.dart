import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:flutter/services.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/tables.dart';

import '../../logic/model_download_controller.dart';
import '../../logic/maintenance_controller.dart';
import '../../logic/catalog_controller.dart';
import '../../logic/folder_storage_status.dart';
import '../../logic/library_controller.dart';
import '../../logic/library_groups.dart';
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
import '../movie_manager_visual_system.dart';
import '../widgets/summary_model_settings_panel.dart';
import '../widgets/summarization_api_settings_panel.dart';
import '../widgets/private_library_auto_lock_control.dart';
import '../widgets/empty_folder_cleanup_control.dart';
import '../widgets/macos_preference_checkbox.dart';

enum _SettingsTab { general, misc, transcriptionAndSummarization }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _intervalController;
  late TextEditingController _batchSizeController;
  late TextEditingController _paginationSizeController;
  late FocusNode _intervalFocusNode;
  late FocusNode _batchSizeFocusNode;
  late FocusNode _paginationSizeFocusNode;
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
    _intervalFocusNode = FocusNode(debugLabel: 'scan-interval-preference')
      ..addListener(_saveAdvancedSettingsWhenIntervalLosesFocus);
    _batchSizeFocusNode = FocusNode(debugLabel: 'batch-size-preference')
      ..addListener(_saveAdvancedSettingsWhenBatchSizeLosesFocus);
    _paginationSizeFocusNode = FocusNode(
      debugLabel: 'pagination-size-preference',
    )..addListener(_saveAdvancedSettingsWhenPaginationSizeLosesFocus);
  }

  @override
  void dispose() {
    _intervalFocusNode.dispose();
    _batchSizeFocusNode.dispose();
    _paginationSizeFocusNode.dispose();
    _intervalController.dispose();
    _batchSizeController.dispose();
    _paginationSizeController.dispose();
    super.dispose();
  }

  void _saveAdvancedSettingsWhenIntervalLosesFocus() {
    if (!_intervalFocusNode.hasFocus) {
      _saveAdvancedSettings();
    }
  }

  void _saveAdvancedSettingsWhenBatchSizeLosesFocus() {
    if (!_batchSizeFocusNode.hasFocus) {
      _saveAdvancedSettings();
    }
  }

  void _saveAdvancedSettingsWhenPaginationSizeLosesFocus() {
    if (!_paginationSizeFocusNode.hasFocus) {
      _saveAdvancedSettings();
    }
  }

  void _saveAdvancedSettings() {
    final interval =
        int.tryParse(_intervalController.text) ??
        LibrarySynchronizationConfiguration.defaultScanIntervalMinutes;
    final batch =
        int.tryParse(_batchSizeController.text) ??
        LibrarySynchronizationConfiguration.defaultBatchSize;
    final pagination =
        int.tryParse(_paginationSizeController.text) ??
        CatalogBrowsingConfiguration.defaultPaginationSize;

    ref
        .read(settingsProvider.notifier)
        .updateSettings(interval, batch, pagination);
    ref.read(statusMessageProvider.notifier).set('Preferences saved');
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
        title: const ExcludeSemantics(child: Text('Back')),
        leading: Transform.translate(
          offset: const Offset(-10, 0),
          child: MovieManagerIconButton(
            label: 'Back',
            icon: CupertinoIcons.back,
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
                      backgroundColor: MacosTheme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.35),
                      thumbColor: MovieManagerVisuals.surfaceColor(context),
                      children: const {
                        _SettingsTab.general: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text('General'),
                        ),
                        _SettingsTab.misc: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text('Misc'),
                        ),
                        _SettingsTab.transcriptionAndSummarization: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text('Transcription & Summarization'),
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
                        _SettingsTab.misc => _buildMiscSettings(
                          context,
                          settingsAsync,
                        ),
                        _SettingsTab.transcriptionAndSummarization =>
                          _buildTranscriptionAndSummarizationSettings(
                            context,
                            settingsAsync,
                          ),
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
    FocusNode focusNode,
    Key fieldKey,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 200,
          child: Text(
            label,
            style: MacosTheme.of(context).typography.subheadline,
          ),
        ),
        SizedBox(
          width: 160,
          child: MovieManagerLabeledField(
            label: label,
            controller: controller,
            focusNode: focusNode,
            hasVisibleLabel: true,
            builder: (focusNode) => MacosTextField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveAdvancedSettings(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralSettings(
    BuildContext context,
    AsyncValue<AppSettings> settingsAsync,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Libraries',
                style: MacosTheme.of(context).typography.headline,
              ),
              const Spacer(),
              MovieManagerIconButton(
                key: const ValueKey('settings-add-library-folder-button'),
                label: 'Add Folder',
                icon: CupertinoIcons.add,
                onPressed: () {
                  _pickLibraryFolder();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const SizedBox(
            height: 240,
            child: _FolderList(key: ValueKey('settings-library-folder-list')),
          ),
          if (_libraryActionMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _libraryActionMessage!,
              key: const ValueKey('settings-library-action-message'),
              style: MacosTheme.of(context).typography.caption1,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(
                child: Text('Show private libraries in the Library filter'),
              ),
              const SizedBox(width: 6),
              MacosPreferenceCheckbox(
                key: const ValueKey(
                  'show-private-libraries-in-filter-checkbox',
                ),
                value:
                    settingsAsync
                        .value
                        ?.privateLibraryAccess
                        .showPrivateLibrariesInFilter ??
                    PrivateLibraryAccessConfiguration
                        .defaults
                        .showPrivateLibrariesInFilter,
                semanticLabel: 'Show private libraries in the Library filter',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .updateShowPrivateLibrariesInFilter(value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const PrivateLibraryAutoLockControl(),
          const SizedBox(height: 12),
          const _OpenDataFolderWidget(),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          const _LibraryGroupsPanel(),
        ],
      ),
    );
  }

  Widget _buildMiscSettings(
    BuildContext context,
    AsyncValue<AppSettings> settingsAsync,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: Text(
                  'Theme',
                  style: MacosTheme.of(context).typography.subheadline,
                ),
              ),
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
          const SizedBox(height: 16),
          const EmptyFolderCleanupControl(),
          const SizedBox(height: 16),
          _buildPreferenceRow(
            context,
            'Scan Interval (min)',
            _intervalController,
            _intervalFocusNode,
            const ValueKey('scan-interval-preference-field'),
          ),
          const SizedBox(height: 12),
          _buildPreferenceRow(
            context,
            'DB Batch Size',
            _batchSizeController,
            _batchSizeFocusNode,
            const ValueKey('batch-size-preference-field'),
          ),
          const SizedBox(height: 12),
          _buildPreferenceRow(
            context,
            'Pagination Size',
            _paginationSizeController,
            _paginationSizeFocusNode,
            const ValueKey('pagination-size-preference-field'),
          ),
        ],
      ),
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

  Widget _buildTranscriptionAndSummarizationSettings(
    BuildContext context,
    AsyncValue<AppSettings> settingsAsync,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final transcriptionPane = _buildTranscribeSettings(
          context,
          settingsAsync,
        );
        final summarizationPane = _buildSummarizationSettings(settingsAsync);

        if (constraints.maxWidth < 1200) {
          return Column(
            children: [
              Expanded(child: transcriptionPane),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(),
              ),
              Expanded(child: summarizationPane),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: transcriptionPane),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: VerticalDivider(),
            ),
            Expanded(child: summarizationPane),
          ],
        );
      },
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
          MovieManagerIconButton(
            label: 'Open data folder in Finder',
            icon: CupertinoIcons.folder,
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
  const _FolderList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersDaoProvider).watchAllFolders();
    ref.watch(libraryGroupsRefreshProvider);
    final groupsFuture = ref.read(libraryGroupsDaoProvider).getAllGroups();

    return FutureBuilder<List<LibraryGroup>>(
      future: groupsFuture,
      builder: (context, groupSnapshot) {
        final groupNames = (groupSnapshot.data ?? const <LibraryGroup>[])
            .map((group) => group.name)
            .toList();
        if (!groupNames.any(
          (name) => sameLibraryGroupName(name, defaultLibraryGroupName),
        )) {
          groupNames.insert(0, defaultLibraryGroupName);
        }

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
                                  const SizedBox(width: 12),
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
                        const SizedBox(width: 12),
                        _LibraryGroupSelector(
                          folder: folder,
                          groupNames: groupNames,
                        ),
                        MovieManagerIconButton(
                          label: folder.isPrivate
                              ? 'Private library. Click to make videos visible by default.'
                              : 'Public library. Click to require authentication before videos appear.',
                          icon: folder.isPrivate
                              ? CupertinoIcons.lock
                              : CupertinoIcons.lock_open,
                          selected: folder.isPrivate,
                          onPressed: () async {
                            final nextIsPrivate = !folder.isPrivate;
                            final result = await ref
                                .read(managedLibraryServiceProvider)
                                .setPrivacy(
                                  folder.id,
                                  isPrivate: nextIsPrivate,
                                );
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
                        MovieManagerIconButton(
                          label: accessTooltip,
                          icon: CupertinoIcons.exclamationmark_shield,
                          color: storageStatus.needsRepair
                              ? MacosColors.systemOrangeColor
                              : storageStatus.isRemovableStorage
                              ? MacosColors.systemBlueColor
                              : MacosColors.systemGrayColor,
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
                                ManagedLibraryRepairStatus
                                    .bookmarkUnavailable =>
                                  'Could not repair folder access.',
                                ManagedLibraryRepairStatus.notFound =>
                                  'Library no longer exists.',
                              },
                            );
                          },
                        ),
                        MovieManagerIconButton(
                          label:
                              'Remove this folder from the library. Files stay on disk.',
                          icon: CupertinoIcons.trash,
                          color: MovieManagerVisuals.errorColor(context),
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
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _LibraryGroupsPanel extends ConsumerStatefulWidget {
  const _LibraryGroupsPanel();

  @override
  ConsumerState<_LibraryGroupsPanel> createState() =>
      _LibraryGroupsPanelState();
}

class _LibraryGroupsPanelState extends ConsumerState<_LibraryGroupsPanel> {
  final _nameController = TextEditingController();
  String? _message;
  late Future<List<LibraryGroup>> _groupsFuture;

  @override
  void initState() {
    super.initState();
    _groupsFuture = ref.read(libraryGroupsDaoProvider).getAllGroups();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addGroup() async {
    final result = await ref
        .read(managedLibraryServiceProvider)
        .addGroup(_nameController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _message = switch (result.status) {
        ManagedLibraryGroupStatus.created => 'Group added.',
        ManagedLibraryGroupStatus.blankName => 'Group name is required.',
        ManagedLibraryGroupStatus.duplicateName => 'Group name must be unique.',
        _ => 'Could not add group.',
      };
      if (result.status == ManagedLibraryGroupStatus.created) {
        _nameController.clear();
        _groupsFuture = ref.read(libraryGroupsDaoProvider).getAllGroups();
        ref.read(libraryGroupsRefreshProvider.notifier).refresh();
      }
    });
  }

  Future<void> _removeGroup(String name) async {
    final result = await ref
        .read(managedLibraryServiceProvider)
        .removeGroup(name);
    if (!mounted) {
      return;
    }
    setState(() {
      _message = switch (result.status) {
        ManagedLibraryGroupStatus.removed =>
          'Group removed. Libraries moved to Default Group.',
        ManagedLibraryGroupStatus.defaultGroup =>
          'Default Group cannot be removed.',
        ManagedLibraryGroupStatus.groupNotFound => 'Group no longer exists.',
        _ => 'Could not remove group.',
      };
      if (result.status == ManagedLibraryGroupStatus.removed) {
        _groupsFuture = ref.read(libraryGroupsDaoProvider).getAllGroups();
        ref.read(libraryGroupsRefreshProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LibraryGroup>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        final groups = List<LibraryGroup>.from(
          snapshot.data ?? const <LibraryGroup>[],
        )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        if (!groups.any(
          (group) => sameLibraryGroupName(group.name, defaultLibraryGroupName),
        )) {
          groups.insert(
            0,
            LibraryGroup(
              id: 0,
              name: defaultLibraryGroupName,
              addedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Groups', style: MacosTheme.of(context).typography.headline),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 240,
                  child: MovieManagerLabeledField(
                    label: 'New group name',
                    controller: _nameController,
                    builder: (focusNode) => MacosTextField(
                      key: const ValueKey('library-group-name-field'),
                      controller: _nameController,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addGroup(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                MovieManagerIconButton(
                  key: const ValueKey('library-group-add-button'),
                  label: 'Add group',
                  icon: CupertinoIcons.add,
                  onPressed: _addGroup,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final group in groups)
                  Builder(
                    builder: (context) {
                      final isDefault = sameLibraryGroupName(
                        group.name,
                        defaultLibraryGroupName,
                      );
                      final theme = MacosTheme.of(context);
                      return Container(
                        key: ValueKey('library-group-chip-${group.id}'),
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.12),
                          border: Border.all(
                            color: theme.primaryColor.withValues(alpha: 0.35),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(group.name, textAlign: TextAlign.right),
                            const SizedBox(width: 8),
                            SizedBox.square(
                              key: ValueKey(
                                'library-group-action-slot-${group.id}',
                              ),
                              dimension:
                                  MovieManagerControlMetrics.minimumTarget,
                              child: isDefault
                                  ? null
                                  : MovieManagerIconButton(
                                      key: ValueKey(
                                        'library-group-remove-${group.id}',
                                      ),
                                      label:
                                          'Remove ${group.name}. Libraries return to Default Group.',
                                      icon: CupertinoIcons.trash,
                                      onPressed: () => _removeGroup(group.name),
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 6),
              Text(
                _message!,
                style: MacosTheme.of(context).typography.caption1,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LibraryGroupSelector extends ConsumerWidget {
  const _LibraryGroupSelector({required this.folder, required this.groupNames});

  final Folder folder;
  final List<String> groupNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = <String>[...groupNames];
    final currentGroup = libraryGroupName(folder);
    if (!names.any((name) => sameLibraryGroupName(name, currentGroup))) {
      names.add(currentGroup);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return SizedBox(
      width: 160,
      child: MacosPopupButton<String>(
        key: ValueKey('library-group-selector-${folder.id}'),
        value: names.firstWhere(
          (name) => sameLibraryGroupName(name, currentGroup),
        ),
        onChanged: (String? name) async {
          if (name == null) {
            return;
          }
          final result = await ref
              .read(managedLibraryServiceProvider)
              .assignGroup(folder.id, name);
          ref.read(statusMessageProvider.notifier).set(switch (result.status) {
            ManagedLibraryGroupStatus.assigned => 'Library group updated.',
            ManagedLibraryGroupStatus.groupNotFound =>
              'Group no longer exists.',
            ManagedLibraryGroupStatus.folderNotFound =>
              'Library no longer exists.',
            _ => 'Library group unchanged.',
          });
        },
        items: [
          for (final name in names)
            MacosPopupMenuItem(
              value: name,
              child: MacosTooltip(
                message: name,
                child: SizedBox(
                  width: 96,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
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
          child: MovieManagerLabeledField(
            label: 'Library name for ${widget.folder.path}',
            controller: _controller,
            focusNode: _focusNode,
            enabled: !_isSaving,
            builder: (focusNode) => MacosTextField(
              key: ValueKey('library-name-field-${widget.folder.id}'),
              controller: _controller,
              focusNode: focusNode,
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
