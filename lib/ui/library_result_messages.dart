import '../logic/library_controller.dart';
import '../logic/managed_library_service.dart';

String managedLibraryAddResultMessage(ManagedLibraryAddResult result) {
  return switch (result.status) {
    ManagedLibraryAddStatus.created => 'Library added.',
    ManagedLibraryAddStatus.existing => 'Library already exists.',
    ManagedLibraryAddStatus.bookmarkRefreshed => 'Library access refreshed.',
  };
}

String libraryAddFlowResultMessage(LibraryAddFlowResult result) {
  return switch (result.status) {
    LibraryAddFlowStatus.scanInProgress => 'Scan already in progress',
    LibraryAddFlowStatus.moveInProgress => 'Move in progress',
    LibraryAddFlowStatus.completed => managedLibraryAddResultMessage(
      result.managedLibraryResult!,
    ),
  };
}
