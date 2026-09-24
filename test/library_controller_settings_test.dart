import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'library scan timer reacts to typed synchronization configuration',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'scanInterval': 7,
      });
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final timers = <_RecordingTimer>[];
      final durations = <Duration>[];
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          periodicScanTimerFactoryProvider.overrideWithValue((duration, _) {
            durations.add(duration);
            final timer = _RecordingTimer();
            timers.add(timer);
            return timer;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container.read(libraryControllerProvider.future);
      expect(durations, [const Duration(minutes: 7)]);

      await container.read(settingsProvider.notifier).updateSettings(12, 4, 50);

      expect(durations, [
        const Duration(minutes: 7),
        const Duration(minutes: 12),
      ]);
      expect(timers.first.isActive, isFalse);
      expect(timers.last.isActive, isTrue);

      await Future<void>.delayed(Duration.zero);
      for (var attempt = 0; attempt < 50; attempt += 1) {
        if (!container.read(libraryOperationControllerProvider).isScanning) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    },
  );

  test('periodic ticks do not replace an active scan status', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final foldersDao = _BlockingFoldersDao(database);
    void Function(Timer)? timerCallback;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        foldersDaoProvider.overrideWithValue(foldersDao),
        periodicScanTimerFactoryProvider.overrideWithValue((_, callback) {
          timerCallback = callback;
          return _NoopTimer();
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(libraryControllerProvider.future);
    await foldersDao.scanStarted.future;
    expect(timerCallback, isNotNull);
    expect(container.read(scanStatusProvider), 'Checking for updates...');

    timerCallback!(_NoopTimer());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(scanStatusProvider), 'Checking for updates...');

    foldersDao.releaseScan();
    await _waitForScanIdle(container);
  });
}

class _BlockingFoldersDao extends FoldersDao {
  _BlockingFoldersDao(super.db);

  final scanStarted = Completer<void>();
  final _scanRelease = Completer<void>();
  var _getAllFoldersCalls = 0;

  @override
  Future<List<Folder>> getAllFolders() async {
    _getAllFoldersCalls += 1;
    if (_getAllFoldersCalls == 1) {
      return <Folder>[];
    }
    if (!scanStarted.isCompleted) {
      scanStarted.complete();
    }
    await _scanRelease.future;
    return <Folder>[];
  }

  void releaseScan() {
    if (!_scanRelease.isCompleted) {
      _scanRelease.complete();
    }
  }
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

Future<void> _waitForScanIdle(ProviderContainer container) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (!container.read(libraryOperationControllerProvider).isScanning) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Timed out waiting for scan to finish.');
}

class _RecordingTimer implements Timer {
  @override
  bool isActive = true;

  @override
  int get tick => 0;

  @override
  void cancel() {
    isActive = false;
  }
}
