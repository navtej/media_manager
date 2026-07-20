import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/providers.dart';
import 'library_access_service.dart';

class EmptyFolderCleanupResult {
  const EmptyFolderCleanupResult({
    required this.librariesAttempted,
    required this.directoriesRemoved,
    required this.libraryFailures,
    required this.directoryFailures,
  });

  final int librariesAttempted;
  final int directoriesRemoved;
  final int libraryFailures;
  final int directoryFailures;

  String get summary =>
      'Removed $directoriesRemoved empty folders; '
      '$libraryFailures Libraries and $directoryFailures directories failed.';
}

class EmptyFolderCleanupService {
  const EmptyFolderCleanupService({
    required FoldersDao foldersDao,
    required LibraryAccessService libraryAccessService,
  }) : _foldersDao = foldersDao,
       _libraryAccessService = libraryAccessService;

  final FoldersDao _foldersDao;
  final LibraryAccessService _libraryAccessService;

  Future<EmptyFolderCleanupResult> cleanup() async {
    final libraries = await _foldersDao.getAllFolders();
    var directoriesRemoved = 0;
    var libraryFailures = 0;
    var directoryFailures = 0;

    for (final library in libraries) {
      try {
        final result = await _libraryAccessService.withAccess(
          library: LibraryAccessRequest(
            path: library.path,
            bookmark: library.securityScopedBookmark,
          ),
          action: () => _cleanupLibrary(library),
        );
        directoriesRemoved += result.removed;
        directoryFailures += result.failed;
      } catch (error) {
        libraryFailures += 1;
        print(
          'Empty-folder cleanup failed for Library ${library.path}: $error',
        );
      }
    }

    return EmptyFolderCleanupResult(
      librariesAttempted: libraries.length,
      directoriesRemoved: directoriesRemoved,
      libraryFailures: libraryFailures,
      directoryFailures: directoryFailures,
    );
  }

  Future<_LibraryCleanupResult> _cleanupLibrary(Folder library) async {
    final rootPath = p.normalize(p.absolute(library.path));
    final rootType = await FileSystemEntity.type(rootPath, followLinks: false);
    if (rootType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Library root is not an accessible directory',
        rootPath,
      );
    }

    final candidates = <String>[];
    final pending = <String>[rootPath];
    var failed = 0;
    while (pending.isNotEmpty) {
      final currentPath = pending.removeLast();
      try {
        final currentType = await FileSystemEntity.type(
          currentPath,
          followLinks: false,
        );
        if (currentType != FileSystemEntityType.directory) {
          continue;
        }
        await for (final entity in Directory(
          currentPath,
        ).list(followLinks: false)) {
          final candidatePath = p.normalize(p.absolute(entity.path));
          if (entity is Directory && p.isWithin(rootPath, candidatePath)) {
            candidates.add(candidatePath);
            pending.add(candidatePath);
          }
        }
      } catch (error) {
        if (currentPath == rootPath) {
          rethrow;
        }
        candidates.remove(currentPath);
        failed += 1;
        print(
          'Empty-folder cleanup could not inspect Library ${library.path} '
          'at $currentPath: $error',
        );
      }
    }
    candidates.sort((left, right) {
      final depth = p.split(right).length.compareTo(p.split(left).length);
      return depth != 0 ? depth : left.compareTo(right);
    });

    var removed = 0;
    for (final candidatePath in candidates) {
      try {
        final type = await FileSystemEntity.type(
          candidatePath,
          followLinks: false,
        );
        if (type != FileSystemEntityType.directory ||
            !p.isWithin(rootPath, candidatePath)) {
          continue;
        }
        final directory = Directory(candidatePath);
        if (await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
          removed += 1;
        }
      } catch (error) {
        failed += 1;
        print(
          'Empty-folder cleanup failed in Library ${library.path} '
          'at $candidatePath: $error',
        );
      }
    }
    return _LibraryCleanupResult(removed: removed, failed: failed);
  }
}

class _LibraryCleanupResult {
  const _LibraryCleanupResult({required this.removed, required this.failed});

  final int removed;
  final int failed;
}

final emptyFolderCleanupServiceProvider = Provider(
  (ref) => EmptyFolderCleanupService(
    foldersDao: ref.watch(foldersDaoProvider),
    libraryAccessService: ref.watch(libraryAccessServiceProvider),
  ),
);

typedef EmptyFolderCleanupRunner = Future<EmptyFolderCleanupResult> Function();

final emptyFolderCleanupRunnerProvider = Provider<EmptyFolderCleanupRunner>(
  (ref) => ref.watch(emptyFolderCleanupServiceProvider).cleanup,
);
