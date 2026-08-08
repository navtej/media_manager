import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/providers.dart';
import '../data/tables.dart';
import '../services/library_access_service.dart';
import '../services/private_library_auth_service.dart';
import 'library_name.dart';
import 'library_groups.dart';

enum ManagedLibraryAddStatus { created, existing, bookmarkRefreshed }

class ManagedLibraryAddResult {
  const ManagedLibraryAddResult({required this.status, this.folder});

  final ManagedLibraryAddStatus status;
  final Folder? folder;
}

enum ManagedLibraryRenameStatus {
  renamed,
  unchanged,
  blankName,
  duplicateName,
  notFound,
}

class ManagedLibraryRenameResult {
  const ManagedLibraryRenameResult({required this.status, this.folder});

  final ManagedLibraryRenameStatus status;
  final Folder? folder;
}

enum ManagedLibraryPrivacyStatus {
  madePrivate,
  madePublic,
  unchanged,
  authenticationCancelled,
  notFound,
}

class ManagedLibraryPrivacyResult {
  const ManagedLibraryPrivacyResult({required this.status, this.folder});

  final ManagedLibraryPrivacyStatus status;
  final Folder? folder;
}

enum ManagedLibraryGroupStatus {
  created,
  assigned,
  removed,
  unchanged,
  blankName,
  duplicateName,
  defaultGroup,
  groupNotFound,
  folderNotFound,
}

class ManagedLibraryGroupResult {
  const ManagedLibraryGroupResult({
    required this.status,
    this.groupName,
    this.folder,
  });

  final ManagedLibraryGroupStatus status;
  final String? groupName;
  final Folder? folder;
}

enum ManagedLibraryRepairStatus {
  repaired,
  pathMismatch,
  bookmarkUnavailable,
  notFound,
}

class ManagedLibraryRepairResult {
  const ManagedLibraryRepairResult({required this.status, this.folder});

  final ManagedLibraryRepairStatus status;
  final Folder? folder;
}

enum ManagedLibraryRemoveStatus { removed, notFound }

class ManagedLibraryRemoveResult {
  const ManagedLibraryRemoveResult({
    required this.status,
    this.folder,
    this.removedVideoCount = 0,
  });

  final ManagedLibraryRemoveStatus status;
  final Folder? folder;
  final int removedVideoCount;
}

class ManagedLibraryService {
  ManagedLibraryService({
    required FoldersDao foldersDao,
    required LibraryGroupsDao libraryGroupsDao,
    required Future<int> Function(int folderId) catalogVideoCount,
    required LibraryAccessService libraryAccessService,
    required PrivateLibraryAuthService privateLibraryAuthService,
  }) : _foldersDao = foldersDao,
       _libraryGroupsDao = libraryGroupsDao,
       _catalogVideoCount = catalogVideoCount,
       _libraryAccessService = libraryAccessService,
       _privateLibraryAuthService = privateLibraryAuthService;

  final FoldersDao _foldersDao;
  final LibraryGroupsDao _libraryGroupsDao;
  final Future<int> Function(int folderId) _catalogVideoCount;
  final LibraryAccessService _libraryAccessService;
  final PrivateLibraryAuthService _privateLibraryAuthService;
  Future<void> _mutationTail = Future<void>.value();

  Future<ManagedLibraryAddResult> addOrRefresh(String path) {
    return _serialize(() => _addOrRefresh(path));
  }

