import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderAccessSession {
  const FolderAccessSession({
    required this.path,
    required this.canAccess,
    required this.needsRepair,
    this.message,
  });

  final String path;
  final bool canAccess;
  final bool needsRepair;
  final String? message;
}

class FolderAccessService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.moviemanager/natural_language',
  );

  Future<String?> createBookmark(String path) async {
    if (!Platform.isMacOS) {
      return null;
    }

    try {
      return await _channel.invokeMethod<String>('createFolderBookmark', {
        'path': path,
      });
    } on PlatformException catch (e) {
      print("Failed to create folder bookmark: '${e.message}'.");
      return null;
    }
  }

  Future<FolderAccessSession> startAccessing({
    required String path,
    required String? bookmark,
  }) async {
    if (!Platform.isMacOS) {
      return FolderAccessSession(
        path: path,
        canAccess: await Directory(path).exists(),
        needsRepair: false,
      );
    }

    if (bookmark == null || bookmark.isEmpty) {
      return FolderAccessSession(
        path: path,
        canAccess: false,
        needsRepair: true,
        message:
            'Folder access needs repair. Reselect this folder in Settings.',
      );
    }

    try {
      final canAccess = await _channel.invokeMethod<bool>(
        'startAccessingFolder',
        {'path': path, 'bookmark': bookmark},
      );
      return FolderAccessSession(
        path: path,
        canAccess: canAccess ?? false,
        needsRepair: canAccess != true,
        message: canAccess == true
            ? null
            : 'Folder access needs repair. Reselect this folder in Settings.',
      );
    } on PlatformException catch (e) {
      print("Failed to access folder bookmark: '${e.message}'.");
      return FolderAccessSession(
        path: path,
        canAccess: false,
        needsRepair: true,
        message:
            'Folder access needs repair. Reselect this folder in Settings.',
      );
    }
  }

  Future<void> stopAccessing({
    required String path,
    required String? bookmark,
  }) async {
    if (!Platform.isMacOS || bookmark == null || bookmark.isEmpty) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('stopAccessingFolder', {'path': path});
    } on PlatformException catch (e) {
      print("Failed to stop folder access: '${e.message}'.");
    }
  }
}

final folderAccessServiceProvider = Provider((ref) => FolderAccessService());
