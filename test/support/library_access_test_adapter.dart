import 'package:movie_manager/services/library_access_service.dart';

class AlwaysAllowedLibraryAccessAdapter implements LibraryAccessAdapter {
  @override
  Future<String?> createBookmark(String path) async => 'bookmark:$path';

  @override
  Future<bool> startAccessing({
    required String path,
    required String bookmark,
  }) async => true;

  @override
  Future<void> stopAccessing(String path) async {}
}
