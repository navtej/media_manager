import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/library_controller.dart';
import 'package:movie_manager/logic/library_operation_controller.dart';
import 'package:movie_manager/logic/maintenance_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/status_message_provider.dart';
import 'package:movie_manager/services/empty_folder_cleanup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'missing schedule state anchors now and waits one full interval',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      var now = DateTime.utc(2026, 7, 21, 9);
      var cleanupCount = 0;
      final timers = <_RecordedTimer>[];
      final container = _container(
        clock: () => now,
        timers: timers,
        runner: () async {
          cleanupCount += 1;
          return _success();
        },
      );
      addTearDown(container.dispose);

      await container.read(maintenanceControllerProvider.future);

      expect(cleanupCount, 0);
      expect(timers.single.duration, const Duration(days: 7));
      expect(await _persistedAnchor(), now);

      now = now.add(const Duration(days: 6));
      await container
          .read(maintenanceControllerProvider.notifier)
          .evaluateEmptyFolderCleanupSchedule();
      expect(cleanupCount, 0);
    },
  );

  test('disable during initialization is honored before scheduling', () async {
    final now = DateTime.utc(2026, 7, 21, 9);
    final persistence = _BlockingAnchorPersistence();
    var cleanupCount = 0;
    final timers = <_RecordedTimer>[];
    final container = _container(
      clock: () => now,
      timers: timers,
      persistence: persistence,
      runner: () async {
        cleanupCount += 1;
        return _success();
      },
    );
    addTearDown(container.dispose);

    final initialization = container.read(maintenanceControllerProvider.future);
    await persistence.anchorWriteStarted.future;
    await container
        .read(settingsProvider.notifier)
        .updateEmptyFolderCleanup(enabled: false, intervalDays: 7);
    persistence.allowAnchorWrite.complete();
    await initialization;

    expect(cleanupCount, 0);
    expect(timers, isEmpty);
    expect(persistence.getBool('emptyFolderCleanupEnabled'), isFalse);
  });

  test(
    'due persisted schedule runs, surfaces failures, and advances',
    () async {
      final now = DateTime.utc(2026, 7, 21, 9);
      SharedPreferences.setMockInitialValues(<String, Object>{
        emptyFolderCleanupScheduleAnchorKey: now
            .subtract(const Duration(days: 7))
            .toIso8601String(),
      });
      var cleanupCount = 0;
      final timers = <_RecordedTimer>[];
      final container = _container(
        clock: () => now,
        timers: timers,
        runner: () async {
          cleanupCount += 1;
          return const EmptyFolderCleanupResult(
            librariesAttempted: 3,
            directoriesRemoved: 4,
            libraryFailures: 1,
            directoryFailures: 2,
          );
        },
      );
      addTearDown(container.dispose);
      final messages = <String?>[];
      final subscription = container.listen<String?>(
        statusMessageProvider,
        (_, next) => messages.add(next),
      );
      addTearDown(subscription.close);

      await container.read(maintenanceControllerProvider.future);

      expect(cleanupCount, 1);
      expect(await _persistedAnchor(), now);
      expect(container.read(scanStatusProvider), isEmpty);
      expect(
        container.read(libraryOperationControllerProvider).isBusy,
        isFalse,
      );
      expect(messages.last, contains('4 empty folders'));
      expect(messages.last, contains('1 Libraries'));
      expect(messages.last, contains('2 directories failed'));
      expect(timers.last.duration, const Duration(days: 7));
    },
  );

  test('disable cancels work and re-enable starts a fresh interval', () async {
    var now = DateTime.utc(2026, 7, 21, 9);
    SharedPreferences.setMockInitialValues(<String, Object>{
      emptyFolderCleanupScheduleAnchorKey: now.toIso8601String(),
    });
    var cleanupCount = 0;
    final timers = <_RecordedTimer>[];
    final container = _container(
      clock: () => now,
      timers: timers,
      runner: () async {
        cleanupCount += 1;
        return _success();
      },
    );
    addTearDown(container.dispose);
    await container.read(maintenanceControllerProvider.future);

    await container
        .read(settingsProvider.notifier)
        .updateEmptyFolderCleanup(enabled: false, intervalDays: 7);
    await _waitUntil(() => timers.every((timer) => !timer.isActive));
    now = now.add(const Duration(days: 30));
    await container
        .read(maintenanceControllerProvider.notifier)
        .evaluateEmptyFolderCleanupSchedule();
    expect(cleanupCount, 0);

    await container
        .read(settingsProvider.notifier)
        .updateEmptyFolderCleanup(enabled: true, intervalDays: 7);
    await _waitUntil(() async => await _persistedAnchor() == now);
    await container
        .read(maintenanceControllerProvider.notifier)
        .evaluateEmptyFolderCleanupSchedule();
    expect(cleanupCount, 0);
    expect(timers.last.duration, const Duration(days: 7));
  });

  test(
    'shortening interval preserves anchor and can become immediately due',
    () async {
      final anchor = DateTime.utc(2026, 7, 1);
      final now = DateTime.utc(2026, 7, 5);
      SharedPreferences.setMockInitialValues(<String, Object>{
        emptyFolderCleanupScheduleAnchorKey: anchor.toIso8601String(),
      });
      var cleanupCount = 0;
      final container = _container(
        clock: () => now,
        timers: <_RecordedTimer>[],
        runner: () async {
          cleanupCount += 1;
          return _success();
        },
      );
      addTearDown(container.dispose);
      await container.read(maintenanceControllerProvider.future);

      await container
          .read(settingsProvider.notifier)
          .updateEmptyFolderCleanup(enabled: true, intervalDays: 3);
      await _waitUntil(() => cleanupCount == 1);

      expect(await _persistedAnchor(), now);
    },
  );

  test(
    'lengthening interval preserves anchor and postpones due time',
    () async {
      final anchor = DateTime.utc(2026, 7, 1);
      final now = DateTime.utc(2026, 7, 5);
      SharedPreferences.setMockInitialValues(<String, Object>{
        emptyFolderCleanupScheduleAnchorKey: anchor.toIso8601String(),
      });
      var cleanupCount = 0;
      final timers = <_RecordedTimer>[];
      final container = _container(
        clock: () => now,
        timers: timers,
        runner: () async {
          cleanupCount += 1;
          return _success();
        },
      );
      addTearDown(container.dispose);
      await container.read(maintenanceControllerProvider.future);

      await container
          .read(settingsProvider.notifier)
          .updateEmptyFolderCleanup(enabled: true, intervalDays: 14);
      await _waitUntil(() => timers.last.duration == const Duration(days: 10));

      expect(cleanupCount, 0);
      expect(await _persistedAnchor(), anchor);
    },
  );

  test(
    'active cleanup owns the operation lock until its sweep finishes',
    () async {
      final now = DateTime.utc(2026, 7, 21, 9);
      SharedPreferences.setMockInitialValues(<String, Object>{
        emptyFolderCleanupScheduleAnchorKey: now
            .subtract(const Duration(days: 8))
            .toIso8601String(),
      });
      final started = Completer<void>();
      final finish = Completer<void>();
      final container = _container(
        clock: () => now,
        timers: <_RecordedTimer>[],
        runner: () async {
          started.complete();
          await finish.future;
          return _success();
        },
      );
      addTearDown(container.dispose);

      final initialization = container.read(
        maintenanceControllerProvider.future,
      );
      await started.future;
      final operation = container.read(
        libraryOperationControllerProvider.notifier,
      );
      expect(operation.beginScan(), isFalse);
      expect(operation.beginMove(), isFalse);
      expect(
        container.read(libraryOperationControllerProvider).isCleaning,
        isTrue,
      );

      finish.complete();
      await initialization;
      expect(
        container.read(libraryOperationControllerProvider).isBusy,
        isFalse,
      );
    },
  );

  test('failed sweep keeps anchor and clears active status', () async {
    final now = DateTime.utc(2026, 7, 21, 9);
    final oldAnchor = now.subtract(const Duration(days: 8));
    SharedPreferences.setMockInitialValues(<String, Object>{
      emptyFolderCleanupScheduleAnchorKey: oldAnchor.toIso8601String(),
    });
    final timers = <_RecordedTimer>[];
    final container = _container(
      clock: () => now,
      timers: timers,
      runner: () async => throw StateError('unexpected sweep failure'),
    );
    addTearDown(container.dispose);

    await container.read(maintenanceControllerProvider.future);

    expect(await _persistedAnchor(), oldAnchor);
    expect(container.read(scanStatusProvider), isEmpty);
    expect(container.read(libraryOperationControllerProvider).isBusy, isFalse);
    expect(timers.last.duration, const Duration(days: 7));
  });

  for (final operationName in <String>['scan', 'move']) {
    test(
      'due cleanup defers while $operationName owns the operation lock',
      () async {
        final now = DateTime.utc(2026, 7, 21, 9);
        final oldAnchor = now.subtract(const Duration(days: 8));
        SharedPreferences.setMockInitialValues(<String, Object>{
          emptyFolderCleanupScheduleAnchorKey: oldAnchor.toIso8601String(),
        });
        var cleanupCount = 0;
        final container = _container(
          clock: () => now,
          timers: <_RecordedTimer>[],
          runner: () async {
            cleanupCount += 1;
            return _success();
          },
        );
        addTearDown(container.dispose);
        final operation = container.read(
          libraryOperationControllerProvider.notifier,
        );
        expect(
          operationName == 'scan'
              ? operation.beginScan()
              : operation.beginMove(),
          isTrue,
        );

        await container.read(maintenanceControllerProvider.future);
        expect(cleanupCount, 0);
        expect(await _persistedAnchor(), oldAnchor);

        if (operationName == 'scan') {
          operation.endScan();
        } else {
          operation.endMove();
        }
        await _waitUntil(() => cleanupCount == 1);
        expect(await _persistedAnchor(), now);
      },
    );
  }
}

