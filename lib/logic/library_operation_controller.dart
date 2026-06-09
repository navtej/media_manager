import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryOperationState {
  const LibraryOperationState({this.isScanning = false, this.isMoving = false});

  final bool isScanning;
  final bool isMoving;

  bool get isBusy => isScanning || isMoving;

  LibraryOperationState copyWith({bool? isScanning, bool? isMoving}) {
    return LibraryOperationState(
      isScanning: isScanning ?? this.isScanning,
      isMoving: isMoving ?? this.isMoving,
    );
  }
}

class LibraryOperationController extends Notifier<LibraryOperationState> {
  @override
  LibraryOperationState build() => const LibraryOperationState();

  bool beginScan() {
    if (state.isMoving) {
      return false;
    }
    state = state.copyWith(isScanning: true);
    return true;
  }

  void endScan() {
    state = state.copyWith(isScanning: false);
  }

  bool beginMove() {
    if (state.isScanning || state.isMoving) {
      return false;
    }
    state = state.copyWith(isMoving: true);
    return true;
  }

  void endMove() {
    state = state.copyWith(isMoving: false);
  }
}

final libraryOperationControllerProvider =
    NotifierProvider<LibraryOperationController, LibraryOperationState>(
      LibraryOperationController.new,
    );
