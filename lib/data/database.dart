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
}
