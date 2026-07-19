import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const libraryAccessRepairMessage =
    'Folder access needs repair. Reselect this folder in Settings.';

class LibraryAccessNeedsRepairException implements Exception {
  const LibraryAccessNeedsRepairException(this.path);

  final String path;
  String get message => libraryAccessRepairMessage;

  @override
  String toString() => message;
}

class LibraryAccessRequest {
  const LibraryAccessRequest({required this.path, required this.bookmark});

  final String path;
  final String? bookmark;
}

abstract class LibraryAccessAdapter {
  Future<String?> createBookmark(String path);

  Future<bool> startAccessing({required String path, required String bookmark});

  Future<void> stopAccessing(String path);
}

class MethodChannelLibraryAccessAdapter implements LibraryAccessAdapter {
  MethodChannelLibraryAccessAdapter({MethodChannel? channel, bool? isMacOS})
    : _channel = channel ?? _defaultChannel,
      _isMacOS = isMacOS ?? Platform.isMacOS;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.example.moviemanager/natural_language',
  );

  final MethodChannel _channel;
  final bool _isMacOS;

  @override
  Future<String?> createBookmark(String path) async {
    if (!_isMacOS) {
      return null;
    }

    try {
      return await _channel.invokeMethod<String>('createFolderBookmark', {
        'path': path,
      });
    } on PlatformException catch (error) {
      print("Failed to create folder bookmark: '${error.message}'.");
      return null;
    }
  }

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async {
    if (!_isMacOS) {
      return Directory(path).exists();
    }

    try {
      return await _channel.invokeMethod<bool>('startAccessingFolder', {
            'path': path,
            'bookmark': bookmark,
          }) ??
          false;
    } on PlatformException catch (error) {
      print("Failed to access folder bookmark: '${error.message}'.");
      return false;
    }
  }

  @override
  Future<void> stopAccessing(String path) async {
    if (!_isMacOS) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('stopAccessingFolder', {'path': path});
    } on PlatformException catch (error) {
      print("Failed to stop folder access: '${error.message}'.");
    }
  }
}

class LibraryAccessService {
  LibraryAccessService({LibraryAccessAdapter? adapter})
    : _adapter = adapter ?? MethodChannelLibraryAccessAdapter();

  final LibraryAccessAdapter _adapter;
  final Map<String, _ActiveLibraryAccess> _active = {};
  final Map<String, Future<_ActiveLibraryAccess?>> _acquiring = {};
  final Map<String, Future<void>> _releasing = {};

  Future<String?> createBookmark(String path) => _adapter.createBookmark(path);

  Future<T> withAccess<T>({
    required LibraryAccessRequest library,
    required FutureOr<T> Function() action,
  }) async {
    final lease = await _acquire(library);
    try {
      return await Future<T>.sync(action);
    } finally {
      await lease.release();
    }
  }

  Future<T> withAccessToAll<T>({
    required Iterable<LibraryAccessRequest> libraries,
    required FutureOr<T> Function() action,
  }) async {
    final uniqueLibraries = <String, LibraryAccessRequest>{};
    for (final library in libraries) {
      uniqueLibraries[library.path] = library;
    }

    final leases = <_LibraryAccessLease>[];
    try {
      for (final library in uniqueLibraries.values) {
        leases.add(await _acquire(library));
      }
      return await Future<T>.sync(action);
    } finally {
      for (final lease in leases.reversed) {
        await lease.release();
      }
    }
  }

  Future<_LibraryAccessLease> _acquire(LibraryAccessRequest library) async {
    final path = library.path;
    final bookmark = library.bookmark;
    if (bookmark == null || bookmark.isEmpty) {
      throw LibraryAccessNeedsRepairException(path);
    }

    while (true) {
      final release = _releasing[path];
      if (release == null) {
        break;
      }
      await release;
    }

    final active = _active[path];
    if (active != null) {
      active.ownerCount += 1;
      return _LibraryAccessLease(this, active);
    }

    var acquisition = _acquiring[path];
    if (acquisition == null) {
      acquisition = _startNativeAccess(library);
      _acquiring[path] = acquisition;
    }

    _ActiveLibraryAccess? acquired;
    try {
      acquired = await acquisition;
    } finally {
      if (identical(_acquiring[path], acquisition)) {
        _acquiring.remove(path);
      }
    }
    if (acquired == null) {
      throw LibraryAccessNeedsRepairException(path);
    }

    acquired.ownerCount += 1;
    return _LibraryAccessLease(this, acquired);
  }

  Future<_ActiveLibraryAccess?> _startNativeAccess(
    LibraryAccessRequest library,
  ) async {
    final bool canAccess;
    try {
      canAccess = await _adapter.startAccessing(
        path: library.path,
        bookmark: library.bookmark!,
      );
    } catch (error) {
      print('Failed to acquire Library access for ${library.path}: $error');
      return null;
    }
    if (!canAccess) {
      return null;
    }

    final active = _ActiveLibraryAccess(library.path);
    _active[library.path] = active;
    return active;
  }

  Future<void> _release(_ActiveLibraryAccess access) async {
    if (!identical(_active[access.path], access) || access.ownerCount <= 0) {
      return;
    }

    access.ownerCount -= 1;
    if (access.ownerCount > 0) {
      return;
    }

    _active.remove(access.path);
    final completion = Completer<void>();
    final release = completion.future;
    _releasing[access.path] = release;
    try {
      await _adapter.stopAccessing(access.path);
    } finally {
      if (identical(_releasing[access.path], release)) {
        _releasing.remove(access.path);
      }
      completion.complete();
    }
  }
}

class _ActiveLibraryAccess {
  _ActiveLibraryAccess(this.path);

  final String path;
  int ownerCount = 0;
}

class _LibraryAccessLease {
  _LibraryAccessLease(this._service, this._access);

  final LibraryAccessService _service;
  final _ActiveLibraryAccess _access;
  bool _released = false;

  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    await _service._release(_access);
  }
}

final libraryAccessServiceProvider = Provider((ref) => LibraryAccessService());
