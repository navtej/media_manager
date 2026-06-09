import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';

void main() {
  test('setFavoriteForVideos updates every selected video', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Volumes/Library'),
    );
    final first = await _insertVideo(db, folderId, 'first.mp4');
    final second = await _insertVideo(db, folderId, 'second.mp4');
    final untouched = await _insertVideo(db, folderId, 'third.mp4');

    await db.videosDao.setFavoriteForVideos([first.id, second.id], true);

    expect((await db.videosDao.getVideoById(first.id))!.isFavorite, isTrue);
    expect((await db.videosDao.getVideoById(second.id))!.isFavorite, isTrue);
    expect(
      (await db.videosDao.getVideoById(untouched.id))!.isFavorite,
      isFalse,
    );

    await db.videosDao.setFavoriteForVideos([first.id, second.id], false);

    expect((await db.videosDao.getVideoById(first.id))!.isFavorite, isFalse);
    expect((await db.videosDao.getVideoById(second.id))!.isFavorite, isFalse);
  });

  test('deleteAllTagsForVideos clears tags only for selected videos', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final folderId = await db.foldersDao.insertFolder(
      FoldersCompanion.insert(path: '/Volumes/Library'),
    );
    final first = await _insertVideo(db, folderId, 'first.mp4');
    final second = await _insertVideo(db, folderId, 'second.mp4');
    final untouched = await _insertVideo(db, folderId, 'third.mp4');

    await db.tagsDao.insertTagsBatch([
      TagsCompanion.insert(
        videoId: first.id,
        tagText: 'Keepable',
        source: const drift.Value('user'),
      ),
      TagsCompanion.insert(
        videoId: second.id,
        tagText: 'Clearable',
        source: const drift.Value('user'),
      ),
      TagsCompanion.insert(
        videoId: untouched.id,
        tagText: 'Untouched',
        source: const drift.Value('user'),
      ),
    ]);

    await db.tagsDao.deleteAllTagsForVideos([first.id, second.id]);

    expect(await db.tagsDao.getTagsForVideo(first.id), isEmpty);
    expect(await db.tagsDao.getTagsForVideo(second.id), isEmpty);
    expect(await db.tagsDao.getTagsForVideo(untouched.id), hasLength(1));
  });
}

Future<Video> _insertVideo(
  AppDatabase db,
  int folderId,
  String fileName,
) async {
  final path = '/Volumes/Library/$fileName';
  await db.videosDao.insertVideo(
    VideosCompanion.insert(
      folderId: folderId,
      absolutePath: path,
      title: fileName,
    ),
  );
  return (await db.videosDao.getVideoByPath(path))!;
}
