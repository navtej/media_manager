import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/providers.dart';

enum DataCompactionStatus { completed, busy, failed }

class DataCompactionResult {
  const DataCompactionResult({
    required this.status,
    required this.beforeBytes,
    required this.afterBytes,
    required this.removedThumbnailCount,
    this.errorMessage,
  });

  final DataCompactionStatus status;
  final int beforeBytes;
  final int afterBytes;
  final int removedThumbnailCount;
  final String? errorMessage;

  int get reclaimedBytes => (beforeBytes - afterBytes).clamp(0, beforeBytes);
}

class DataCompactionService {
  const DataCompactionService({
    required AppDatabase database,
    required Directory applicationSupportDirectory,
  }) : _database = database,
       _applicationSupportDirectory = applicationSupportDirectory;

  final AppDatabase _database;
  final Directory _applicationSupportDirectory;

  Future<DataCompactionResult> compact() async {
    var stage = 'measuring the data folder';
    var beforeBytes = 0;
    var removedThumbnailCount = 0;
    try {
      beforeBytes = await directorySize(_applicationSupportDirectory);

      stage = 'checking the database';
      await _quickCheck();

      stage = 'removing unreferenced thumbnails';
      removedThumbnailCount = await _removeOrphanedThumbnails();

      stage = 'compacting the database';
      await _database.customStatement('VACUUM');
      if (await _usesWalJournal()) {
        await _database.customSelect('PRAGMA wal_checkpoint(TRUNCATE)').get();
      }

      stage = 'measuring the compacted data folder';
      final afterBytes = await directorySize(_applicationSupportDirectory);
      return DataCompactionResult(
        status: DataCompactionStatus.completed,
        beforeBytes: beforeBytes,
        afterBytes: afterBytes,
        removedThumbnailCount: removedThumbnailCount,
      );
    } catch (_) {
      return DataCompactionResult(
        status: DataCompactionStatus.failed,
        beforeBytes: beforeBytes,
        afterBytes: beforeBytes,
        removedThumbnailCount: removedThumbnailCount,
        errorMessage: 'Failed while $stage.',
      );
    }
  }

  Future<void> _quickCheck() async {
    final rows = await _database.customSelect('PRAGMA quick_check').get();
    if (rows.isEmpty ||
        rows.any((row) => row.read<String>('quick_check') != 'ok')) {
      throw StateError('SQLite quick_check failed');
    }
  }

  Future<bool> _usesWalJournal() async {
    final row = await _database.customSelect('PRAGMA journal_mode').getSingle();
    return row.read<String>('journal_mode').toLowerCase() == 'wal';
  }

  Future<int> _removeOrphanedThumbnails() async {
    final thumbnailDirectory = Directory(
      p.join(_applicationSupportDirectory.path, 'thumbnails'),
    );
    if (!await thumbnailDirectory.exists()) {
      return 0;
    }

    final rows = await _database
        .customSelect(
          'SELECT thumbnail_path FROM videos '
          'WHERE thumbnail_path IS NOT NULL '
          "AND length(trim(thumbnail_path)) > 0",
        )
        .get();
    final referencedPaths = rows
        .map(
          (row) => p.normalize(p.absolute(row.read<String>('thumbnail_path'))),
        )
        .toSet();

    var removed = 0;
    await for (final entity in thumbnailDirectory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final normalizedPath = p.normalize(p.absolute(entity.path));
      if (referencedPaths.contains(normalizedPath)) {
        continue;
      }
      await entity.delete();
      removed += 1;
    }
    return removed;
  }
}

Future<int> directorySize(Directory directory) async {
  if (!await directory.exists()) {
    return 0;
  }

  var total = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      total += await entity.length();
    }
  }
  return total;
}

typedef DataCompactionRunner = Future<DataCompactionResult> Function();

final dataCompactionRunnerProvider = Provider<DataCompactionRunner>(
  (ref) => () async {
    final applicationSupportDirectory = await getApplicationSupportDirectory();
    return DataCompactionService(
      database: ref.read(databaseProvider),
      applicationSupportDirectory: applicationSupportDirectory,
    ).compact();
  },
);
