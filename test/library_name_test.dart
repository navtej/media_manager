import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/data/database.dart';
import 'package:movie_manager/logic/library_name.dart';

void main() {
  test('libraryDisplayName trims aliases and falls back to path basename', () {
    final now = DateTime(2026, 6, 22);

    expect(
      libraryDisplayName(
        Folder(
          id: 1,
          path: '/Volumes/Media/Movies',
          alias: '  Family Movies  ',
          securityScopedBookmark: null,
          isPrivate: false,
          addedAt: now,
        ),
      ),
      'Family Movies',
    );
    expect(
      libraryDisplayName(
        Folder(
          id: 2,
          path: '/Volumes/Archive/Movies',
          alias: null,
          securityScopedBookmark: null,
          isPrivate: false,
          addedAt: now,
        ),
      ),
      'Movies',
    );
  });

  test('validateLibraryName rejects blank and duplicate names', () {
    final now = DateTime(2026, 6, 22);
    final folders = [
      Folder(
        id: 1,
        path: '/Volumes/Media/Movies',
        alias: 'Movies',
        securityScopedBookmark: null,
        isPrivate: false,
        addedAt: now,
      ),
      Folder(
        id: 2,
        path: '/Volumes/Archive/Shows',
        alias: 'Shows',
        securityScopedBookmark: null,
        isPrivate: false,
        addedAt: now,
      ),
    ];

    expect(
      validateLibraryName(folderId: 2, name: ' ', folders: folders),
      'Library name is required.',
    );
    expect(
      validateLibraryName(folderId: 2, name: ' movies ', folders: folders),
      'Library name must be unique.',
    );
    expect(
      validateLibraryName(folderId: 2, name: ' Shows ', folders: folders),
      isNull,
    );
  });

  test(
    'uniqueLibraryNameForPath disambiguates matching trailing folder names',
    () {
      final now = DateTime(2026, 6, 22);

      expect(
        uniqueLibraryNameForPath('/Volumes/Archive/Movies', [
          Folder(
            id: 1,
            path: '/Volumes/Media/Movies',
            alias: 'Movies',
            securityScopedBookmark: null,
            isPrivate: false,
            addedAt: now,
          ),
        ]),
        'Archive / Movies',
      );
      expect(
        uniqueLibraryNameForPath('/Volumes/Archive/Movies', [
          Folder(
            id: 1,
            path: '/Volumes/Media/Movies',
            alias: 'Movies',
            securityScopedBookmark: null,
            isPrivate: false,
            addedAt: now,
          ),
          Folder(
            id: 2,
            path: '/Volumes/Other/Archive/Movies',
            alias: 'Archive / Movies',
            securityScopedBookmark: null,
            isPrivate: false,
            addedAt: now,
          ),
        ]),
        'Movies (2)',
      );
    },
  );
}
