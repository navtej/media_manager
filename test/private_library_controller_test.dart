import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';

void main() {
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
