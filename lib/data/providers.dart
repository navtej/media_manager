// import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'database.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase database(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(() {
    print('DEBUG: Disposing AppDatabase');
    db.close();
  });
  return db;
}

@riverpod
FoldersDao foldersDao(Ref ref) {
  return ref.watch(databaseProvider).foldersDao;
}

@riverpod
LibraryGroupsDao libraryGroupsDao(Ref ref) {
  return LibraryGroupsDao(ref.watch(foldersDaoProvider).attachedDatabase);
}

@riverpod
VideosDao videosDao(Ref ref) {
  return ref.watch(databaseProvider).videosDao;
}

@riverpod
TagsDao tagsDao(Ref ref) {
  return ref.watch(databaseProvider).tagsDao;
}

@riverpod
VideoSummariesDao videoSummariesDao(Ref ref) {
  return ref.watch(databaseProvider).videoSummariesDao;
}

@riverpod
Stream<List<String>> allUniqueTags(Ref ref) {
  return ref.watch(tagsDaoProvider).watchAllUniqueTags();
}