ProviderContainer _container({
  required DateTime Function() clock,
  required List<_RecordedTimer> timers,
  required EmptyFolderCleanupRunner runner,
  SettingsPersistence? persistence,
}) {
  return ProviderContainer(
    overrides: [
      if (persistence != null)
        settingsPersistenceProvider.overrideWith((ref) async => persistence),
      emptyFolderCleanupClockProvider.overrideWithValue(clock),
      emptyFolderCleanupRunnerProvider.overrideWithValue(runner),
      emptyFolderCleanupTimerFactoryProvider.overrideWithValue((
        duration,
        callback,
      ) {
        final timer = _RecordedTimer(duration, callback);
        timers.add(timer);
        return timer;
      }),
    ],
  );
}

EmptyFolderCleanupResult _success() {
  return const EmptyFolderCleanupResult(
    librariesAttempted: 0,
    directoriesRemoved: 0,
    libraryFailures: 0,
    directoryFailures: 0,
  );
}

Future<DateTime?> _persistedAnchor() async {
  final preferences = await SharedPreferences.getInstance();
  final value = preferences.getString(emptyFolderCleanupScheduleAnchorKey);
  return value == null ? null : DateTime.parse(value);
}

Future<void> _waitUntil(FutureOr<bool> Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw TimeoutException('Condition was not met.');
}

class _RecordedTimer implements Timer {
  _RecordedTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _isActive = false;
  }
}

class _BlockingAnchorPersistence implements SettingsPersistence {
  final Map<String, Object> values = {};
  final Completer<void> anchorWriteStarted = Completer<void>();
  final Completer<void> allowAnchorWrite = Completer<void>();

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  int? getInt(String key) => values[key] as int?;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => values[key] = value;

  @override
  Future<void> setString(String key, String value) async {
    if (key == emptyFolderCleanupScheduleAnchorKey) {
      if (!anchorWriteStarted.isCompleted) {
        anchorWriteStarted.complete();
      }
      await allowAnchorWrite.future;
    }
    values[key] = value;
  }
}
