import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'database.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase database(Ref ref) {
  return AppDatabase();
}

@riverpod
FoldersDao foldersDao(Ref ref) {
  return ref.watch(databaseProvider).foldersDao;
}

@riverpod
VideosDao videosDao(Ref ref) {
  return ref.watch(databaseProvider).videosDao;
}

@riverpod
TagsDao tagsDao(Ref ref) {
  return ref.watch(databaseProvider).tagsDao;
}
