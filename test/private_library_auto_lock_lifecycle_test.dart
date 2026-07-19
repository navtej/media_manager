import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/private_library_controller.dart';
import 'package:movie_manager/services/private_library_auth_service.dart';
import 'package:movie_manager/ui/widgets/private_library_auto_lock_lifecycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app resume enforces an overdue private-library deadline', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'privateLibraryAutoLockMinutes': 10,
    });
    var now = DateTime(2026, 7, 19, 10);
    final container = ProviderContainer(
      overrides: [
        privateLibraryAuthServiceProvider.overrideWithValue(
          _SuccessfulPrivateLibraryAuthService(),
        ),
        privateLibraryAutoLockClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PrivateLibraryAutoLockLifecycle(child: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    await container
        .read(privateLibraryAccessControllerProvider.notifier)
        .unlock();
    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isTrue,
    );

    now = now.add(const Duration(minutes: 11));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      container.read(privateLibraryAccessControllerProvider).isUnlocked,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _SuccessfulPrivateLibraryAuthService extends PrivateLibraryAuthService {
  @override
  Future<bool> authenticate() async => true;
}