  Future<ManagedLibraryAddResult> _addOrRefresh(String path) async {
    await _ensureDefaultGroup();
    final normalizedPath = _normalizePath(path);
    final bookmark = await _libraryAccessService.createBookmark(normalizedPath);
    final folders = await _foldersDao.getAllFolders();
    final existing = _findByPath(folders, normalizedPath);

    if (existing != null) {
      return _refreshExisting(existing, bookmark);
    }

    final id = await _foldersDao.insertFolder(
      FoldersCompanion(
        path: drift.Value(normalizedPath),
        alias: drift.Value(uniqueLibraryNameForPath(normalizedPath, folders)),
        groupName: const drift.Value(defaultLibraryGroupName),
        securityScopedBookmark: drift.Value(bookmark),
      ),
    );

    if (id == 0) {
      final refetched = await _foldersDao.getAllFolders();
      final concurrentlyAdded = _findByPath(refetched, normalizedPath);
      if (concurrentlyAdded == null) {
        throw StateError('Could not add managed Library at $normalizedPath.');
      }
      return _refreshExisting(concurrentlyAdded, bookmark);
    }

    final folder = await _foldersDao.getFolderById(id);
    if (folder == null) {
      throw StateError('Could not load managed Library $id after creation.');
    }
    return ManagedLibraryAddResult(
      status: ManagedLibraryAddStatus.created,
      folder: folder,
    );
  }

  Future<int> normalizeNames() {
    return _serialize(_normalizeNames);
  }

  Future<int> _normalizeNames() async {
    final folders = await _foldersDao.getAllFolders()
      ..sort((a, b) => a.id.compareTo(b.id));
    final normalizedFolders = <Folder>[];
    var updateCount = 0;

    for (final folder in folders) {
      final trimmedName = folder.alias?.trim() ?? '';
      final validation = validateLibraryName(
        folderId: folder.id,
        name: trimmedName,
        folders: normalizedFolders,
      );
      final normalizedName = validation == null
          ? trimmedName
          : uniqueLibraryNameForPath(folder.path, normalizedFolders);

      if (folder.alias != normalizedName) {
        await _foldersDao.updateFolderName(folder.id, normalizedName);
        updateCount += 1;
      }
      normalizedFolders.add(
        folder.copyWith(alias: drift.Value(normalizedName)),
      );
    }

    return updateCount;
  }

  Future<ManagedLibraryRenameResult> rename(int folderId, String name) {
    return _serialize(() => _rename(folderId, name));
  }

  Future<ManagedLibraryRenameResult> _rename(int folderId, String name) async {
    final folders = await _foldersDao.getAllFolders();
    final folder = _findById(folders, folderId);
    if (folder == null) {
      return const ManagedLibraryRenameResult(
        status: ManagedLibraryRenameStatus.notFound,
      );
    }

    final trimmedName = name.trim();
    final validation = validateLibraryName(
      folderId: folderId,
      name: trimmedName,
      folders: folders,
    );
    if (validation == libraryNameRequiredMessage) {
      return ManagedLibraryRenameResult(
        status: ManagedLibraryRenameStatus.blankName,
        folder: folder,
      );
    }
    if (validation == libraryNameUniqueMessage) {
      return ManagedLibraryRenameResult(
        status: ManagedLibraryRenameStatus.duplicateName,
        folder: folder,
      );
    }

    if (folder.alias == trimmedName) {
      return ManagedLibraryRenameResult(
        status: ManagedLibraryRenameStatus.unchanged,
        folder: folder,
      );
    }

    await _foldersDao.updateFolderName(folderId, trimmedName);
    return ManagedLibraryRenameResult(
      status: ManagedLibraryRenameStatus.renamed,
      folder: folder.copyWith(alias: drift.Value(trimmedName)),
    );
  }

  Future<ManagedLibraryPrivacyResult> setPrivacy(
    int folderId, {
    required bool isPrivate,
  }) {
    return _serialize(() => _setPrivacy(folderId, isPrivate: isPrivate));
  }

  Future<ManagedLibraryGroupResult> addGroup(String name) {
    return _serialize(() => _addGroup(name));
  }

  Future<ManagedLibraryGroupResult> _addGroup(String name) async {
    await _ensureDefaultGroup();
    final normalizedName = normalizeLibraryGroupName(name);
    if (normalizedName.isEmpty) {
      return const ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.blankName,
      );
    }

