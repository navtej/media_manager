class FolderStorageStatus {
  const FolderStorageStatus({
    required this.isRemovableStorage,
    required this.needsRepair,
  });

  factory FolderStorageStatus.fromFolder({
    required String path,
    required String? securityScopedBookmark,
  }) {
    final needsRepair =
        securityScopedBookmark == null || securityScopedBookmark.isEmpty;

    return FolderStorageStatus(
      isRemovableStorage: path.startsWith('/Volumes/'),
      needsRepair: needsRepair,
    );
  }

  final bool isRemovableStorage;
  final bool needsRepair;

  String? get statusLabel {
    if (needsRepair) {
      return 'Access repair required';
    }
    if (isRemovableStorage) {
      return 'Removable storage';
    }
    return null;
  }
}
