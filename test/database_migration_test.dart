import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('resumes a partially completed version 10 library-groups migration',
      () async {
    final directory = await Directory.systemTemp.createTemp('movie-manager-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(p.join(directory.path, 'movie_manager.sqlite'));
    final legacy = sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE folders (
        id INTEGER NOT NULL PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        alias TEXT,
        group_name TEXT,
        security_scoped_bookmark TEXT,
        is_private INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL
      );
      CREATE TABLE library_groups (
        id INTEGER NOT NULL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        added_at INTEGER NOT NULL
      );
      INSERT INTO folders (id, path, alias, group_name, is_private, added_at)
      VALUES (1, '/Volumes/Media/Movies', 'Movies', 'Default Group', 0, 0);
      INSERT INTO library_groups (id, name, added_at)
      VALUES (1, 'Default Group', 0);
      PRAGMA user_version = 9;
    ''');
    legacy.dispose();

    final database = AppDatabase.forTesting(
      NativeDatabase.createInBackground(file),
    );
    addTearDown(database.close);

    final folders = await database.foldersDao.getAllFolders();
    expect(folders, hasLength(1));
    expect(folders.single.groupName, 'Default Group');
    expect(await database.libraryGroupsDao.getAllGroups(), hasLength(1));
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      10,
    );
  });
}
