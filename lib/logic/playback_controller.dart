import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../services/library_access_service.dart';
import '../services/natural_language_service.dart';

class PlaybackController {
  const PlaybackController({
    required FoldersDao foldersDao,
    required LibraryAccessService libraryAccessService,
    required NaturalLanguageService naturalLanguageService,
  }) : _foldersDao = foldersDao,
       _libraryAccessService = libraryAccessService,
       _naturalLanguageService = naturalLanguageService;

  final FoldersDao _foldersDao;
  final LibraryAccessService _libraryAccessService;
  final NaturalLanguageService _naturalLanguageService;

  Future<bool> play(Video video) {
    return _withLibraryAccess(
      video,
      () => _naturalLanguageService.playVideo(video.absolutePath),
    );
  }

  Future<void> revealInFinder(Video video) {
    return _withLibraryAccess(
      video,
      () => _naturalLanguageService.openInFinder(video.absolutePath),
    );
  }

  Future<T> _withLibraryAccess<T>(
    Video video,
    Future<T> Function() action,
  ) async {
    final folder = await _foldersDao.getFolderById(video.folderId);
    if (folder == null) {
      throw StateError('Library folder is missing.');
    }

    return _libraryAccessService.withAccess(
      library: LibraryAccessRequest(
        path: folder.path,
        bookmark: folder.securityScopedBookmark,
      ),
      action: action,
    );
  }
}

final playbackControllerProvider = Provider(
  (ref) => PlaybackController(
    foldersDao: ref.watch(foldersDaoProvider),
    libraryAccessService: ref.watch(libraryAccessServiceProvider),
    naturalLanguageService: ref.watch(naturalLanguageServiceProvider),
  ),
);
