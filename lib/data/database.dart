import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables.dart';

part 'database.g.dart';

enum SortOption { title, duration, addedAt, size }
enum SortDirection { asc, desc }

@DriftDatabase(tables: [Folders, Videos, Tags, TagDefinitions, VideoTags], daos: [VideosDao, FoldersDao, TagsDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) => m.createAll(),
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          try {
            await m.addColumn(videos, videos.isFavorite);
          } catch (e) {
            print('MIGRATION INFO: isFavorite already exists or error: $e');
          }
        }
        if (from < 3) {
          try {
            await m.addColumn(videos, videos.fileCreatedAt);
          } catch (e) {
             print('MIGRATION INFO: fileCreatedAt already exists or error: $e');
          }
        }
        if (from < 4) {
          try {
            await m.addColumn(videos, videos.aiProcessed);
          } catch (e) {
             print('MIGRATION INFO: aiProcessed already exists or error: $e');
          }
        }
        if (from < 5) {
          try {
            await m.addColumn(videos, videos.thumbnailPath);
          } catch (e) {
             print('MIGRATION INFO: thumbnailPath already exists or error: $e');
          }
        }
        if (from < 6) {
          // These are CREATE TABLE, so they should fail if exists, which is fine
          // but Drift's createTable normally handles "IF NOT EXISTS" if configured?
          // Actually createTable might throw if table exists.
          try {
            await m.createTable(tagDefinitions);
            await m.createTable(videoTags);
          } catch (e) {
             print('MIGRATION INFO: Tables already exist or error: $e');
          }
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        // Only migrate tags if we are just now upgrading to 6
        if (details.wasCreated == false && details.versionBefore != null && details.versionBefore! < 6) {
           await _migrateTags(this);
        }
      },
    );
  }

  Future<void> _migrateTags(AppDatabase db) async {
    try {
      final legacyCount = await db.customSelect('SELECT count(*) as c FROM tags').getSingle().then((r) => r.read<int>('c'));
      if (legacyCount == 0) return;
      
      await db.transaction(() async {
        // 1. Insert unique tags into tag_definitions
        await db.customStatement(
          'INSERT OR IGNORE INTO tag_definitions (name, source) SELECT DISTINCT tag_text, source FROM tags'
        );
        
        // 2. Insert into video_tags
        await db.customStatement('''
          INSERT OR IGNORE INTO video_tags (video_id, tag_id)
          SELECT t.video_id, td.id 
          FROM tags t 
          JOIN tag_definitions td ON t.tag_text = td.name
        ''');
      });
      print('MIGRATION: Tags normalized successfully.');
    } catch (e) {
      print('MIGRATION ERROR (Tags): $e');
    }
  }

  Future<void> clearAllData() async {
    await transaction(() async {
      await customStatement('DELETE FROM tags');
      await customStatement('DELETE FROM videos');
    });
  }

  @override
  Future<void> close() {
    print('DEBUG: AppDatabase.close() called');
    return super.close();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final oldFolder = await getApplicationDocumentsDirectory();
    final newFolder = await getApplicationSupportDirectory();
    
    final oldFile = File(p.join(oldFolder.path, 'movie_manager.sqlite'));
    final newFile = File(p.join(newFolder.path, 'movie_manager.sqlite'));

    // If the database exists in Documents but not in Application Support, move it.
    if (await oldFile.exists() && !await newFile.exists()) {
      try {
        // Ensure the target directory exists
        if (!await newFolder.exists()) {
          await newFolder.create(recursive: true);
        }

        print('MIGRATION: Moving database from Documents to Application Support');
        await oldFile.rename(newFile.path);

        // Also move sidecar files (WAL and SHM) if they exist
        final sidecars = ['-wal', '-shm'];
        for (final ext in sidecars) {
          final oldS = File('${oldFile.path}$ext');
          final newS = File('${newFile.path}$ext');
          if (await oldS.exists()) {
            await oldS.rename(newS.path);
          }
        }
      } catch (e) {
        print('MIGRATION ERROR: Failed to move database: $e');
        // If rename fails, we fall back to the old location to prevent data loss
        return NativeDatabase.createInBackground(oldFile);
      }
    }

    return NativeDatabase.createInBackground(newFile);
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

@DriftAccessor(tables: [Videos, TagDefinitions, VideoTags]) // Access Tags for join queries if needed
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
  
  // Migration Helpers
  Future<List<Video>> getVideosWithBlobs() {
    return (select(videos)..where((t) => t.thumbnailBlob.isNotNull())).get();
  }

  Future<void> updateVideoThumbnailPath(int id, String path) {
    return (update(videos)..where((t) => t.id.equals(id))).write(
      VideosCompanion(
        thumbnailPath: Value(path),
        thumbnailBlob: const Value(null),
      ),
    );
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
    int limit = 0,
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
    
    if (limit > 0) {
      query.limit(limit);
    }
    
    return query.watch();
  }

  Stream<List<Video>> searchVideos({
    List<String> tagsAny = const [], // OR logic (Primary)
    List<String> tagsAll = const [], // AND logic (Secondary)
    String? searchQuery,
    bool favoritesOnly = false, 
    SortOption sortBy = SortOption.title,
    SortDirection direction = SortDirection.asc,
    int limit = 0,
  }) {
    // If no tags and no search, use watchAllVideos
    if (tagsAny.isEmpty && tagsAll.isEmpty && (searchQuery == null || searchQuery.isEmpty)) {
      return watchAllVideos(favoritesOnly: favoritesOnly, sortBy: sortBy, direction: direction, limit: limit);
    }
    
    // Build WHERE clause components
    final variables = <Variable>[];
    final conditions = <String>[];

    // 1. OR Logic (Attributes Any)
    if (tagsAny.isNotEmpty) {
      final placeholders = tagsAny.map((_) => '?').join(',');
      conditions.add('''
        id IN (
          SELECT vt.video_id 
          FROM video_tags vt 
          JOIN tag_definitions td ON vt.tag_id = td.id 
          WHERE td.name IN ($placeholders)
        )
      ''');
      variables.addAll(tagsAny.map((t) => Variable.withString(t)));
    }

    // 2. AND Logic (Attributes All)
    if (tagsAll.isNotEmpty) {
      final placeholders = tagsAll.map((_) => '?').join(',');
      conditions.add('''
        id IN (
          SELECT vt.video_id 
          FROM video_tags vt 
          JOIN tag_definitions td ON vt.tag_id = td.id 
          WHERE td.name IN ($placeholders) 
          GROUP BY vt.video_id 
          HAVING COUNT(DISTINCT td.name) = ?
        )
      ''');
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

    final sql = 'SELECT * FROM videos $whereClause $orderBy ${limit > 0 ? 'LIMIT ?' : ''}';

    if (limit > 0) {
      variables.add(Variable.withInt(limit));
    }

    return customSelect(sql, variables: variables, readsFrom: {videos, this.videoTags, this.tagDefinitions})
      .watch()
      .map((rows) => rows.map((row) => videos.map(row.data)).toList());
  } 

  Stream<int> countVideos({
    List<String> tagsAny = const [],
    List<String> tagsAll = const [],
    String? searchQuery,
    bool favoritesOnly = false,
  }) {
    // Replicates WHERE clause logic from searchVideos but returns count only
    final List<Variable> variables = [];
    final conditions = <String>[];

    // 1. OR Logic
    if (tagsAny.isNotEmpty) {
      final placeholders = tagsAny.map((_) => '?').join(',');
      conditions.add('''
        id IN (
          SELECT vt.video_id 
          FROM video_tags vt 
          JOIN tag_definitions td ON vt.tag_id = td.id 
          WHERE td.name IN ($placeholders)
        )
      ''');
      variables.addAll(tagsAny.map((t) => Variable.withString(t)));
    }

    // 2. AND Logic
    if (tagsAll.isNotEmpty) {
      final placeholders = tagsAll.map((_) => '?').join(',');
      conditions.add('''
        id IN (
          SELECT vt.video_id 
          FROM video_tags vt 
          JOIN tag_definitions td ON vt.tag_id = td.id 
          WHERE td.name IN ($placeholders) 
          GROUP BY vt.video_id 
          HAVING COUNT(DISTINCT td.name) = ?
        )
      ''');
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

    final sql = 'SELECT COUNT(*) AS c FROM videos $whereClause';

    return customSelect(sql, variables: variables, readsFrom: {videos, this.videoTags, this.tagDefinitions})
      .watch()
      .map((rows) => rows.first.read<int>('c'));
  } 
    

}

@DriftAccessor(tables: [TagDefinitions, VideoTags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(AppDatabase db) : super(db);
  
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

  Future<int> insertTag(TagsCompanion tag) async {
    final normalized = _normalizeTag(tag.tagText.value);
    
    // 1. Ensure Tag Definition exists
    int? tagId = await (select(tagDefinitions)..where((t) => t.name.equals(normalized))).map((t) => t.id).getSingleOrNull();
    if (tagId == null) {
       try {
         tagId = await into(tagDefinitions).insert(TagDefinitionsCompanion(
           name: Value(normalized),
           source: tag.source,
         ), mode: InsertMode.insertOrIgnore);
       } catch (e) {
         // Concurrency fallback
         tagId = await (select(tagDefinitions)..where((t) => t.name.equals(normalized))).map((t) => t.id).getSingleOrNull();
       }
    }
    
    // 2. Insert Video Tag
    if (tagId != null && tag.videoId.present) {
      await into(videoTags).insert(VideoTagsCompanion(
        videoId: tag.videoId,
        tagId: Value(tagId),
      ), mode: InsertMode.insertOrIgnore);
      return tagId;
    }
    return -1;
  }
  
  Future<void> insertTagsBatch(List<TagsCompanion> companions) async {
    if (companions.isEmpty) return;
    
    await transaction(() async {
      for (final c in companions) {
        await insertTag(c);
      }
    });
  }

  Future<void> deleteTag(int videoId, String tagText) async {
    final tagDef = await (select(tagDefinitions)..where((t) => t.name.equals(tagText))).getSingleOrNull();
    if (tagDef != null) {
      await (delete(videoTags)..where((t) => t.videoId.equals(videoId) & t.tagId.equals(tagDef.id))).go();
    }
  }

  Future<void> deleteAllTagsForVideo(int videoId) async {
    await (delete(videoTags)..where((t) => t.videoId.equals(videoId))).go();
  }

  Future<void> deleteTagFromAllVideos(String tagText) async {
    await (delete(tagDefinitions)..where((t) => t.name.equals(tagText))).go();
  }

  // Compatibility mapping to legacy Tag object
  Future<List<Tag>> getTagsForVideo(int videoId) async {
    final query = select(videoTags).join([
      innerJoin(tagDefinitions, tagDefinitions.id.equalsExp(videoTags.tagId))
    ]);
    query.where(videoTags.videoId.equals(videoId));
    
    return query.map((row) {
      final td = row.readTable(tagDefinitions);
      return Tag(
        id: td.id,
        videoId: videoId,
        tagText: td.name,
        source: td.source,
      );
    }).get();
  }

  Stream<List<Tag>> watchTagsForVideo(int videoId) {
    final query = select(videoTags).join([
      innerJoin(tagDefinitions, tagDefinitions.id.equalsExp(videoTags.tagId))
    ]);
    query.where(videoTags.videoId.equals(videoId));
    
    return query.watch().map((rows) {
      return rows.map((row) {
        final td = row.readTable(tagDefinitions);
        return Tag(
          id: td.id,
          videoId: videoId,
          tagText: td.name,
          source: td.source,
        );
      }).toList();
    });
  }
  
  Future<List<String>> getAllUniqueTags() {
    return (select(tagDefinitions)..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .map((t) => t.name).get();
  }

  Stream<List<String>> watchAllUniqueTags() {
    return (select(tagDefinitions)..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .map((t) => t.name).watch();
  }

  Future<int> getTagUsageCount(String tagText) async {
    final tagDef = await (select(tagDefinitions)..where((t) => t.name.equals(tagText))).getSingleOrNull();
    if (tagDef == null) return 0;
    
    final countExp = videoTags.videoId.count();
    final query = selectOnly(videoTags)..addColumns([countExp])..where(videoTags.tagId.equals(tagDef.id));
    return await query.map((row) => row.read(countExp)).getSingle() ?? 0;
  }

  Stream<Map<String, int>> watchTagsWithCounts() {
    // New normalized query
    final countExp = videoTags.videoId.count();
    final query = select(tagDefinitions).join([
      innerJoin(videoTags, videoTags.tagId.equalsExp(tagDefinitions.id))
    ]);
    
    final grouped = query
      ..addColumns([tagDefinitions.name, countExp])
      ..groupBy([tagDefinitions.id]);
      
    return grouped.watch().map((rows) {
      final results = <String, int>{};
      for (final row in rows) {
        final text = row.read(tagDefinitions.name);
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
    
    final countExp = videoTags.videoId.count();
    final query = select(tagDefinitions).join([
      innerJoin(videoTags, videoTags.tagId.equalsExp(tagDefinitions.id))
    ]);
    
    query.where(videoTags.videoId.isIn(videoIds));
    
    final grouped = query
      ..addColumns([tagDefinitions.name, countExp])
      ..groupBy([tagDefinitions.name]);
    
    final rows = await grouped.get();
    
    final results = <String, int>{};
    for (final row in rows) {
      final text = row.read(tagDefinitions.name);
      final count = row.read(countExp);
      if (text != null && count != null) {
        results[text] = count;
      }
    }
    return results;
  }

  Future<void> pruneEmptyTags() async {
    await customStatement('''
      DELETE FROM tag_definitions 
      WHERE id NOT IN (SELECT tag_id FROM video_tags)
    ''');
  }

  // ============== TAG MANAGEMENT OPERATIONS ==============

  Future<TagRenameResult> renameTag(String oldTagText, String newTagText) async {
    final normalizedNew = _normalizeTag(newTagText);
    
    return transaction(() async {
      // 1. Get Old Tag Def
      final oldDef = await (select(tagDefinitions)..where((t) => t.name.equals(oldTagText))).getSingleOrNull();
      if (oldDef == null) return const TagRenameResult(updated: 0, skipped: 0);
      
      // 2. Check if New Tag Def exists
      final newDef = await (select(tagDefinitions)..where((t) => t.name.equals(normalizedNew))).getSingleOrNull();
      
      if (newDef == null) {
        // Simple Rename: Just update text
        await (update(tagDefinitions)..where((t) => t.id.equals(oldDef.id)))
            .write(TagDefinitionsCompanion(name: Value(normalizedNew)));
            
        // Count how many videos had this tag (approximate, costly to count accurately in update)
        // We can count links
        final count = await (selectOnly(videoTags)..addColumns([videoTags.videoId.count()])..where(videoTags.tagId.equals(oldDef.id))).map((row) => row.read(videoTags.videoId.count())).getSingle() ?? 0;
        return TagRenameResult(updated: count, skipped: 0);
      } else {
        // Merge rename: Old tag becomes New tag, but New tag already exists.
        // We need to move all links from Old ID to New ID.
        // But some videos might have BOTH.
        
        // 2a. Find Conflict Links (Videos having both Old and New)
        // SELECT video_id FROM video_tags WHERE tag_id = oldDef.id
        // INTERSECT
        // SELECT video_id FROM video_tags WHERE tag_id = newDef.id
        final conflicts = await customSelect(
          'SELECT video_id FROM video_tags WHERE tag_id = ? INTERSECT SELECT video_id FROM video_tags WHERE tag_id = ?',
          variables: [Variable.withInt(oldDef.id), Variable.withInt(newDef.id)]
        ).get();
        
        final conflictVideoIds = conflicts.map((r) => r.read<int>('video_id')).toList();
        
        // 2b. Delete links for Old Tag where conflict exists (redundant)
        if (conflictVideoIds.isNotEmpty) {
          await (delete(videoTags)..where((t) => t.tagId.equals(oldDef.id) & t.videoId.isIn(conflictVideoIds))).go();
        }
        
        // 2c. Update remaining Old Tag links to New Tag ID
        await customStatement(
          'UPDATE video_tags SET tag_id = ? WHERE tag_id = ?',
          [newDef.id, oldDef.id]
        );
        
        // 2d. Delete Old Tag Def
        await delete(tagDefinitions).delete(oldDef);
        
        // Count non-conflicts roughly
        final totalLinks = await (selectOnly(videoTags)..addColumns([videoTags.videoId.count()])..where(videoTags.tagId.equals(newDef.id))).map((row) => row.read(videoTags.videoId.count())).getSingle() ?? 0;
        
        return TagRenameResult(updated: totalLinks - conflictVideoIds.length, skipped: conflictVideoIds.length);
      }
    });
  }

  Future<TagMergeResult> mergeTags(List<String> sourceTagTexts, String targetTagText) async {
    final normalizedTarget = _normalizeTag(targetTagText);
    
    return transaction(() async {
      // Resolve Target ID (Create if needed)
      int targetId;
      var targetDef = await (select(tagDefinitions)..where((t) => t.name.equals(normalizedTarget))).getSingleOrNull();
      if (targetDef == null) {
        targetId = await into(tagDefinitions).insert(TagDefinitionsCompanion(name: Value(normalizedTarget)));
      } else {
        targetId = targetDef.id;
      }
      
      int affected = 0;
      int removed = 0;
      
      for (final srcText in sourceTagTexts) {
        if (srcText == normalizedTarget) continue;
        
        final srcDef = await (select(tagDefinitions)..where((t) => t.name.equals(srcText))).getSingleOrNull();
        if (srcDef == null) continue;
        
        // Merge srcDef -> targetId (Same logic as rename merge)
        // 1. Delete conflicts
        await customStatement('''
          DELETE FROM video_tags 
          WHERE tag_id = ? 
          AND video_id IN (SELECT video_id FROM video_tags WHERE tag_id = ?)
        ''', [srcDef.id, targetId]);
        
        // 2. Move links
        await customStatement('UPDATE video_tags SET tag_id = ? WHERE tag_id = ?', [targetId, srcDef.id]);
        
        // 3. Delete Src Def
        await delete(tagDefinitions).delete(srcDef);
        removed++;
        affected++; // Rough approximation
      }
      
      return TagMergeResult(videosAffected: affected, tagsRemoved: removed);
    });
  }

  Future<void> addTagsToVideos(List<int> videoIds, List<String> tagTexts) async {
    for (final tag in tagTexts) {
      final normalized = _normalizeTag(tag);
      // Ensure def
      int? tagId = await (select(tagDefinitions)..where((t) => t.name.equals(normalized))).map((t) => t.id).getSingleOrNull();
      if (tagId == null) {
        tagId = await into(tagDefinitions).insert(TagDefinitionsCompanion(name: Value(normalized)));
      }
      
      // Insert links
      for (final vid in videoIds) {
        await into(videoTags).insert(VideoTagsCompanion(videoId: Value(vid), tagId: Value(tagId)), mode: InsertMode.insertOrIgnore);
      }
    }
  }

  Future<void> removeTagsFromVideos(List<int> videoIds, List<String> tagTexts) async {
    // Resolve IDs
    final ids = await (select(tagDefinitions)..where((t) => t.name.isIn(tagTexts))).map((t) => t.id).get();
    
    await (delete(videoTags)
      ..where((t) => t.videoId.isIn(videoIds) & t.tagId.isIn(ids))
    ).go();
  }

  /// Gets all tags with their video counts and source info for management UI.
  Stream<List<TagInfo>> watchAllTagsWithInfo() {
    // Normalized query: Group by TagDefinition
    // We lost granular source-per-video info, so we just use the TagDefinition's source.
    /*
      SELECT 
        td.name as tag_text,
        td.source as source_type,
        COUNT(vt.video_id) as video_count
      FROM tag_definitions td
      LEFT JOIN video_tags vt ON td.id = vt.tag_id
      GROUP BY td.id
      ORDER BY td.name ASC
    */
    final countExp = videoTags.videoId.count();
    
    final query = select(tagDefinitions).join([
      leftOuterJoin(videoTags, videoTags.tagId.equalsExp(tagDefinitions.id))
    ]);
    
    final grouped = query
      ..addColumns([tagDefinitions.name, tagDefinitions.source, countExp])
      ..groupBy([tagDefinitions.id])
      ..orderBy([OrderingTerm.asc(tagDefinitions.name)]);

    return grouped.watch().map((rows) {
      return rows.map((row) {
        final text = row.read(tagDefinitions.name)!;
        final source = row.read(tagDefinitions.source)!;
        final count = row.read(countExp) ?? 0;
        
        return TagInfo(
          tagText: text,
          videoCount: count,
          sourceType: source,
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
