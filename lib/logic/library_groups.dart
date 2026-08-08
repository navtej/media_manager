import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/tables.dart';

String libraryGroupName(Folder folder) {
  final groupName = folder.groupName?.trim();
  return groupName == null || groupName.isEmpty
      ? defaultLibraryGroupName
      : groupName;
}

String normalizeLibraryGroupName(String name) => name.trim();

bool sameLibraryGroupName(String first, String second) =>
    normalizeLibraryGroupName(first).toLowerCase() ==
    normalizeLibraryGroupName(second).toLowerCase();

class LibraryGroupsRefreshController extends Notifier<int> {
  @override
  int build() => 0;

  void refresh() => state += 1;
}

final libraryGroupsRefreshProvider =
    NotifierProvider<LibraryGroupsRefreshController, int>(
      LibraryGroupsRefreshController.new,
    );
