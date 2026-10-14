import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LibraryOperation { idle, scanning, moving, cleaning, versioning }

class LibraryOperationState {
  const LibraryOperationState([this.operation = LibraryOperation.idle]);

  final LibraryOperation operation;

  bool get isScanning => operation == LibraryOperation.scanning;
  bool get isMoving => operation == LibraryOperation.moving;
  bool get isCleaning => operation == LibraryOperation.cleaning;

  /// A short catalog/file update of a video's versions (finalizing a
  /// conversion, deleting a version or changing the primary).
  bool get isVersioning => operation == LibraryOperation.versioning;
  bool get isBusy => operation != LibraryOperation.idle;
}

class LibraryOperationController extends Notifier<LibraryOperationState> {
  final List<Completer<void>> _idleWaiters = [];

  @override
  LibraryOperationState build() => const LibraryOperationState();

  bool beginScan() => _begin(LibraryOperation.scanning);

  void endScan() => _end(LibraryOperation.scanning);

  bool beginMove() => _begin(LibraryOperation.moving);

  void endMove() => _end(LibraryOperation.moving);

  bool beginCleanup() => _begin(LibraryOperation.cleaning);

  void endCleanup() => _end(LibraryOperation.cleaning);

  bool beginVersioning() => _begin(LibraryOperation.versioning);

  void endVersioning() => _end(LibraryOperation.versioning);

  /// Runs [action] as an exclusive versioning operation, waiting (without
  /// polling) for any scan, move or cleanup to finish first. Not re-entrant:
  /// [action] must not call [runVersioning] again.
  Future<T> runVersioning<T>(Future<T> Function() action) async {
    while (!beginVersioning()) {
      final waiter = Completer<void>();
      _idleWaiters.add(waiter);
      await waiter.future;
    }
    try {
      return await action();
    } finally {
      endVersioning();
    }
  }

  bool _begin(LibraryOperation operation) {
    if (state.isBusy) {
      return false;
    }
    state = LibraryOperationState(operation);
    return true;
  }

  void _end(LibraryOperation operation) {
    if (state.operation != operation) {
      return;
    }
    state = const LibraryOperationState();
    // Listeners (e.g. a pending scan) may claim the idle state synchronously;
    // woken waiters re-check and wait again if so.
    final waiters = List.of(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete();
    }
  }
}

final libraryOperationControllerProvider =
    NotifierProvider<LibraryOperationController, LibraryOperationState>(
      LibraryOperationController.new,
    );
