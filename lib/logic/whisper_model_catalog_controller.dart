import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'settings_provider.dart';
import 'whisper_model_catalog.dart';

part 'whisper_model_catalog_controller.g.dart';

const _whisperReadmeUrl =
    'https://raw.githubusercontent.com/ggml-org/whisper.cpp/master/README.md';

@Riverpod(keepAlive: true)
class WhisperModelCatalogController extends _$WhisperModelCatalogController {
  @override
  WhisperModelCatalogState build() {
    final settings = ref.watch(settingsProvider).asData?.value;
    final refreshedAtRaw =
        settings?['summaryCatalogLastRefreshedAt'] as String?;

    return WhisperModelCatalogState(
      entries: builtInWhisperModelCatalog,
      lastRefreshedAt: refreshedAtRaw == null
          ? null
          : DateTime.tryParse(refreshedAtRaw),
      isRefreshing: false,
      refreshError: null,
    );
  }

  Future<void> refresh() async {
    state = state.copyWith(isRefreshing: true, refreshError: null);

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_whisperReadmeUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Catalog refresh failed with status ${response.statusCode}.',
        );
      }

      final readme = await response.transform(SystemEncoding().decoder).join();
      final metadata = parseWhisperCppReadmeMetadata(readme);
      if (metadata.entries.isEmpty) {
        throw const FormatException(
          'Catalog refresh returned no model entries.',
        );
      }

      final refreshedAt = DateTime.now();
      await ref
          .read(settingsProvider.notifier)
          .updateSummaryCatalogLastRefreshedAt(refreshedAt);

      state = WhisperModelCatalogState(
        entries: metadata.entries,
        lastRefreshedAt: refreshedAt,
        isRefreshing: false,
        refreshError: null,
      );
    } catch (error) {
      state = state.copyWith(
        isRefreshing: false,
        refreshError: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
