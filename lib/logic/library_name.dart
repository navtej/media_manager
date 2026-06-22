import 'package:path/path.dart' as p;

import '../data/database.dart';

const libraryNameRequiredMessage = 'Library name is required.';
const libraryNameUniqueMessage = 'Library name must be unique.';

String libraryDisplayName(Folder folder) {
  final alias = folder.alias?.trim();
  if (alias != null && alias.isNotEmpty) {
    return alias;
  }
  return _pathDisplayName(folder.path);
}

String? validateLibraryName({
  required int folderId,
  required String name,
  required Iterable<Folder> folders,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return libraryNameRequiredMessage;
  }

  final candidateKey = _nameKey(trimmed);
  for (final folder in folders) {
    if (folder.id == folderId) {
      continue;
    }
    if (_nameKey(libraryDisplayName(folder)) == candidateKey) {
      return libraryNameUniqueMessage;
    }
  }

  return null;
}

String uniqueLibraryNameForPath(String path, Iterable<Folder> existingFolders) {
  final usedNames = existingFolders
      .map(libraryDisplayName)
      .map(_nameKey)
      .toSet();
  final baseName = _pathDisplayName(path);
  final parentName = _parentDisplayName(path);
  final candidates = <String>[
    baseName,
    if (parentName != null && _nameKey(parentName) != _nameKey(baseName))
      '$parentName / $baseName',
  ];

  for (final candidate in candidates) {
    if (!usedNames.contains(_nameKey(candidate))) {
      return candidate;
    }
  }

  var suffix = 2;
  while (true) {
    final candidate = '$baseName ($suffix)';
    if (!usedNames.contains(_nameKey(candidate))) {
      return candidate;
    }
    suffix += 1;
  }
}

String _pathDisplayName(String path) {
  final normalizedPath = p.normalize(path);
  final basename = p.basename(normalizedPath).trim();
  if (basename.isNotEmpty && basename != p.separator) {
    return basename;
  }
  final trimmedPath = path.trim();
  return trimmedPath.isEmpty ? 'Library' : trimmedPath;
}

String? _parentDisplayName(String path) {
  final normalizedPath = p.normalize(path);
  final parent = p.basename(p.dirname(normalizedPath)).trim();
  if (parent.isEmpty ||
      parent == '.' ||
      parent == p.separator ||
      parent == p.basename(normalizedPath)) {
    return null;
  }
  return parent;
}

String _nameKey(String name) => name.trim().toLowerCase();
