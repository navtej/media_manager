import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/data/providers.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/logic/video_selection_controller.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/provider_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('unlock succeeds after owner authentication', () async {
    final auth = _FakePrivateLibraryAuthService(result: true);
    final container = ProviderContainer(
      overrides: [privateLibraryAuthServiceProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);

    final unlocked = await container
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();

    expect(unlocked, isTrue);
    expect(auth.attempts, 1);
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );
    expect(
      container.read(privateLibraryAccessControllerProvider).errorMessage,
      isNull,
    );
  });

  test('unlock failure keeps private libraries locked', () async {
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final unlocked = await container
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();

    final state = container.read(privateLibraryAccessControllerProvider);
    expect(unlocked, isFalse);
    expect(state.isUnlocked, isFalse);
    expect(state.isAuthenticating, isFalse);
    expect(state.errorMessage, 'Authentication cancelled.');
  });

  test(
    'disabling filter visibility while authenticating keeps private libraries locked',
    () async {
      final auth = _DeferredPrivateLibraryAuthService();
      final container = ProviderContainer(
        overrides: [privateLibraryAuthServiceProvider.overrideWithValue(auth)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        privateLibraryAccessControllerProvider.notifier,
      );
      await container
          .read(settingsProvider.notifier)
          .updateShowPrivateLibrariesInFilter(true);
      await _waitFor(
        () => container.read(showPrivateLibrariesInFilterProvider),
      );

      final unlockFuture = controller.unlock();
      await auth.started.future;
      await container
          .read(settingsProvider.notifier)
          .updateShowPrivateLibrariesInFilter(false);
      await _waitFor(
        () => !container.read(showPrivateLibrariesInFilterProvider),
      );
      auth.complete(true);

      expect(await unlockFuture, isFalse);
      expect(
        container.read(privateLibraryAccessControllerProvider).isUnlocked,
        isFalse,
      );
    },
  );

  test('lock clears private access state', () async {
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();
    container.read(privateLibraryAccessControllerProvider.notifier).lock();

    final state = container.read(privateLibraryAccessControllerProvider);
    expect(state.isUnlocked, isFalse);
    expect(state.isAuthenticating, isFalse);
    expect(state.errorMessage, isNull);
  });

  testWidgets('successful unlock locks after the default countdown', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();

    await tester.pump(const Duration(minutes: 9, seconds: 59));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  testWidgets('changed duration restarts an active countdown', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'privateLibraryAutoLockMinutes': 1,
    });
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();
    await tester.pump(const Duration(seconds: 30));

    await container
        .read(settingsProvider.notifier)
        .updatePrivateLibraryAutoLockMinutes(2);
    await tester.pump();
    expect(
      container.read(privateLibraryAutoLockDurationProvider),
      const Duration(minutes: 2),
    );
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  testWidgets('manual lock cancels the previous countdown', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'privateLibraryAutoLockMinutes': 1,
    });
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      privateLibraryAccessControllerProvider.notifier,
    );

    await controller.unlock();
    await tester.pump(const Duration(seconds: 30));
    controller.lock();
    await controller.unlock();

    await tester.pump(const Duration(seconds: 31));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );

    await tester.pump(const Duration(seconds: 29));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  test('resume enforcement locks an overdue wall-clock deadline', () async {
    var now = DateTime(2026, 7, 19, 10);
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
        privateLibraryAutoLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      privateLibraryAccessControllerProvider.notifier,
    );

    await controller.unlock();
    now = now.add(const Duration(minutes: 11));
    controller.enforceAutoLockDeadline();

    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  testWidgets('resume before the deadline re-arms only the remaining time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'privateLibraryAutoLockMinutes': 1,
    });
    var now = DateTime(2026, 7, 19, 10);
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
        privateLibraryAutoLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      privateLibraryAccessControllerProvider.notifier,
    );

    await controller.unlock();
    now = now.add(const Duration(seconds: 20));
    controller.enforceAutoLockDeadline();

    await tester.pump(const Duration(seconds: 39));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  testWidgets('provider disposal cancels an active countdown', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'privateLibraryAutoLockMinutes': 1,
    });
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _FakePrivateLibraryAuthService(result: true),
        ),
      ],
    );

    await container
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();
    container.dispose();
    await tester.pump(const Duration(minutes: 1));

    expect(tester.takeException(), isNull);
  });

  test(
    'direct lock hides private libraries and removes private selections',
    () async {
      final fixture = await _PrivateLibraryPolicyFixture.create(
        authenticationResult: true,
      );
      addTearDown(fixture.dispose);
      await readAsyncValue<List<Folder>>(
        fixture.container,
        libraryFoldersProvider,
      );
      final selectedFolders = fixture.container.read(
        selectedLibraryFoldersControllerProvider.notifier,
      );
      selectedFolders.toggle(fixture.publicFolderId);
      selectedFolders.toggle(fixture.privateFolderId);
      await fixture.container
          .read(videoSelectionControllerProvider.notifier)
          .selectLoaded([fixture.publicVideoId, fixture.privateVideoId]);

      final controller = fixture.container.read(
        privateLibraryAccessControllerProvider.notifier,
      );
      await controller.unlock();
      expect(
        fixture.container.read(effectiveLibraryFolderIdsProvider).toSet(),
        {fixture.publicFolderId, fixture.privateFolderId},
      );

      await controller.lock();

      expect(
        fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked,
        isFalse,
      );
      expect(fixture.container.read(effectiveLibraryFolderIdsProvider), [
        fixture.publicFolderId,
      ]);
      expect(fixture.container.read(selectedLibraryFoldersControllerProvider), {
        fixture.publicFolderId,
      });
      expect(
        fixture.container.read(videoSelectionControllerProvider).selectedIds,
        {fixture.publicVideoId},
      );
    },
  );

  test(
    'disabling private-library filter visibility locks and clears private selections',
    () async {
      final fixture = await _PrivateLibraryPolicyFixture.create(
        authenticationResult: true,
      );
      addTearDown(fixture.dispose);
      await readAsyncValue<List<Folder>>(
        fixture.container,
        libraryFoldersProvider,
      );
      final controller = fixture.container.read(
        privateLibraryAccessControllerProvider.notifier,
      );
      await fixture.container
          .read(settingsProvider.notifier)
          .updateShowPrivateLibrariesInFilter(true);
      await _waitFor(
        () => fixture.container.read(showPrivateLibrariesInFilterProvider),
      );

      final selectedFolders = fixture.container.read(
        selectedLibraryFoldersControllerProvider.notifier,
      );
      selectedFolders.toggle(fixture.publicFolderId);
      selectedFolders.toggle(fixture.privateFolderId);
      await fixture.container
          .read(videoSelectionControllerProvider.notifier)
          .selectLoaded([fixture.publicVideoId, fixture.privateVideoId]);
      await controller.unlock();

      await fixture.container
          .read(settingsProvider.notifier)
          .updateShowPrivateLibrariesInFilter(false);
      await _waitFor(() {
        final selectedFolderIds = fixture.container.read(
          selectedLibraryFoldersControllerProvider,
        );
        final selectedVideoIds = fixture.container
            .read(videoSelectionControllerProvider)
            .selectedIds;
        return !fixture.container
                .read(privateLibraryAccessControllerProvider)
                .isUnlocked &&
            selectedFolderIds.length == 1 &&
            selectedFolderIds.contains(fixture.publicFolderId) &&
            selectedVideoIds.length == 1 &&
            selectedVideoIds.contains(fixture.publicVideoId);
      });

      expect(
        fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked,
        isFalse,
      );
      expect(fixture.container.read(selectedLibraryFoldersControllerProvider), {
        fixture.publicFolderId,
      });
      expect(
        fixture.container.read(videoSelectionControllerProvider).selectedIds,
        {fixture.publicVideoId},
      );
    },
  );

  test(
    'disabling filter visibility waits for an active private action',
    () async {
      final fixture = await _PrivateLibraryPolicyFixture.create(
        authenticationResult: true,
      );
      addTearDown(fixture.dispose);
      final controller = fixture.container.read(
        privateLibraryAccessControllerProvider.notifier,
      );
      await fixture.container
          .read(settingsProvider.notifier)
          .updateShowPrivateLibrariesInFilter(true);
      await _waitFor(
        () => fixture.container.read(showPrivateLibrariesInFilterProvider),
      );
      await controller.unlock();
      final actionStarted = Completer<void>();
      final finishAction = Completer<void>();

      final actionFuture = controller.runVideoAction<int>(
        videoIds: [fixture.privateVideoId],
        action: () async {
          actionStarted.complete();
          await finishAction.future;
          return 42;
        },
      );
      await actionStarted.future;

      await fixture.container
          .read(settingsProvider.notifier)
          .updateShowPrivateLibrariesInFilter(false);
      await _waitFor(
        () => !fixture.container.read(showPrivateLibrariesInFilterProvider),
      );
      expect(
        fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked,
        isTrue,
      );

      finishAction.complete();
      expect(await actionFuture, 42);
      await _waitFor(
        () => !fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked,
      );
    },
  );

  test('locked private action authenticates, runs, and relocks', () async {
    final fixture = await _PrivateLibraryPolicyFixture.create(
      authenticationResult: true,
    );
    addTearDown(fixture.dispose);
    await fixture.container
        .read(videoSelectionControllerProvider.notifier)
        .selectLoaded([fixture.publicVideoId, fixture.privateVideoId]);
    final controller = fixture.container.read(
      privateLibraryAccessControllerProvider.notifier,
    );
    var wasUnlockedDuringAction = false;

    final result = await controller.runVideoAction<int>(
      videoIds: [fixture.publicVideoId, fixture.privateVideoId],
      action: () async {
        wasUnlockedDuringAction = fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked;
        return 42;
      },
    );

    expect(result, 42);
    expect(fixture.auth.attempts, 1);
    expect(wasUnlockedDuringAction, isTrue);
    expect(
      fixture.container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
    expect(
      fixture.container.read(videoSelectionControllerProvider).selectedIds,
      {fixture.publicVideoId},
    );
  });

  test(
    'authentication cancellation aborts action and preserves public selection',
    () async {
      final fixture = await _PrivateLibraryPolicyFixture.create(
        authenticationResult: false,
      );
      addTearDown(fixture.dispose);
      await fixture.container
          .read(videoSelectionControllerProvider.notifier)
          .selectLoaded([fixture.publicVideoId, fixture.privateVideoId]);
      final controller = fixture.container.read(
        privateLibraryAccessControllerProvider.notifier,
      );
      var didRun = false;

      final result = await controller.runVideoAction<int>(
        videoIds: [fixture.publicVideoId, fixture.privateVideoId],
        action: () async {
          didRun = true;
          return 42;
        },
      );

      expect(result, isNull);
      expect(didRun, isFalse);
      expect(fixture.auth.attempts, 1);
      expect(
        fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked,
        isFalse,
      );
      expect(
        fixture.container.read(videoSelectionControllerProvider).selectedIds,
        {fixture.publicVideoId},
      );
    },
  );

  test('manual lock waits for an authorized action before relocking', () async {
    final fixture = await _PrivateLibraryPolicyFixture.create(
      authenticationResult: true,
    );
    addTearDown(fixture.dispose);
    final controller = fixture.container.read(
      privateLibraryAccessControllerProvider.notifier,
    );
    await controller.unlock();
    final actionStarted = Completer<void>();
    final finishAction = Completer<void>();

    final actionFuture = controller.runVideoAction<int>(
      videoIds: [fixture.privateVideoId],
      action: () async {
        actionStarted.complete();
        await finishAction.future;
        return 42;
      },
    );
    await actionStarted.future;
    var lockCompleted = false;
    final lockFuture = controller.lock().whenComplete(() {
      lockCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(lockCompleted, isFalse);
    expect(
      fixture.container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );

    finishAction.complete();
    expect(await actionFuture, 42);
    await lockFuture;
    expect(lockCompleted, isTrue);
    expect(
      fixture.container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  test('public-only action runs while locked without authentication', () async {
    final fixture = await _PrivateLibraryPolicyFixture.create(
      authenticationResult: false,
    );
    addTearDown(fixture.dispose);
    final controller = fixture.container.read(
      privateLibraryAccessControllerProvider.notifier,
    );

    final result = await controller.runVideoAction<int>(
      videoIds: [fixture.publicVideoId],
      action: () async => 42,
    );

    expect(result, 42);
    expect(fixture.auth.attempts, 0);
    expect(
      fixture.container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  test('private action reuses an existing unlocked session', () async {
    final fixture = await _PrivateLibraryPolicyFixture.create(
      authenticationResult: true,
    );
    addTearDown(fixture.dispose);
    final controller = fixture.container.read(
      privateLibraryAccessControllerProvider.notifier,
    );
    await controller.unlock();

    final result = await controller.runVideoAction<int>(
      videoIds: [fixture.privateVideoId],
      action: () async => 42,
    );

    expect(result, 42);
    expect(fixture.auth.attempts, 1);
    expect(
      fixture.container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );
    await controller.lock();
  });

  test('temporary access relocks when the private action throws', () async {
    final fixture = await _PrivateLibraryPolicyFixture.create(
      authenticationResult: true,
    );
    addTearDown(fixture.dispose);
    final controller = fixture.container.read(
      privateLibraryAccessControllerProvider.notifier,
    );

    await expectLater(
      controller.runVideoAction<int>(
        videoIds: [fixture.privateVideoId],
        action: () async => throw StateError('action failed'),
      ),
      throwsStateError,
    );

    expect(
      fixture.container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );
  });

  test(
    'overdue timeout waits for an authorized action before locking',
    () async {
      var now = DateTime(2026, 7, 20, 10);
      final fixture = await _PrivateLibraryPolicyFixture.create(
        authenticationResult: true,
        clock: () => now,
      );
      addTearDown(fixture.dispose);
      final controller = fixture.container.read(
        privateLibraryAccessControllerProvider.notifier,
      );
      await controller.unlock();
      final actionStarted = Completer<void>();
      final finishAction = Completer<void>();
      final actionFuture = controller.runVideoAction<int>(
        videoIds: [fixture.privateVideoId],
        action: () async {
          actionStarted.complete();
          await finishAction.future;
          return 42;
        },
      );
      await actionStarted.future;
      now = now.add(const Duration(minutes: 11));

      final timeoutLock = controller.enforceAutoLockDeadline();
      await Future<void>.delayed(Duration.zero);
      expect(
        fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked,
        isTrue,
      );

      finishAction.complete();
      expect(await actionFuture, 42);
      await timeoutLock;
      expect(
        fixture.container
            .read(privateLibraryAccessControllerProvider)
            .isUnlocked,
        isFalse,
      );
    },
  );
}

class _FakePrivateLibraryAuthService extends PrivateLibraryAuthService {
  _FakePrivateLibraryAuthService({required this.result});

  final bool result;
  int attempts = 0;

  @override
  Future<bool> authenticate() async {
    attempts += 1;
    return result;
  }
}

class _DeferredPrivateLibraryAuthService extends PrivateLibraryAuthService {
  final Completer<void> started = Completer<void>();
  final Completer<bool> _result = Completer<bool>();

  @override
  Future<bool> authenticate() {
    started.complete();
    return _result.future;
  }

  void complete(bool value) => _result.complete(value);
}

class _PrivateLibraryPolicyFixture {
  const _PrivateLibraryPolicyFixture({
    required this.db,
    required this.container,
    required this.auth,
    required this.publicFolderId,
    required this.privateFolderId,
    required this.publicVideoId,
    required this.privateVideoId,
  });

  final AppDatabase db;
  final ProviderContainer container;
  final _FakePrivateLibraryAuthService auth;
  final int publicFolderId;
  final int privateFolderId;
  final int publicVideoId;
  final int privateVideoId;

  static Future<_PrivateLibraryPolicyFixture> create({
    required bool authenticationResult,
    PrivateLibraryAutoLockClock? clock,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final publicFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Volumes/Public'),
    );
    final privateFolderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(
        path: '/Volumes/Private',
        isPrivate: const drift.Value(true),
      ),
    );
    final publicVideoId = await _insertPolicyVideo(
      db,
      folderId: publicFolderId,
      path: '/Volumes/Public/public.mp4',
    );
    final privateVideoId = await _insertPolicyVideo(
      db,
      folderId: privateFolderId,
      path: '/Volumes/Private/private.mp4',
    );
    final auth = _FakePrivateLibraryAuthService(result: authenticationResult);
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        privateLibraryAuthServiceProvider.overrideWithValue(auth),
        if (clock != null)
          privateLibraryAutoLockClockProvider.overrideWithValue(clock),
      ],
    );
    return _PrivateLibraryPolicyFixture(
      db: db,
      container: container,
      auth: auth,
      publicFolderId: publicFolderId,
      privateFolderId: privateFolderId,
      publicVideoId: publicVideoId,
      privateVideoId: privateVideoId,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

Future<int> _insertPolicyVideo(
  AppDatabase db, {
  required int folderId,
  required String path,
}) async {
  await db.videosDao.insertVideo(
    VideosCompanion.insert(folderId: folderId, absolutePath: path, title: path),
  );
  return (await db.videosDao.getVideoByPath(path))!.id;
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met.');
}
