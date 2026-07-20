import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LibraryOperation { idle, scanning, moving, cleaning }

class LibraryOperationState {
  const LibraryOperationState([this.operation = LibraryOperation.idle]);

  final LibraryOperation operation;

  bool get isScanning => operation == LibraryOperation.scanning;
  bool get isMoving => operation == LibraryOperation.moving;
  bool get isCleaning => operation == LibraryOperation.cleaning;
  bool get isBusy => operation != LibraryOperation.idle;
}

class LibraryOperationController extends Notifier<LibraryOperationState> {
  @override
  LibraryOperationState build() => const LibraryOperationState();

  bool beginScan() {
    if (state.isBusy) {
      return false;
    }
    state = const LibraryOperationState(LibraryOperation.scanning);
    return true;
  }

  void endScan() {
    if (state.isScanning) {
      state = const LibraryOperationState();
    }
  }

  bool beginMove() {
    if (state.isBusy) {
      return false;
    }
    state = const LibraryOperationState(LibraryOperation.moving);
    return true;
  }

  void endMove() {
    if (state.isMoving) {
      state = const LibraryOperationState();
    }
  }

  bool beginCleanup() {
    if (state.isBusy) {
      return false;
    }
    state = const LibraryOperationState(LibraryOperation.cleaning);
    return true;
  }

  void endCleanup() {
    if (state.isCleaning) {
      state = const LibraryOperationState();
    }
  }
}

final libraryOperationControllerProvider =
    NotifierProvider<LibraryOperationController, LibraryOperationState>(
      LibraryOperationController.new,
    );
