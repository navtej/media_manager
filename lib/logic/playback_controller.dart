import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/providers.dart';
import '../services/library_access_service.dart';
import '../services/natural_language_service.dart';
import '../services/playback_service.dart';

class PlaybackController {
  const PlaybackController({
    required FoldersDao foldersDao,
    required VideosDao videosDao,
    required LibraryAccessService libraryAccessService,
    required PlaybackService playbackService,
    required NaturalLanguageService naturalLanguageService,
  }) : _foldersDao = foldersDao,
       _videosDao = videosDao,
       _libraryAccessService = libraryAccessService,
       _playbackService = playbackService,
       _naturalLanguageService = naturalLanguageService;

  final FoldersDao _foldersDao;
  final VideosDao _videosDao;
  final LibraryAccessService _libraryAccessService;
  final PlaybackService _playbackService;
  final NaturalLanguageService _naturalLanguageService;

  Future<bool> play(Video video) {
    return _withLibraryAccess(
      video,
      () => _playbackService.playVideo(video.absolutePath),
    );
  }

  Future<bool> playPlaylist(List<int> videoIds) async {
    final ids = videoIds.toSet().toList(growable: false);
    if (ids.isEmpty) {
      return false;
    }

    final videosById = {
      for (final video in await _videosDao.getVideosByIds(ids)) video.id: video,
    };
    final videos = [
      for (final id in ids)
        if (videosById[id] case final video?)
          video
        else
          throw StateError('A selected video no longer exists.'),
    ];
    final foldersById = {
      for (final folder in await _foldersDao.getAllFolders()) folder.id: folder,
    };

    return _libraryAccessService.withAccessToAll(
      libraries: [
        for (final video in videos)
          if (foldersById[video.folderId] case final folder?)
            LibraryAccessRequest(
              path: folder.path,
              bookmark: folder.securityScopedBookmark,
            )
          else
            throw StateError('Library folder is missing.'),
      ],
      action: () => _playbackService.playPlaylist(
        videos.map((video) => video.absolutePath).toList(growable: false),
      ),
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
    videosDao: ref.watch(videosDaoProvider),
    libraryAccessService: ref.watch(libraryAccessServiceProvider),
    playbackService: ref.watch(playbackServiceProvider),
    naturalLanguageService: ref.watch(naturalLanguageServiceProvider),
  ),
);
