import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/private_library_controller.dart';

class PrivateLibraryAutoLockLifecycle extends ConsumerStatefulWidget {
  const PrivateLibraryAutoLockLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PrivateLibraryAutoLockLifecycle> createState() =>
      _PrivateLibraryAutoLockLifecycleState();
}

class _PrivateLibraryAutoLockLifecycleState
    extends ConsumerState<PrivateLibraryAutoLockLifecycle> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onResume: () => ref
          .read(privateLibraryAccessControllerProvider.notifier)
          .enforceAutoLockDeadline(),
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