    final groups = await _libraryGroupsDao.getAllGroups();
    if (groups.any(
      (group) => sameLibraryGroupName(group.name, normalizedName),
    )) {
      return ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.duplicateName,
        groupName: normalizedName,
      );
    }

    final id = await _libraryGroupsDao.insertGroup(
      LibraryGroupsCompanion(name: drift.Value(normalizedName)),
    );
    if (id == 0) {
      return ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.duplicateName,
        groupName: normalizedName,
      );
    }
    return ManagedLibraryGroupResult(
      status: ManagedLibraryGroupStatus.created,
      groupName: normalizedName,
    );
  }

  Future<ManagedLibraryGroupResult> assignGroup(int folderId, String name) {
    return _serialize(() => _assignGroup(folderId, name));
  }

  Future<ManagedLibraryGroupResult> _assignGroup(
    int folderId,
    String name,
  ) async {
    await _ensureDefaultGroup();
    final folder = await _foldersDao.getFolderById(folderId);
    if (folder == null) {
      return const ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.folderNotFound,
      );
    }

    final group = _findGroup(await _libraryGroupsDao.getAllGroups(), name);
    if (group == null) {
      return ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.groupNotFound,
        folder: folder,
      );
    }
    if (sameLibraryGroupName(libraryGroupName(folder), group.name)) {
      return ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.unchanged,
        groupName: group.name,
        folder: folder,
      );
    }

    await _foldersDao.updateFolderGroup(folderId, group.name);
    return ManagedLibraryGroupResult(
      status: ManagedLibraryGroupStatus.assigned,
      groupName: group.name,
      folder: folder.copyWith(groupName: drift.Value(group.name)),
    );
  }

  Future<ManagedLibraryGroupResult> removeGroup(String name) {
    return _serialize(() => _removeGroup(name));
  }

  Future<ManagedLibraryGroupResult> _removeGroup(String name) async {
    await _ensureDefaultGroup();
    final normalizedName = normalizeLibraryGroupName(name);
    if (sameLibraryGroupName(normalizedName, defaultLibraryGroupName)) {
      return const ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.defaultGroup,
        groupName: defaultLibraryGroupName,
      );
    }

    final group = _findGroup(
      await _libraryGroupsDao.getAllGroups(),
      normalizedName,
    );
    if (group == null) {
      return ManagedLibraryGroupResult(
        status: ManagedLibraryGroupStatus.groupNotFound,
        groupName: normalizedName,
      );
    }

    await _foldersDao.moveFoldersToGroup(group.name, defaultLibraryGroupName);
    await _libraryGroupsDao.deleteGroup(group.name);
    return ManagedLibraryGroupResult(
      status: ManagedLibraryGroupStatus.removed,
      groupName: group.name,
    );
  }

  Future<ManagedLibraryPrivacyResult> _setPrivacy(
    int folderId, {
    required bool isPrivate,
  }) async {
    final folder = await _foldersDao.getFolderById(folderId);
    if (folder == null) {
      return const ManagedLibraryPrivacyResult(
        status: ManagedLibraryPrivacyStatus.notFound,
      );
    }
    if (folder.isPrivate == isPrivate) {
      return ManagedLibraryPrivacyResult(
        status: ManagedLibraryPrivacyStatus.unchanged,
        folder: folder,
      );
    }

    if (folder.isPrivate && !isPrivate) {
      final authenticated = await _privateLibraryAuthService.authenticate();
      if (!authenticated) {
        return ManagedLibraryPrivacyResult(
          status: ManagedLibraryPrivacyStatus.authenticationCancelled,
          folder: folder,
        );
      }
    }

    await _foldersDao.updateFolderPrivacy(folderId, isPrivate);
    return ManagedLibraryPrivacyResult(
      status: isPrivate
          ? ManagedLibraryPrivacyStatus.madePrivate
          : ManagedLibraryPrivacyStatus.madePublic,
      folder: folder.copyWith(isPrivate: isPrivate),
    );
  }

  Future<ManagedLibraryRepairResult> repairAccess(
    int folderId,
    String selectedPath,
  ) {
    return _serialize(() => _repairAccess(folderId, selectedPath));
  }

  Future<ManagedLibraryRepairResult> _repairAccess(
    int folderId,
    String selectedPath,
  ) async {
    final folder = await _foldersDao.getFolderById(folderId);
    if (folder == null) {
      return const ManagedLibraryRepairResult(
        status: ManagedLibraryRepairStatus.notFound,
      );
    }

    final normalizedSelectedPath = _normalizePath(selectedPath);
    if (_normalizePath(folder.path) != normalizedSelectedPath) {
      return ManagedLibraryRepairResult(
        status: ManagedLibraryRepairStatus.pathMismatch,
        folder: folder,
      );
    }

    final bookmark = await _libraryAccessService.createBookmark(
      normalizedSelectedPath,
    );
    if (bookmark == null || bookmark.isEmpty) {
      return ManagedLibraryRepairResult(
        status: ManagedLibraryRepairStatus.bookmarkUnavailable,
        folder: folder,
      );
    }

    await _foldersDao.updateFolderBookmark(folderId, bookmark);
    return ManagedLibraryRepairResult(
      status: ManagedLibraryRepairStatus.repaired,
      folder: folder.copyWith(securityScopedBookmark: drift.Value(bookmark)),
    );
  }

  Future<ManagedLibraryRemoveResult> remove(int folderId) {
    return _serialize(() => _remove(folderId));
  }

  Future<ManagedLibraryRemoveResult> _remove(int folderId) async {
    final folder = await _foldersDao.getFolderById(folderId);
    if (folder == null) {
      return const ManagedLibraryRemoveResult(
        status: ManagedLibraryRemoveStatus.notFound,
      );
    }

    final videoCount = await _catalogVideoCount(folderId);
    await _foldersDao.deleteFolder(folderId);
    return ManagedLibraryRemoveResult(
      status: ManagedLibraryRemoveStatus.removed,
      folder: folder,
      removedVideoCount: videoCount,
    );
  }

  Future<ManagedLibraryAddResult> _refreshExisting(
    Folder existing,
    String? bookmark,
  ) async {
    if (bookmark == null ||
        bookmark.isEmpty ||
        bookmark == existing.securityScopedBookmark) {
      return ManagedLibraryAddResult(
        status: ManagedLibraryAddStatus.existing,
        folder: existing,
      );
    }

    await _foldersDao.updateFolderBookmark(existing.id, bookmark);
    return ManagedLibraryAddResult(
      status: ManagedLibraryAddStatus.bookmarkRefreshed,
      folder: existing.copyWith(securityScopedBookmark: drift.Value(bookmark)),
    );
  }

  Future<void> _ensureDefaultGroup() async {
    final groups = await _libraryGroupsDao.getAllGroups();
    if (!groups.any(
      (group) => sameLibraryGroupName(group.name, defaultLibraryGroupName),
    )) {
      await _libraryGroupsDao.insertGroup(
        const LibraryGroupsCompanion(
          name: drift.Value(defaultLibraryGroupName),
        ),
      );
    }
  }

  Folder? _findByPath(Iterable<Folder> folders, String path) {
    for (final folder in folders) {
      if (_normalizePath(folder.path) == path) {
        return folder;
      }
    }
    return null;
  }

  Folder? _findById(Iterable<Folder> folders, int id) {
    for (final folder in folders) {
      if (folder.id == id) {
        return folder;
      }
    }
    return null;
  }

  LibraryGroup? _findGroup(Iterable<LibraryGroup> groups, String name) {
    for (final group in groups) {
      if (sameLibraryGroupName(group.name, name)) {
        return group;
      }
    }
    return null;
  }

  Future<T> _serialize<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  String _normalizePath(String path) => p.normalize(path.trim());
}

final managedLibraryServiceProvider = Provider<ManagedLibraryService>((ref) {
  return ManagedLibraryService(
    foldersDao: ref.watch(foldersDaoProvider),
    libraryGroupsDao: ref.watch(libraryGroupsDaoProvider),
    catalogVideoCount: (folderId) async {
      final videos = await ref
          .read(videosDaoProvider)
          .getVideosByFolder(folderId);
      return videos.length;
    },
    libraryAccessService: ref.watch(libraryAccessServiceProvider),
    privateLibraryAuthService: ref.watch(privateLibraryAuthServiceProvider),
  );
});
