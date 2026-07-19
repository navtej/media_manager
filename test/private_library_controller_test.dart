import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/logic/settings_provider.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    'locking removes selected private libraries but preserves public ones',
    () async {
      final container = ProviderContainer(
        overrides: [
          publicLibraryFolderIdsProvider.overrideWithValue(const {1}),
          privateLibraryAuthServiceProvider.overrideWithValue(
            _FakePrivateLibraryAuthService(result: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      final selected = container.read(
        selectedLibraryFoldersControllerProvider.notifier,
      );
      selected.toggle(1);
      selected.toggle(2);

      final controller = container.read(
        privateLibraryAccessControllerProvider.notifier,
      );
      await controller.unlock();
      controller.lock();

      expect(container.read(selectedLibraryFoldersControllerProvider), {1});
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
