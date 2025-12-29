// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $FoldersTable extends Folders with TableInfo<$FoldersTable, Folder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, path, alias, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Folder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Folder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Folder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      alias: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alias'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class Folder extends DataClass implements Insertable<Folder> {
  final int id;
  final String path;
  final String? alias;
  final DateTime addedAt;
  const Folder({
    required this.id,
    required this.path,
    this.alias,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || alias != null) {
      map['alias'] = Variable<String>(alias);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      path: Value(path),
      alias: alias == null && nullToAbsent
          ? const Value.absent()
          : Value(alias),
      addedAt: Value(addedAt),
    );
  }

  factory Folder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Folder(
      id: serializer.fromJson<int>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      alias: serializer.fromJson<String?>(json['alias']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'path': serializer.toJson<String>(path),
      'alias': serializer.toJson<String?>(alias),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  Folder copyWith({
    int? id,
    String? path,
    Value<String?> alias = const Value.absent(),
    DateTime? addedAt,
  }) => Folder(
    id: id ?? this.id,
    path: path ?? this.path,
    alias: alias.present ? alias.value : this.alias,
    addedAt: addedAt ?? this.addedAt,
  );
  Folder copyWithCompanion(FoldersCompanion data) {
    return Folder(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      alias: data.alias.present ? data.alias.value : this.alias,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Folder(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('alias: $alias, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, path, alias, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Folder &&
          other.id == this.id &&
          other.path == this.path &&
          other.alias == this.alias &&
          other.addedAt == this.addedAt);
}

class FoldersCompanion extends UpdateCompanion<Folder> {
  final Value<int> id;
  final Value<String> path;
  final Value<String?> alias;
  final Value<DateTime> addedAt;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.alias = const Value.absent(),
    this.addedAt = const Value.absent(),
  });
  FoldersCompanion.insert({
    this.id = const Value.absent(),
    required String path,
    this.alias = const Value.absent(),
    this.addedAt = const Value.absent(),
  }) : path = Value(path);
  static Insertable<Folder> custom({
    Expression<int>? id,
    Expression<String>? path,
    Expression<String>? alias,
    Expression<DateTime>? addedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (alias != null) 'alias': alias,
      if (addedAt != null) 'added_at': addedAt,
    });
  }

  FoldersCompanion copyWith({
    Value<int>? id,
    Value<String>? path,
    Value<String?>? alias,
    Value<DateTime>? addedAt,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      alias: alias ?? this.alias,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('alias: $alias, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }
}

class $VideosTable extends Videos with TableInfo<$VideosTable, Video> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VideosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<int> folderId = GeneratedColumn<int>(
    'folder_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _absolutePathMeta = const VerificationMeta(
    'absolutePath',
  );
  @override
  late final GeneratedColumn<String> absolutePath = GeneratedColumn<String>(
    'absolute_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<int> duration = GeneratedColumn<int>(
    'duration',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _thumbnailBlobMeta = const VerificationMeta(
    'thumbnailBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> thumbnailBlob =
      GeneratedColumn<Uint8List>(
        'thumbnail_blob',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _metadataJsonMeta = const VerificationMeta(
    'metadataJson',
  );
  @override
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
    'metadata_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _isOfflineMeta = const VerificationMeta(
    'isOffline',
  );
  @override
  late final GeneratedColumn<bool> isOffline = GeneratedColumn<bool>(
    'is_offline',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_offline" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _fileCreatedAtMeta = const VerificationMeta(
    'fileCreatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fileCreatedAt =
      GeneratedColumn<DateTime>(
        'file_created_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _aiProcessedMeta = const VerificationMeta(
    'aiProcessed',
  );
  @override
  late final GeneratedColumn<bool> aiProcessed = GeneratedColumn<bool>(
    'ai_processed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("ai_processed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    folderId,
    absolutePath,
    title,
    duration,
    size,
    thumbnailBlob,
    metadataJson,
    isOffline,
    isFavorite,
    addedAt,
    fileCreatedAt,
    aiProcessed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'videos';
  @override
  VerificationContext validateIntegrity(
    Insertable<Video> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_folderIdMeta);
    }
    if (data.containsKey('absolute_path')) {
      context.handle(
        _absolutePathMeta,
        absolutePath.isAcceptableOrUnknown(
          data['absolute_path']!,
          _absolutePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_absolutePathMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('thumbnail_blob')) {
      context.handle(
        _thumbnailBlobMeta,
        thumbnailBlob.isAcceptableOrUnknown(
          data['thumbnail_blob']!,
          _thumbnailBlobMeta,
        ),
      );
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
        _metadataJsonMeta,
        metadataJson.isAcceptableOrUnknown(
          data['metadata_json']!,
          _metadataJsonMeta,
        ),
      );
    }
    if (data.containsKey('is_offline')) {
      context.handle(
        _isOfflineMeta,
        isOffline.isAcceptableOrUnknown(data['is_offline']!, _isOfflineMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('file_created_at')) {
      context.handle(
        _fileCreatedAtMeta,
        fileCreatedAt.isAcceptableOrUnknown(
          data['file_created_at']!,
          _fileCreatedAtMeta,
        ),
      );
    }
    if (data.containsKey('ai_processed')) {
      context.handle(
        _aiProcessedMeta,
        aiProcessed.isAcceptableOrUnknown(
          data['ai_processed']!,
          _aiProcessedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {absolutePath},
  ];
  @override
  Video map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Video(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}folder_id'],
      )!,
      absolutePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}absolute_path'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      thumbnailBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}thumbnail_blob'],
      ),
      metadataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata_json'],
      )!,
      isOffline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_offline'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      fileCreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}file_created_at'],
      ),
      aiProcessed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ai_processed'],
      )!,
    );
  }

  @override
  $VideosTable createAlias(String alias) {
    return $VideosTable(attachedDatabase, alias);
  }
}

class Video extends DataClass implements Insertable<Video> {
  final int id;
  final int folderId;
  final String absolutePath;
  final String title;
  final int duration;
  final int size;
  final Uint8List? thumbnailBlob;
  final String metadataJson;
  final bool isOffline;
  final bool isFavorite;
  final DateTime addedAt;
  final DateTime? fileCreatedAt;
  final bool aiProcessed;
  const Video({
    required this.id,
    required this.folderId,
    required this.absolutePath,
    required this.title,
    required this.duration,
    required this.size,
    this.thumbnailBlob,
    required this.metadataJson,
    required this.isOffline,
    required this.isFavorite,
    required this.addedAt,
    this.fileCreatedAt,
    required this.aiProcessed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['folder_id'] = Variable<int>(folderId);
    map['absolute_path'] = Variable<String>(absolutePath);
    map['title'] = Variable<String>(title);
    map['duration'] = Variable<int>(duration);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || thumbnailBlob != null) {
      map['thumbnail_blob'] = Variable<Uint8List>(thumbnailBlob);
    }
    map['metadata_json'] = Variable<String>(metadataJson);
    map['is_offline'] = Variable<bool>(isOffline);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || fileCreatedAt != null) {
      map['file_created_at'] = Variable<DateTime>(fileCreatedAt);
    }
    map['ai_processed'] = Variable<bool>(aiProcessed);
    return map;
  }

  VideosCompanion toCompanion(bool nullToAbsent) {
    return VideosCompanion(
      id: Value(id),
      folderId: Value(folderId),
      absolutePath: Value(absolutePath),
      title: Value(title),
      duration: Value(duration),
      size: Value(size),
      thumbnailBlob: thumbnailBlob == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailBlob),
      metadataJson: Value(metadataJson),
      isOffline: Value(isOffline),
      isFavorite: Value(isFavorite),
      addedAt: Value(addedAt),
      fileCreatedAt: fileCreatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(fileCreatedAt),
      aiProcessed: Value(aiProcessed),
    );
  }

  factory Video.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Video(
      id: serializer.fromJson<int>(json['id']),
      folderId: serializer.fromJson<int>(json['folderId']),
      absolutePath: serializer.fromJson<String>(json['absolutePath']),
      title: serializer.fromJson<String>(json['title']),
      duration: serializer.fromJson<int>(json['duration']),
      size: serializer.fromJson<int>(json['size']),
      thumbnailBlob: serializer.fromJson<Uint8List?>(json['thumbnailBlob']),
      metadataJson: serializer.fromJson<String>(json['metadataJson']),
      isOffline: serializer.fromJson<bool>(json['isOffline']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      fileCreatedAt: serializer.fromJson<DateTime?>(json['fileCreatedAt']),
      aiProcessed: serializer.fromJson<bool>(json['aiProcessed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'folderId': serializer.toJson<int>(folderId),
      'absolutePath': serializer.toJson<String>(absolutePath),
      'title': serializer.toJson<String>(title),
      'duration': serializer.toJson<int>(duration),
      'size': serializer.toJson<int>(size),
      'thumbnailBlob': serializer.toJson<Uint8List?>(thumbnailBlob),
      'metadataJson': serializer.toJson<String>(metadataJson),
      'isOffline': serializer.toJson<bool>(isOffline),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'fileCreatedAt': serializer.toJson<DateTime?>(fileCreatedAt),
      'aiProcessed': serializer.toJson<bool>(aiProcessed),
    };
  }

  Video copyWith({
    int? id,
    int? folderId,
    String? absolutePath,
    String? title,
    int? duration,
    int? size,
    Value<Uint8List?> thumbnailBlob = const Value.absent(),
    String? metadataJson,
    bool? isOffline,
    bool? isFavorite,
    DateTime? addedAt,
    Value<DateTime?> fileCreatedAt = const Value.absent(),
    bool? aiProcessed,
  }) => Video(
    id: id ?? this.id,
    folderId: folderId ?? this.folderId,
    absolutePath: absolutePath ?? this.absolutePath,
    title: title ?? this.title,
    duration: duration ?? this.duration,
    size: size ?? this.size,
    thumbnailBlob: thumbnailBlob.present
        ? thumbnailBlob.value
        : this.thumbnailBlob,
    metadataJson: metadataJson ?? this.metadataJson,
    isOffline: isOffline ?? this.isOffline,
    isFavorite: isFavorite ?? this.isFavorite,
    addedAt: addedAt ?? this.addedAt,
    fileCreatedAt: fileCreatedAt.present
        ? fileCreatedAt.value
        : this.fileCreatedAt,
    aiProcessed: aiProcessed ?? this.aiProcessed,
  );
  Video copyWithCompanion(VideosCompanion data) {
    return Video(
      id: data.id.present ? data.id.value : this.id,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      absolutePath: data.absolutePath.present
          ? data.absolutePath.value
          : this.absolutePath,
      title: data.title.present ? data.title.value : this.title,
      duration: data.duration.present ? data.duration.value : this.duration,
      size: data.size.present ? data.size.value : this.size,
      thumbnailBlob: data.thumbnailBlob.present
          ? data.thumbnailBlob.value
          : this.thumbnailBlob,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      isOffline: data.isOffline.present ? data.isOffline.value : this.isOffline,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      fileCreatedAt: data.fileCreatedAt.present
          ? data.fileCreatedAt.value
          : this.fileCreatedAt,
      aiProcessed: data.aiProcessed.present
          ? data.aiProcessed.value
          : this.aiProcessed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Video(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('absolutePath: $absolutePath, ')
          ..write('title: $title, ')
          ..write('duration: $duration, ')
          ..write('size: $size, ')
          ..write('thumbnailBlob: $thumbnailBlob, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('isOffline: $isOffline, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('addedAt: $addedAt, ')
          ..write('fileCreatedAt: $fileCreatedAt, ')
          ..write('aiProcessed: $aiProcessed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    folderId,
    absolutePath,
    title,
    duration,
    size,
    $driftBlobEquality.hash(thumbnailBlob),
    metadataJson,
    isOffline,
    isFavorite,
    addedAt,
    fileCreatedAt,
    aiProcessed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Video &&
          other.id == this.id &&
          other.folderId == this.folderId &&
          other.absolutePath == this.absolutePath &&
          other.title == this.title &&
          other.duration == this.duration &&
          other.size == this.size &&
          $driftBlobEquality.equals(other.thumbnailBlob, this.thumbnailBlob) &&
          other.metadataJson == this.metadataJson &&
          other.isOffline == this.isOffline &&
          other.isFavorite == this.isFavorite &&
          other.addedAt == this.addedAt &&
          other.fileCreatedAt == this.fileCreatedAt &&
          other.aiProcessed == this.aiProcessed);
}

class VideosCompanion extends UpdateCompanion<Video> {
  final Value<int> id;
  final Value<int> folderId;
  final Value<String> absolutePath;
  final Value<String> title;
  final Value<int> duration;
  final Value<int> size;
  final Value<Uint8List?> thumbnailBlob;
  final Value<String> metadataJson;
  final Value<bool> isOffline;
  final Value<bool> isFavorite;
  final Value<DateTime> addedAt;
  final Value<DateTime?> fileCreatedAt;
  final Value<bool> aiProcessed;
  const VideosCompanion({
    this.id = const Value.absent(),
    this.folderId = const Value.absent(),
    this.absolutePath = const Value.absent(),
    this.title = const Value.absent(),
    this.duration = const Value.absent(),
    this.size = const Value.absent(),
    this.thumbnailBlob = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.isOffline = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.fileCreatedAt = const Value.absent(),
    this.aiProcessed = const Value.absent(),
  });
  VideosCompanion.insert({
    this.id = const Value.absent(),
    required int folderId,
    required String absolutePath,
    required String title,
    this.duration = const Value.absent(),
    this.size = const Value.absent(),
    this.thumbnailBlob = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.isOffline = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.fileCreatedAt = const Value.absent(),
    this.aiProcessed = const Value.absent(),
  }) : folderId = Value(folderId),
       absolutePath = Value(absolutePath),
       title = Value(title);
  static Insertable<Video> custom({
    Expression<int>? id,
    Expression<int>? folderId,
    Expression<String>? absolutePath,
    Expression<String>? title,
    Expression<int>? duration,
    Expression<int>? size,
    Expression<Uint8List>? thumbnailBlob,
    Expression<String>? metadataJson,
    Expression<bool>? isOffline,
    Expression<bool>? isFavorite,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? fileCreatedAt,
    Expression<bool>? aiProcessed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (folderId != null) 'folder_id': folderId,
      if (absolutePath != null) 'absolute_path': absolutePath,
      if (title != null) 'title': title,
      if (duration != null) 'duration': duration,
      if (size != null) 'size': size,
      if (thumbnailBlob != null) 'thumbnail_blob': thumbnailBlob,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (isOffline != null) 'is_offline': isOffline,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (addedAt != null) 'added_at': addedAt,
      if (fileCreatedAt != null) 'file_created_at': fileCreatedAt,
      if (aiProcessed != null) 'ai_processed': aiProcessed,
    });
  }

  VideosCompanion copyWith({
    Value<int>? id,
    Value<int>? folderId,
    Value<String>? absolutePath,
    Value<String>? title,
    Value<int>? duration,
    Value<int>? size,
    Value<Uint8List?>? thumbnailBlob,
    Value<String>? metadataJson,
    Value<bool>? isOffline,
    Value<bool>? isFavorite,
    Value<DateTime>? addedAt,
    Value<DateTime?>? fileCreatedAt,
    Value<bool>? aiProcessed,
  }) {
    return VideosCompanion(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      absolutePath: absolutePath ?? this.absolutePath,
      title: title ?? this.title,
      duration: duration ?? this.duration,
      size: size ?? this.size,
      thumbnailBlob: thumbnailBlob ?? this.thumbnailBlob,
      metadataJson: metadataJson ?? this.metadataJson,
      isOffline: isOffline ?? this.isOffline,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt ?? this.addedAt,
      fileCreatedAt: fileCreatedAt ?? this.fileCreatedAt,
      aiProcessed: aiProcessed ?? this.aiProcessed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<int>(folderId.value);
    }
    if (absolutePath.present) {
      map['absolute_path'] = Variable<String>(absolutePath.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (duration.present) {
      map['duration'] = Variable<int>(duration.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (thumbnailBlob.present) {
      map['thumbnail_blob'] = Variable<Uint8List>(thumbnailBlob.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (isOffline.present) {
      map['is_offline'] = Variable<bool>(isOffline.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (fileCreatedAt.present) {
      map['file_created_at'] = Variable<DateTime>(fileCreatedAt.value);
    }
    if (aiProcessed.present) {
      map['ai_processed'] = Variable<bool>(aiProcessed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VideosCompanion(')
          ..write('id: $id, ')
          ..write('folderId: $folderId, ')
          ..write('absolutePath: $absolutePath, ')
          ..write('title: $title, ')
          ..write('duration: $duration, ')
          ..write('size: $size, ')
          ..write('thumbnailBlob: $thumbnailBlob, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('isOffline: $isOffline, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('addedAt: $addedAt, ')
          ..write('fileCreatedAt: $fileCreatedAt, ')
          ..write('aiProcessed: $aiProcessed')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _videoIdMeta = const VerificationMeta(
    'videoId',
  );
  @override
  late final GeneratedColumn<int> videoId = GeneratedColumn<int>(
    'video_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES videos (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _tagTextMeta = const VerificationMeta(
    'tagText',
  );
  @override
  late final GeneratedColumn<String> tagText = GeneratedColumn<String>(
    'tag_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('user'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, videoId, tagText, source];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('video_id')) {
      context.handle(
        _videoIdMeta,
        videoId.isAcceptableOrUnknown(data['video_id']!, _videoIdMeta),
      );
    } else if (isInserting) {
      context.missing(_videoIdMeta);
    }
    if (data.containsKey('tag_text')) {
      context.handle(
        _tagTextMeta,
        tagText.isAcceptableOrUnknown(data['tag_text']!, _tagTextMeta),
      );
    } else if (isInserting) {
      context.missing(_tagTextMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {videoId, tagText},
  ];
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      videoId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}video_id'],
      )!,
      tagText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_text'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final int id;
  final int videoId;
  final String tagText;
  final String source;
  const Tag({
    required this.id,
    required this.videoId,
    required this.tagText,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['video_id'] = Variable<int>(videoId);
    map['tag_text'] = Variable<String>(tagText);
    map['source'] = Variable<String>(source);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      videoId: Value(videoId),
      tagText: Value(tagText),
      source: Value(source),
    );
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<int>(json['id']),
      videoId: serializer.fromJson<int>(json['videoId']),
      tagText: serializer.fromJson<String>(json['tagText']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'videoId': serializer.toJson<int>(videoId),
      'tagText': serializer.toJson<String>(tagText),
      'source': serializer.toJson<String>(source),
    };
  }

  Tag copyWith({int? id, int? videoId, String? tagText, String? source}) => Tag(
    id: id ?? this.id,
    videoId: videoId ?? this.videoId,
    tagText: tagText ?? this.tagText,
    source: source ?? this.source,
  );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      videoId: data.videoId.present ? data.videoId.value : this.videoId,
      tagText: data.tagText.present ? data.tagText.value : this.tagText,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('videoId: $videoId, ')
          ..write('tagText: $tagText, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, videoId, tagText, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.videoId == this.videoId &&
          other.tagText == this.tagText &&
          other.source == this.source);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<int> id;
  final Value<int> videoId;
  final Value<String> tagText;
  final Value<String> source;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.videoId = const Value.absent(),
    this.tagText = const Value.absent(),
    this.source = const Value.absent(),
  });
  TagsCompanion.insert({
    this.id = const Value.absent(),
    required int videoId,
    required String tagText,
    this.source = const Value.absent(),
  }) : videoId = Value(videoId),
       tagText = Value(tagText);
  static Insertable<Tag> custom({
    Expression<int>? id,
    Expression<int>? videoId,
    Expression<String>? tagText,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (videoId != null) 'video_id': videoId,
      if (tagText != null) 'tag_text': tagText,
      if (source != null) 'source': source,
    });
  }

  TagsCompanion copyWith({
    Value<int>? id,
    Value<int>? videoId,
    Value<String>? tagText,
    Value<String>? source,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      tagText: tagText ?? this.tagText,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (videoId.present) {
      map['video_id'] = Variable<int>(videoId.value);
    }
    if (tagText.present) {
      map['tag_text'] = Variable<String>(tagText.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('videoId: $videoId, ')
          ..write('tagText: $tagText, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $VideosTable videos = $VideosTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final VideosDao videosDao = VideosDao(this as AppDatabase);
  late final FoldersDao foldersDao = FoldersDao(this as AppDatabase);
  late final TagsDao tagsDao = TagsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [folders, videos, tags];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'folders',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('videos', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'videos',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tags', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      Value<int> id,
      required String path,
      Value<String?> alias,
      Value<DateTime> addedAt,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<int> id,
      Value<String> path,
      Value<String?> alias,
      Value<DateTime> addedAt,
    });

final class $$FoldersTableReferences
    extends BaseReferences<_$AppDatabase, $FoldersTable, Folder> {
  $$FoldersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$VideosTable, List<Video>> _videosRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.videos,
    aliasName: $_aliasNameGenerator(db.folders.id, db.videos.folderId),
  );

  $$VideosTableProcessedTableManager get videosRefs {
    final manager = $$VideosTableTableManager(
      $_db,
      $_db.videos,
    ).filter((f) => f.folderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_videosRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> videosRefs(
    Expression<bool> Function($$VideosTableFilterComposer f) f,
  ) {
    final $$VideosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.videos,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideosTableFilterComposer(
            $db: $db,
            $table: $db.videos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  Expression<T> videosRefs<T extends Object>(
    Expression<T> Function($$VideosTableAnnotationComposer a) f,
  ) {
    final $$VideosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.videos,
      getReferencedColumn: (t) => t.folderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideosTableAnnotationComposer(
            $db: $db,
            $table: $db.videos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          Folder,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (Folder, $$FoldersTableReferences),
          Folder,
          PrefetchHooks Function({bool videosRefs})
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String?> alias = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                path: path,
                alias: alias,
                addedAt: addedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String path,
                Value<String?> alias = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                path: path,
                alias: alias,
                addedAt: addedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FoldersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({videosRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (videosRefs) db.videos],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (videosRefs)
                    await $_getPrefetchedData<Folder, $FoldersTable, Video>(
                      currentTable: table,
                      referencedTable: $$FoldersTableReferences
                          ._videosRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FoldersTableReferences(db, table, p0).videosRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.folderId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      Folder,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (Folder, $$FoldersTableReferences),
      Folder,
      PrefetchHooks Function({bool videosRefs})
    >;
typedef $$VideosTableCreateCompanionBuilder =
    VideosCompanion Function({
      Value<int> id,
      required int folderId,
      required String absolutePath,
      required String title,
      Value<int> duration,
      Value<int> size,
      Value<Uint8List?> thumbnailBlob,
      Value<String> metadataJson,
      Value<bool> isOffline,
      Value<bool> isFavorite,
      Value<DateTime> addedAt,
      Value<DateTime?> fileCreatedAt,
      Value<bool> aiProcessed,
    });
typedef $$VideosTableUpdateCompanionBuilder =
    VideosCompanion Function({
      Value<int> id,
      Value<int> folderId,
      Value<String> absolutePath,
      Value<String> title,
      Value<int> duration,
      Value<int> size,
      Value<Uint8List?> thumbnailBlob,
      Value<String> metadataJson,
      Value<bool> isOffline,
      Value<bool> isFavorite,
      Value<DateTime> addedAt,
      Value<DateTime?> fileCreatedAt,
      Value<bool> aiProcessed,
    });

final class $$VideosTableReferences
    extends BaseReferences<_$AppDatabase, $VideosTable, Video> {
  $$VideosTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTable _folderIdTable(_$AppDatabase db) => db.folders
      .createAlias($_aliasNameGenerator(db.videos.folderId, db.folders.id));

  $$FoldersTableProcessedTableManager get folderId {
    final $_column = $_itemColumn<int>('folder_id')!;

    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TagsTable, List<Tag>> _tagsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tags,
    aliasName: $_aliasNameGenerator(db.videos.id, db.tags.videoId),
  );

  $$TagsTableProcessedTableManager get tagsRefs {
    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.videoId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_tagsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$VideosTableFilterComposer
    extends Composer<_$AppDatabase, $VideosTable> {
  $$VideosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get absolutePath => $composableBuilder(
    column: $table.absolutePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get thumbnailBlob => $composableBuilder(
    column: $table.thumbnailBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOffline => $composableBuilder(
    column: $table.isOffline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fileCreatedAt => $composableBuilder(
    column: $table.fileCreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get aiProcessed => $composableBuilder(
    column: $table.aiProcessed,
    builder: (column) => ColumnFilters(column),
  );

  $$FoldersTableFilterComposer get folderId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> tagsRefs(
    Expression<bool> Function($$TagsTableFilterComposer f) f,
  ) {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.videoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VideosTableOrderingComposer
    extends Composer<_$AppDatabase, $VideosTable> {
  $$VideosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get absolutePath => $composableBuilder(
    column: $table.absolutePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get thumbnailBlob => $composableBuilder(
    column: $table.thumbnailBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOffline => $composableBuilder(
    column: $table.isOffline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fileCreatedAt => $composableBuilder(
    column: $table.fileCreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get aiProcessed => $composableBuilder(
    column: $table.aiProcessed,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoldersTableOrderingComposer get folderId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$VideosTableAnnotationComposer
    extends Composer<_$AppDatabase, $VideosTable> {
  $$VideosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get absolutePath => $composableBuilder(
    column: $table.absolutePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<Uint8List> get thumbnailBlob => $composableBuilder(
    column: $table.thumbnailBlob,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metadataJson => $composableBuilder(
    column: $table.metadataJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isOffline =>
      $composableBuilder(column: $table.isOffline, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get fileCreatedAt => $composableBuilder(
    column: $table.fileCreatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get aiProcessed => $composableBuilder(
    column: $table.aiProcessed,
    builder: (column) => column,
  );

  $$FoldersTableAnnotationComposer get folderId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.folderId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> tagsRefs<T extends Object>(
    Expression<T> Function($$TagsTableAnnotationComposer a) f,
  ) {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.videoId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$VideosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VideosTable,
          Video,
          $$VideosTableFilterComposer,
          $$VideosTableOrderingComposer,
          $$VideosTableAnnotationComposer,
          $$VideosTableCreateCompanionBuilder,
          $$VideosTableUpdateCompanionBuilder,
          (Video, $$VideosTableReferences),
          Video,
          PrefetchHooks Function({bool folderId, bool tagsRefs})
        > {
  $$VideosTableTableManager(_$AppDatabase db, $VideosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VideosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VideosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VideosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> folderId = const Value.absent(),
                Value<String> absolutePath = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> duration = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<Uint8List?> thumbnailBlob = const Value.absent(),
                Value<String> metadataJson = const Value.absent(),
                Value<bool> isOffline = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime?> fileCreatedAt = const Value.absent(),
                Value<bool> aiProcessed = const Value.absent(),
              }) => VideosCompanion(
                id: id,
                folderId: folderId,
                absolutePath: absolutePath,
                title: title,
                duration: duration,
                size: size,
                thumbnailBlob: thumbnailBlob,
                metadataJson: metadataJson,
                isOffline: isOffline,
                isFavorite: isFavorite,
                addedAt: addedAt,
                fileCreatedAt: fileCreatedAt,
                aiProcessed: aiProcessed,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int folderId,
                required String absolutePath,
                required String title,
                Value<int> duration = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<Uint8List?> thumbnailBlob = const Value.absent(),
                Value<String> metadataJson = const Value.absent(),
                Value<bool> isOffline = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<DateTime?> fileCreatedAt = const Value.absent(),
                Value<bool> aiProcessed = const Value.absent(),
              }) => VideosCompanion.insert(
                id: id,
                folderId: folderId,
                absolutePath: absolutePath,
                title: title,
                duration: duration,
                size: size,
                thumbnailBlob: thumbnailBlob,
                metadataJson: metadataJson,
                isOffline: isOffline,
                isFavorite: isFavorite,
                addedAt: addedAt,
                fileCreatedAt: fileCreatedAt,
                aiProcessed: aiProcessed,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$VideosTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({folderId = false, tagsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (tagsRefs) db.tags],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (folderId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.folderId,
                                referencedTable: $$VideosTableReferences
                                    ._folderIdTable(db),
                                referencedColumn: $$VideosTableReferences
                                    ._folderIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (tagsRefs)
                    await $_getPrefetchedData<Video, $VideosTable, Tag>(
                      currentTable: table,
                      referencedTable: $$VideosTableReferences._tagsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$VideosTableReferences(db, table, p0).tagsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.videoId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$VideosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VideosTable,
      Video,
      $$VideosTableFilterComposer,
      $$VideosTableOrderingComposer,
      $$VideosTableAnnotationComposer,
      $$VideosTableCreateCompanionBuilder,
      $$VideosTableUpdateCompanionBuilder,
      (Video, $$VideosTableReferences),
      Video,
      PrefetchHooks Function({bool folderId, bool tagsRefs})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      required int videoId,
      required String tagText,
      Value<String> source,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      Value<int> videoId,
      Value<String> tagText,
      Value<String> source,
    });

final class $$TagsTableReferences
    extends BaseReferences<_$AppDatabase, $TagsTable, Tag> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $VideosTable _videoIdTable(_$AppDatabase db) => db.videos.createAlias(
    $_aliasNameGenerator(db.tags.videoId, db.videos.id),
  );

  $$VideosTableProcessedTableManager get videoId {
    final $_column = $_itemColumn<int>('video_id')!;

    final manager = $$VideosTableTableManager(
      $_db,
      $_db.videos,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_videoIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagText => $composableBuilder(
    column: $table.tagText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  $$VideosTableFilterComposer get videoId {
    final $$VideosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoId,
      referencedTable: $db.videos,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideosTableFilterComposer(
            $db: $db,
            $table: $db.videos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagText => $composableBuilder(
    column: $table.tagText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  $$VideosTableOrderingComposer get videoId {
    final $$VideosTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoId,
      referencedTable: $db.videos,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideosTableOrderingComposer(
            $db: $db,
            $table: $db.videos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tagText =>
      $composableBuilder(column: $table.tagText, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  $$VideosTableAnnotationComposer get videoId {
    final $$VideosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.videoId,
      referencedTable: $db.videos,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$VideosTableAnnotationComposer(
            $db: $db,
            $table: $db.videos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, $$TagsTableReferences),
          Tag,
          PrefetchHooks Function({bool videoId})
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> videoId = const Value.absent(),
                Value<String> tagText = const Value.absent(),
                Value<String> source = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                videoId: videoId,
                tagText: tagText,
                source: source,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int videoId,
                required String tagText,
                Value<String> source = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                videoId: videoId,
                tagText: tagText,
                source: source,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TagsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({videoId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (videoId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.videoId,
                                referencedTable: $$TagsTableReferences
                                    ._videoIdTable(db),
                                referencedColumn: $$TagsTableReferences
                                    ._videoIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, $$TagsTableReferences),
      Tag,
      PrefetchHooks Function({bool videoId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$VideosTableTableManager get videos =>
      $$VideosTableTableManager(_db, _db.videos);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
}

mixin _$VideosDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
  $VideosTable get videos => attachedDatabase.videos;
  $TagsTable get tags => attachedDatabase.tags;
}
mixin _$FoldersDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
}
mixin _$TagsDaoMixin on DatabaseAccessor<AppDatabase> {
  $FoldersTable get folders => attachedDatabase.folders;
  $VideosTable get videos => attachedDatabase.videos;
  $TagsTable get tags => attachedDatabase.tags;
}
