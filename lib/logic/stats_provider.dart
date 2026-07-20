import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

part 'stats_provider.g.dart';

@riverpod
Future<int> dataFolderSize(Ref ref) async {
  final dir = await getApplicationSupportDirectory();
  int totalSize = 0;
  try {
    if (await dir.exists()) {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    }
  } catch (e) {
    // ignore
  }
  return totalSize;
}
