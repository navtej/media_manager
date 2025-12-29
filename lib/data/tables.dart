import 'package:drift/drift.dart';

class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  TextColumn get alias => text().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

class Videos extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get folderId => integer().references(Folders, #id, onDelete: KeyAction.cascade)();
  TextColumn get absolutePath => text()();
  TextColumn get title => text()();
  IntColumn get duration => integer().withDefault(const Constant(0))(); // in seconds
  IntColumn get size => integer().withDefault(const Constant(0))(); // in bytes
  BlobColumn get thumbnailBlob => blob().nullable()();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isOffline => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get fileCreatedAt => dateTime().nullable()();
  BoolColumn get aiProcessed => boolean().withDefault(const Constant(false))();
  
  @override
  List<Set<Column>> get uniqueKeys => [{absolutePath}];
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get videoId => integer().references(Videos, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagText => text()();
  TextColumn get source => text().withDefault(const Constant('user'))(); // 'user' or 'auto'

  @override
  List<Set<Column>> get uniqueKeys => [{videoId, tagText}];
}
