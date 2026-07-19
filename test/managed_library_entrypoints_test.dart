import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/logic/managed_library_service.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/services/library_access_service.dart';

void main() {
  test(
    'Home add and move-destination add persist equivalent Library state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'managed-library-entrypoints-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final home = await _addThroughHome('${directory.path}/');
      final move = await _addThroughMove(directory.path);

      expect(home.status, ManagedLibraryAddStatus.created);
      expect(move.status, ManagedLibraryAddStatus.created);
      expect(home.persistedState, move.persistedState);
      expect(home.libraryCount, 1);
      expect(move.libraryCount, 1);
    },
  );
}

Future<_EntrypointResult> _addThroughHome(String path) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final container = _container(db);
  try {
    await container.read(libraryControllerProvider.future);
    await Future<void>.delayed(Duration.zero);
    await _waitForScanIdle(container);
    final result = await container
        .read(libraryControllerProvider.notifier)
        .addFolder(path);
    final managedResult = result.managedLibraryResult!;
    return _EntrypointResult(
      status: managedResult.status,
      persistedState: _persistedState(managedResult.folder!),
      libraryCount: (await db.foldersDao.getAllFolders()).length,
    );
  } finally {
    container.dispose();
    await db.close();
  }
}

Future<_EntrypointResult> _addThroughMove(String path) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final container = _container(db);
  try {
    final result = await container
        .read(managedLibraryServiceProvider)
        .addOrRefresh(path);
    return _EntrypointResult(
      status: result.status,
      persistedState: _persistedState(result.folder!),
      libraryCount: (await db.foldersDao.getAllFolders()).length,
    );
  } finally {
    container.dispose();
    await db.close();
  }
}

ProviderContainer _container(AppDatabase db) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      settingsProvider.overrideWith(_StaticSettings.new),
      periodicScanTimerFactoryProvider.overrideWithValue(
        (_, _) => _NoopTimer(),
      ),
      libraryAccessServiceProvider.overrideWithValue(
        LibraryAccessService(adapter: _BookmarkingLibraryAccessAdapter()),
      ),
    ],
  );
}

(String, String?, String?, bool) _persistedState(Folder folder) {
  return (
    folder.path,
    folder.alias,
    folder.securityScopedBookmark,
    folder.isPrivate,
  );
}

class _EntrypointResult {
  const _EntrypointResult({
    required this.status,
    required this.persistedState,
    required this.libraryCount,
  });

  final ManagedLibraryAddStatus status;
  final (String, String?, String?, bool) persistedState;
  final int libraryCount;
}

Future<void> _waitForScanIdle(ProviderContainer container) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (!container.read(libraryOperationControllerProvider).isScanning) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Timed out waiting for the startup scan.');
}

class _StaticSettings extends Settings {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _BookmarkingLibraryAccessAdapter implements LibraryAccessAdapter {
  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async => true;

  @override
  Future<void> stopAccessing(String path) async {}
}

class _NoopTimer implements Timer {
  @override
  bool isActive = true;

  @override
  int get tick => 0;

  @override
  void cancel() {
    isActive = false;
  }
}
