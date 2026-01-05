import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables.dart';

part 'database.g.dart';

enum SortOption { title, duration, addedAt, size }
enum SortDirection { asc, desc }

@DriftDatabase(tables: [Folders, Videos, Tags], daos: [VideosDao, FoldersDao, TagsDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) => m.createAll(),
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(videos, videos.isFavorite);
        }
        if (from < 3) {
          await m.addColumn(videos, videos.fileCreatedAt);
        }
        if (from < 4) {
          await m.addColumn(videos, videos.aiProcessed);
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> clearAllData() async {
    await transaction(() async {
      await customStatement('DELETE FROM tags');
      await customStatement('DELETE FROM videos');
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'movie_manager.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

@DriftAccessor(tables: [Folders])
class FoldersDao extends DatabaseAccessor<AppDatabase> with _$FoldersDaoMixin {
  FoldersDao(AppDatabase db) : super(db);

  Future<List<Folder>> getAllFolders() => select(folders).get();
  Stream<List<Folder>> watchAllFolders() => select(folders).watch();
  Future<int> insertFolder(FoldersCompanion folder) => into(folders).insert(folder, mode: InsertMode.insertOrIgnore);
  Future<void> deleteFolder(int id) => (delete(folders)..where((tbl) => tbl.id.equals(id))).go();
}

@DriftAccessor(tables: [Videos, Tags]) // Access Tags for join queries if needed
class VideosDao extends DatabaseAccessor<AppDatabase> with _$VideosDaoMixin {
  VideosDao(AppDatabase db) : super(db);

  Future<List<Video>> getAllVideos() => select(videos).get();
  
  Future<List<Video>> getVideosByFolder(int folderId) {
    return (select(videos)..where((t) => t.folderId.equals(folderId))).get();
  }

  Future<Video?> getVideoById(int id) {
    return (select(videos)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Video?> getVideoByPath(String path) {
    return (select(videos)..where((t) => t.absolutePath.equals(path))).getSingleOrNull();
  }
  
  Future<int> insertVideo(VideosCompanion video) => into(videos).insert(video, mode: InsertMode.insertOrIgnore);
  
  Future<void> updateVideoStatus(int id, bool isOffline) {
    return (update(videos)..where((t) => t.id.equals(id))).write(VideosCompanion(isOffline: Value(isOffline)));
  }

  Future<void> toggleFavorite(int id, bool currentStatus) {
    return (update(videos)..where((t) => t.id.equals(id))).write(VideosCompanion(isFavorite: Value(!currentStatus)));
  }

  Future<void> deleteVideo(int id, {bool deleteFile = true}) async {
    final video = await (select(videos)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (video != null) {
      if (deleteFile) {
        final file = File(video.absolutePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await (delete(videos)..where((t) => t.id.equals(id))).go();
    }
  }

  Future<void> deleteVideosByIds(List<int> ids) {
    return (delete(videos)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> updateVideoSize(int id, int size) {
    return (update(videos)..where((t) => t.id.equals(id))).write(VideosCompanion(size: Value(size)));
  }

  Future<void> updateVideoCreationDate(int id, DateTime date) {
    return (update(videos)..where((t) => t.id.equals(id))).write(VideosCompanion(fileCreatedAt: Value(date)));
  }

  Future<void> updateVideoAiProcessed(int id, bool aiProcessed) {
    return (update(videos)..where((t) => t.id.equals(id))).write(VideosCompanion(aiProcessed: Value(aiProcessed)));
  }

  Future<void> updateVideosAiProcessedBatch(List<int> ids, bool aiProcessed) {
    return (update(videos)..where((t) => t.id.isIn(ids))).write(VideosCompanion(aiProcessed: Value(aiProcessed)));
  }

  Future<void> insertVideosBatch(List<VideosCompanion> companions) {
    return batch((b) {
      b.insertAll(videos, companions, mode: InsertMode.insertOrIgnore);
    });
  }

  Stream<List<Video>> watchAllVideos({
    bool favoritesOnly = false, 
    SortOption sortBy = SortOption.title,
    SortDirection direction = SortDirection.asc,
  }) {
    final query = select(videos);
    if (favoritesOnly) {
      query.where((t) => t.isFavorite.equals(true));
    }
    
    final mode = direction == SortDirection.asc ? OrderingMode.asc : OrderingMode.desc;
    
    query.orderBy([
      (t) {
        if (sortBy == SortOption.duration) {
          return OrderingTerm(expression: t.duration, mode: mode);
        } else if (sortBy == SortOption.addedAt) {
          return OrderingTerm(expression: t.fileCreatedAt, mode: mode);
        } else if (sortBy == SortOption.size) {
          return OrderingTerm(expression: t.size, mode: mode);
        } else {
          return OrderingTerm(expression: t.title, mode: mode);
        }
      }
    ]);
    
    return query.watch();
  }

  Stream<List<Video>> searchVideos({
    List<String> tagsAny = const [], // OR logic (Primary)
    List<String> tagsAll = const [], // AND logic (Secondary)
    String? searchQuery,
    bool favoritesOnly = false, 
    SortOption sortBy = SortOption.title,
    SortDirection direction = SortDirection.asc,
  }) {
    // If no tags and no search, use watchAllVideos
    if (tagsAny.isEmpty && tagsAll.isEmpty && (searchQuery == null || searchQuery.isEmpty)) {
      return watchAllVideos(favoritesOnly: favoritesOnly, sortBy: sortBy, direction: direction);
    }
    
    // Build WHERE clause components
    final variables = <Variable>[];
    final conditions = <String>[];

    // 1. OR Logic (Attributes Any)
    if (tagsAny.isNotEmpty) {
      final placeholders = tagsAny.map((_) => '?').join(',');
      conditions.add('id IN (SELECT video_id FROM tags WHERE tag_text IN ($placeholders))');
      variables.addAll(tagsAny.map((t) => Variable.withString(t)));
    }

    // 2. AND Logic (Attributes All)
    if (tagsAll.isNotEmpty) {
      final placeholders = tagsAll.map((_) => '?').join(',');
      conditions.add('id IN (SELECT video_id FROM tags WHERE tag_text IN ($placeholders) GROUP BY video_id HAVING COUNT(DISTINCT tag_text) = ?)');
      variables.addAll(tagsAll.map((t) => Variable.withString(t)));
      variables.add(Variable.withInt(tagsAll.length));
    }

    if (favoritesOnly) {
      conditions.add('is_favorite = 1');
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      conditions.add('(lower(title) LIKE ? OR lower(absolute_path) LIKE ?)');
      variables.add(Variable.withString('%${searchQuery.toLowerCase()}%'));
      variables.add(Variable.withString('%${searchQuery.toLowerCase()}%'));
    }

    String whereClause = '';
    if (conditions.isNotEmpty) {
      whereClause = 'WHERE ${conditions.join(' AND ')}';
    }

    String orderBy = 'ORDER BY title ASC';
    final mode = direction == SortDirection.asc ? 'ASC' : 'DESC';
    switch (sortBy) {
      case SortOption.title:
        orderBy = 'ORDER BY title $mode';
        break;
      case SortOption.duration:
        orderBy = 'ORDER BY duration $mode';
        break;
      case SortOption.addedAt:
        orderBy = 'ORDER BY file_created_at $mode';
        break;
      case SortOption.size:
        orderBy = 'ORDER BY size $mode';
        break;
    }

    final sql = 'SELECT * FROM videos $whereClause $orderBy';

    return customSelect(sql, variables: variables, readsFrom: {videos, this.tags})
      .watch()
      .map((rows) => rows.map((row) => videos.map(row.data)).toList());
  } 
    

}

@DriftAccessor(tables: [Tags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(AppDatabase db) : super(db);
  
  Future<int> insertTag(TagsCompanion tag) {
    final normalizedText = _normalizeTag(tag.tagText.value);
    return into(tags).insert(tag.copyWith(tagText: Value(normalizedText)), mode: InsertMode.insertOrIgnore);
  }
  
  Future<void> insertTagsBatch(List<TagsCompanion> companions) {
    return batch((b) {
      final normalizedCompanions = companions.map((c) {
        final normalizedText = _normalizeTag(c.tagText.value);
        return c.copyWith(tagText: Value(normalizedText));
      }).toList();
      b.insertAll(tags, normalizedCompanions, mode: InsertMode.insertOrIgnore);
    });
  }

  String _normalizeTag(String tag) {
    String s = tag;
    // 1. Split CamelCase (e.g., testBest -> test Best)
    s = s.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (Match m) => ' ');
    // 2. Handle multiple uppercase (e.g., ASDBest -> ASD Best)
    s = s.replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (Match m) => '${m.group(1)} ${m.group(2)}');
    // 3. Split Numbers at end (e.g., gsd3 -> gsd 3)
    s = s.replaceAllMapped(RegExp(r'(?<=[a-zA-Z])(?=[0-9]+$)'), (Match m) => ' ');
    
    // 4. Lowercase and trim
    return s.trim().toLowerCase();
  }
  
  Future<void> deleteTag(int videoId, String tagText) {
    return (delete(tags)..where((t) => t.videoId.equals(videoId) & t.tagText.equals(tagText))).go();
  }

  Future<void> deleteTagFromAllVideos(String tagText) {
    return (delete(tags)..where((t) => t.tagText.equals(tagText))).go();
  }
  Future<List<Tag>> getTagsForVideo(int videoId) => (select(tags)..where((t) => t.videoId.equals(videoId))).get();
  Stream<List<Tag>> watchTagsForVideo(int videoId) => (select(tags)..where((t) => t.videoId.equals(videoId))).watch();
  
  Future<List<String>> getAllUniqueTags() {
    final query = selectOnly(tags, distinct: true)..addColumns([tags.tagText]);
    return query.map((row) => row.read(tags.tagText)!).get();
  }

  Stream<List<String>> watchAllUniqueTags() {
    final query = selectOnly(tags, distinct: true)..addColumns([tags.tagText]);
    return query.map((row) => row.read(tags.tagText)!).watch();
  }

  Future<int> getTagUsageCount(String tagText) async {
    final countExp = tags.id.count();
    final query = selectOnly(tags)..addColumns([countExp])..where(tags.tagText.equals(tagText));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  Stream<Map<String, int>> watchTagsWithCounts() {
    final countExp = tags.id.count();
    final query = selectOnly(tags)..addColumns([tags.tagText, countExp])..groupBy([tags.tagText]);
    
    return query.watch().map((rows) {
      final results = <String, int>{};
      for (final row in rows) {
        final text = row.read(tags.tagText);
        final count = row.read(countExp);
        if (text != null && count != null) {
          results[text] = count;
        }
      }
      return results;
    });
  }

  Future<Map<String, int>> getTagsWithCountsForVideos(List<int> videoIds) async {
    if (videoIds.isEmpty) return {};
    
    final countExp = tags.id.count();
    final query = selectOnly(tags)
      ..addColumns([tags.tagText, countExp])
      ..where(tags.videoId.isIn(videoIds))
      ..groupBy([tags.tagText]);
    
    final rows = await query.get();
    
    final results = <String, int>{};
    for (final row in rows) {
      final text = row.read(tags.tagText);
      final count = row.read(countExp);
      if (text != null && count != null) {
        results[text] = count;
      }
    }
    return results;
  }

  Future<void> pruneEmptyTags() async {
    // We want to delete tags where the videoId no longer exists in search (FK cascade should handle this)
    // AND tags that might have been left over if we ever had a logic bug.
    // Also, if we ever support manual tag entry without association, we'd handle it here.
    // For now, let's just make it explicit: delete tags that don't match any video.
    // However, since videoId has a reference, Sqlite won't allow orphans.
    // The "zero associated videos" issue mentioned by user likely refers to 
    // tags that the UI still sees because of slow stream updates or 
    // if a video was deleted but the stream didn't fire correctly.
    // Actually, Drift handles this well. The "tags with zero videos" might be 
    // tags from videos that ARE in the DB but were processed incorrectly.
    // Let's add a manual cleanup query.
    await customStatement('DELETE FROM tags WHERE video_id NOT IN (SELECT id FROM videos)');
  }

  // ============== TAG MANAGEMENT OPERATIONS ==============

  /// Renames a tag across all videos, handling conflicts.
  /// Returns a result with counts of updated and skipped videos.
  /// Note: oldTagText should be the exact tag text from the database
  Future<TagRenameResult> renameTag(String oldTagText, String newTagText) async {
    final normalizedNew = _normalizeTag(newTagText);
    
    if (normalizedNew.isEmpty) {
      throw ArgumentError('New tag name cannot be empty');
    }
    
    // Use oldTagText exactly as passed - it comes from the database
    final exactOldTag = oldTagText;
    
    // Check if old and new are effectively the same
    if (normalizedNew == exactOldTag.trim().toLowerCase()) {
      return TagRenameResult(updated: 0, skipped: 0);
    }
    
    return transaction(() async {
      // Get all video IDs with the old tag (exact match)
      final videosWithOldTag = await (selectOnly(tags)
        ..addColumns([tags.videoId])
        ..where(tags.tagText.equals(exactOldTag))
      ).map((row) => row.read(tags.videoId)!).get();
      
      if (videosWithOldTag.isEmpty) {
        return TagRenameResult(updated: 0, skipped: 0);
      }
      
      // Get video IDs that already have the new tag (conflicts)
      final videosWithNewTag = await (selectOnly(tags)
        ..addColumns([tags.videoId])
        ..where(tags.tagText.equals(normalizedNew) & tags.videoId.isIn(videosWithOldTag))
      ).map((row) => row.read(tags.videoId)!).get();
      
      final conflictVideoIds = videosWithNewTag.toSet();
      
      // Delete old tag from conflicting videos (they already have new tag)
      if (conflictVideoIds.isNotEmpty) {
        await (delete(tags)
          ..where((t) => t.tagText.equals(exactOldTag) & t.videoId.isIn(conflictVideoIds.toList()))
        ).go();
      }
      
      // Update old tag to new tag for non-conflicting videos
      final nonConflictVideoIds = videosWithOldTag.where((id) => !conflictVideoIds.contains(id)).toList();
      if (nonConflictVideoIds.isNotEmpty) {
        await (update(tags)
          ..where((t) => t.tagText.equals(exactOldTag) & t.videoId.isIn(nonConflictVideoIds))
        ).write(TagsCompanion(tagText: Value(normalizedNew)));
      }
      
      return TagRenameResult(
        updated: nonConflictVideoIds.length,
        skipped: conflictVideoIds.length,
      );
    });
  }

  /// Merges multiple tags into a single target tag.
  /// Returns result with count of videos affected.
  /// Note: sourceTagTexts should be exact tag texts from the database
  Future<TagMergeResult> mergeTags(List<String> sourceTagTexts, String targetTagText) async {
    final normalizedTarget = _normalizeTag(targetTagText);
    // Use exact source tags from database
    final exactSources = sourceTagTexts.toSet();
    
    if (exactSources.isEmpty) {
      return TagMergeResult(videosAffected: 0, tagsRemoved: 0);
    }
    if (normalizedTarget.isEmpty) {
      throw ArgumentError('Target tag name cannot be empty');
    }
    
    // Remove target from sources if it's there (no need to merge into itself)
    // Check both exact match and normalized match
    exactSources.removeWhere((s) => s == normalizedTarget || s.trim().toLowerCase() == normalizedTarget);
    if (exactSources.isEmpty) {
      return TagMergeResult(videosAffected: 0, tagsRemoved: 0);
    }
    
    return transaction(() async {
      // Get all video IDs with any source tag (exact match)
      final videosWithSourceTags = await (selectOnly(tags, distinct: true)
        ..addColumns([tags.videoId])
        ..where(tags.tagText.isIn(exactSources.toList()))
      ).map((row) => row.read(tags.videoId)!).get();
      
      if (videosWithSourceTags.isEmpty) {
        return TagMergeResult(videosAffected: 0, tagsRemoved: exactSources.length);
      }
      
      // Get video IDs that already have the target tag
      final videosWithTargetTag = await (selectOnly(tags)
        ..addColumns([tags.videoId])
        ..where(tags.tagText.equals(normalizedTarget) & tags.videoId.isIn(videosWithSourceTags))
      ).map((row) => row.read(tags.videoId)!).get();
      
      final videosNeedingTargetTag = videosWithSourceTags.where((id) => !videosWithTargetTag.contains(id)).toList();
      
      // Add target tag to videos that don't have it
      if (videosNeedingTargetTag.isNotEmpty) {
        final newTags = videosNeedingTargetTag.map((videoId) => 
          TagsCompanion.insert(videoId: videoId, tagText: normalizedTarget)
        ).toList();
        await insertTagsBatch(newTags);
      }
      
      // Delete all source tags (exact match)
      await (delete(tags)..where((t) => t.tagText.isIn(exactSources.toList()))).go();
      
      return TagMergeResult(
        videosAffected: videosWithSourceTags.length,
        tagsRemoved: exactSources.length,
      );
    });
  }

  /// Adds tags to multiple videos in batch.
  Future<void> addTagsToVideos(List<int> videoIds, List<String> tagTexts) async {
    if (videoIds.isEmpty || tagTexts.isEmpty) return;
    
    final normalizedTags = tagTexts.map((t) => _normalizeTag(t)).where((t) => t.isNotEmpty).toList();
    if (normalizedTags.isEmpty) return;
    
    final companions = <TagsCompanion>[];
    for (final videoId in videoIds) {
      for (final tagText in normalizedTags) {
        companions.add(TagsCompanion.insert(videoId: videoId, tagText: tagText));
      }
    }
    await insertTagsBatch(companions);
  }

  /// Removes specific tags from multiple videos.
  Future<void> removeTagsFromVideos(List<int> videoIds, List<String> tagTexts) async {
    if (videoIds.isEmpty || tagTexts.isEmpty) return;
    
    final normalizedTags = tagTexts.map((t) => t.trim().toLowerCase()).toList();
    await (delete(tags)
      ..where((t) => t.videoId.isIn(videoIds) & t.tagText.isIn(normalizedTags))
    ).go();
  }

  /// Gets all tags with their video counts and source info for management UI.
  Stream<List<TagInfo>> watchAllTagsWithInfo() {
    return customSelect('''
      SELECT 
        tag_text,
        COUNT(*) as video_count,
        COUNT(CASE WHEN source = 'user' THEN 1 END) as user_count,
        COUNT(CASE WHEN source = 'auto' THEN 1 END) as auto_count
      FROM tags
      GROUP BY tag_text
      ORDER BY tag_text ASC
    ''', readsFrom: {tags}).watch().map((rows) {
      return rows.map((row) {
        final userCount = row.read<int>('user_count');
        final autoCount = row.read<int>('auto_count');
        String sourceType;
        if (userCount > 0 && autoCount > 0) {
          sourceType = 'mixed';
        } else if (autoCount > 0) {
          sourceType = 'auto';
        } else {
          sourceType = 'user';
        }
        return TagInfo(
          tagText: row.read<String>('tag_text')!,
          videoCount: row.read<int>('video_count'),
          sourceType: sourceType,
        );
      }).toList();
    });
  }

  Future<TagStatistics> getTagStatistics() async {
    final uniqueTagsResult = await customSelect(
      'SELECT COUNT(DISTINCT tag_text) as count FROM tags'
    ).getSingle();
    final uniqueCount = uniqueTagsResult.read<int>('count');

    final totalResult = await customSelect(
      'SELECT COUNT(*) as count FROM tags'
    ).getSingle();
    final totalAssignments = totalResult.read<int>('count');

    final userResult = await customSelect(
      "SELECT COUNT(*) as count FROM tags WHERE source = 'user'"
    ).getSingle();
    final userTags = userResult.read<int>('count');

    final autoResult = await customSelect(
      "SELECT COUNT(*) as count FROM tags WHERE source = 'auto'"
    ).getSingle();
    final autoTags = autoResult.read<int>('count');

    final tagsPerVideoResult = await customSelect(
      'SELECT video_id, COUNT(*) as tag_count FROM tags GROUP BY video_id'
    ).get();
    
    int minTags = 0, maxTags = 0;
    double avgTags = 0;
    if (tagsPerVideoResult.isNotEmpty) {
      final counts = tagsPerVideoResult.map((r) => r.read<int>('tag_count')).toList();
      minTags = counts.reduce((a, b) => a < b ? a : b);
      maxTags = counts.reduce((a, b) => a > b ? a : b);
      avgTags = counts.reduce((a, b) => a + b) / counts.length;
    }

    return TagStatistics(
      uniqueTagCount: uniqueCount,
      totalAssignments: totalAssignments,
      userTags: userTags,
      autoTags: autoTags,
      minTagsPerVideo: minTags,
      maxTagsPerVideo: maxTags,
      avgTagsPerVideo: avgTags,
    );
  }
}

// ============== TAG MANAGEMENT MODELS ==============

class TagRenameResult {
  final int updated;
  final int skipped;
  
  const TagRenameResult({required this.updated, required this.skipped});
}

class TagMergeResult {
  final int videosAffected;
  final int tagsRemoved;
  
  const TagMergeResult({required this.videosAffected, required this.tagsRemoved});
}

class TagInfo {
  final String tagText;
  final int videoCount;
  final String sourceType; // 'user', 'auto', or 'mixed'
  
  const TagInfo({
    required this.tagText,
    required this.videoCount,
    required this.sourceType,
  });
}

class TagStatistics {
  final int uniqueTagCount;
  final int totalAssignments;
  final int userTags;
  final int autoTags;
  final int minTagsPerVideo;
  final int maxTagsPerVideo;
  final double avgTagsPerVideo;
  
  const TagStatistics({
    required this.uniqueTagCount,
    required this.totalAssignments,
    required this.userTags,
    required this.autoTags,
    required this.minTagsPerVideo,
    required this.maxTagsPerVideo,
    required this.avgTagsPerVideo,
  });
}
