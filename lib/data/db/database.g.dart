// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $VaultItemsTable extends VaultItems
    with TableInfo<$VaultItemsTable, VaultItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VaultItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localUpdatedAtMeta = const VerificationMeta(
    'localUpdatedAt',
  );
  @override
  late final GeneratedColumn<int> localUpdatedAt = GeneratedColumn<int>(
    'local_updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payload,
    localUpdatedAt,
    revision,
    deleted,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vault_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<VaultItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('local_updated_at')) {
      context.handle(
        _localUpdatedAtMeta,
        localUpdatedAt.isAcceptableOrUnknown(
          data['local_updated_at']!,
          _localUpdatedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localUpdatedAtMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VaultItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VaultItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      ),
      localUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_updated_at'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $VaultItemsTable createAlias(String alias) {
    return $VaultItemsTable(attachedDatabase, alias);
  }
}

class VaultItem extends DataClass implements Insertable<VaultItem> {
  final String id;
  final Uint8List? payload;

  /// Local edit time (ms since epoch, client clock). Informational only;
  /// conflict resolution uses the server revision.
  final int localUpdatedAt;

  /// Last server revision this row is based on (0 = never synced).
  final int revision;
  final bool deleted;

  /// Has local changes not yet pushed.
  final bool dirty;
  const VaultItem({
    required this.id,
    this.payload,
    required this.localUpdatedAt,
    required this.revision,
    required this.deleted,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<Uint8List>(payload);
    }
    map['local_updated_at'] = Variable<int>(localUpdatedAt);
    map['revision'] = Variable<int>(revision);
    map['deleted'] = Variable<bool>(deleted);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  VaultItemsCompanion toCompanion(bool nullToAbsent) {
    return VaultItemsCompanion(
      id: Value(id),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      localUpdatedAt: Value(localUpdatedAt),
      revision: Value(revision),
      deleted: Value(deleted),
      dirty: Value(dirty),
    );
  }

  factory VaultItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VaultItem(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<Uint8List?>(json['payload']),
      localUpdatedAt: serializer.fromJson<int>(json['localUpdatedAt']),
      revision: serializer.fromJson<int>(json['revision']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<Uint8List?>(payload),
      'localUpdatedAt': serializer.toJson<int>(localUpdatedAt),
      'revision': serializer.toJson<int>(revision),
      'deleted': serializer.toJson<bool>(deleted),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  VaultItem copyWith({
    String? id,
    Value<Uint8List?> payload = const Value.absent(),
    int? localUpdatedAt,
    int? revision,
    bool? deleted,
    bool? dirty,
  }) => VaultItem(
    id: id ?? this.id,
    payload: payload.present ? payload.value : this.payload,
    localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
    revision: revision ?? this.revision,
    deleted: deleted ?? this.deleted,
    dirty: dirty ?? this.dirty,
  );
  VaultItem copyWithCompanion(VaultItemsCompanion data) {
    return VaultItem(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      localUpdatedAt: data.localUpdatedAt.present
          ? data.localUpdatedAt.value
          : this.localUpdatedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VaultItem(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('revision: $revision, ')
          ..write('deleted: $deleted, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    $driftBlobEquality.hash(payload),
    localUpdatedAt,
    revision,
    deleted,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VaultItem &&
          other.id == this.id &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          other.localUpdatedAt == this.localUpdatedAt &&
          other.revision == this.revision &&
          other.deleted == this.deleted &&
          other.dirty == this.dirty);
}

class VaultItemsCompanion extends UpdateCompanion<VaultItem> {
  final Value<String> id;
  final Value<Uint8List?> payload;
  final Value<int> localUpdatedAt;
  final Value<int> revision;
  final Value<bool> deleted;
  final Value<bool> dirty;
  final Value<int> rowid;
  const VaultItemsCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.localUpdatedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.deleted = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VaultItemsCompanion.insert({
    required String id,
    this.payload = const Value.absent(),
    required int localUpdatedAt,
    this.revision = const Value.absent(),
    this.deleted = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       localUpdatedAt = Value(localUpdatedAt);
  static Insertable<VaultItem> custom({
    Expression<String>? id,
    Expression<Uint8List>? payload,
    Expression<int>? localUpdatedAt,
    Expression<int>? revision,
    Expression<bool>? deleted,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (localUpdatedAt != null) 'local_updated_at': localUpdatedAt,
      if (revision != null) 'revision': revision,
      if (deleted != null) 'deleted': deleted,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VaultItemsCompanion copyWith({
    Value<String>? id,
    Value<Uint8List?>? payload,
    Value<int>? localUpdatedAt,
    Value<int>? revision,
    Value<bool>? deleted,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return VaultItemsCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      localUpdatedAt: localUpdatedAt ?? this.localUpdatedAt,
      revision: revision ?? this.revision,
      deleted: deleted ?? this.deleted,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (localUpdatedAt.present) {
      map['local_updated_at'] = Variable<int>(localUpdatedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VaultItemsCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('localUpdatedAt: $localUpdatedAt, ')
          ..write('revision: $revision, ')
          ..write('deleted: $deleted, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KvStoreTable extends KvStore with TableInfo<$KvStoreTable, KvStoreData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvStoreTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kv_store';
  @override
  VerificationContext validateIntegrity(
    Insertable<KvStoreData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvStoreData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvStoreData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $KvStoreTable createAlias(String alias) {
    return $KvStoreTable(attachedDatabase, alias);
  }
}

class KvStoreData extends DataClass implements Insertable<KvStoreData> {
  final String key;
  final String value;
  const KvStoreData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KvStoreCompanion toCompanion(bool nullToAbsent) {
    return KvStoreCompanion(key: Value(key), value: Value(value));
  }

  factory KvStoreData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvStoreData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KvStoreData copyWith({String? key, String? value}) =>
      KvStoreData(key: key ?? this.key, value: value ?? this.value);
  KvStoreData copyWithCompanion(KvStoreCompanion data) {
    return KvStoreData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KvStoreData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvStoreData &&
          other.key == this.key &&
          other.value == this.value);
}

class KvStoreCompanion extends UpdateCompanion<KvStoreData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KvStoreCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KvStoreCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KvStoreData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KvStoreCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return KvStoreCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KvStoreCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FaviconsTable extends Favicons with TableInfo<$FaviconsTable, Favicon> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FaviconsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failedMeta = const VerificationMeta('failed');
  @override
  late final GeneratedColumn<bool> failed = GeneratedColumn<bool>(
    'failed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("failed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    host,
    bytes,
    contentType,
    fetchedAt,
    failed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favicons';
  @override
  VerificationContext validateIntegrity(
    Insertable<Favicon> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('failed')) {
      context.handle(
        _failedMeta,
        failed.isAcceptableOrUnknown(data['failed']!, _failedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {host};
  @override
  Favicon map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favicon(
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      ),
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      failed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}failed'],
      )!,
    );
  }

  @override
  $FaviconsTable createAlias(String alias) {
    return $FaviconsTable(attachedDatabase, alias);
  }
}

class Favicon extends DataClass implements Insertable<Favicon> {
  final String host;

  /// Validated image bytes; null if no usable icon was ever found.
  final Uint8List? bytes;
  final String? contentType;

  /// Time of the last fetch attempt (ms since epoch, client clock).
  final int fetchedAt;

  /// The last attempt failed. [bytes] may still hold an older icon.
  final bool failed;
  const Favicon({
    required this.host,
    this.bytes,
    this.contentType,
    required this.fetchedAt,
    required this.failed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['host'] = Variable<String>(host);
    if (!nullToAbsent || bytes != null) {
      map['bytes'] = Variable<Uint8List>(bytes);
    }
    if (!nullToAbsent || contentType != null) {
      map['content_type'] = Variable<String>(contentType);
    }
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['failed'] = Variable<bool>(failed);
    return map;
  }

  FaviconsCompanion toCompanion(bool nullToAbsent) {
    return FaviconsCompanion(
      host: Value(host),
      bytes: bytes == null && nullToAbsent
          ? const Value.absent()
          : Value(bytes),
      contentType: contentType == null && nullToAbsent
          ? const Value.absent()
          : Value(contentType),
      fetchedAt: Value(fetchedAt),
      failed: Value(failed),
    );
  }

  factory Favicon.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favicon(
      host: serializer.fromJson<String>(json['host']),
      bytes: serializer.fromJson<Uint8List?>(json['bytes']),
      contentType: serializer.fromJson<String?>(json['contentType']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      failed: serializer.fromJson<bool>(json['failed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'host': serializer.toJson<String>(host),
      'bytes': serializer.toJson<Uint8List?>(bytes),
      'contentType': serializer.toJson<String?>(contentType),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'failed': serializer.toJson<bool>(failed),
    };
  }

  Favicon copyWith({
    String? host,
    Value<Uint8List?> bytes = const Value.absent(),
    Value<String?> contentType = const Value.absent(),
    int? fetchedAt,
    bool? failed,
  }) => Favicon(
    host: host ?? this.host,
    bytes: bytes.present ? bytes.value : this.bytes,
    contentType: contentType.present ? contentType.value : this.contentType,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    failed: failed ?? this.failed,
  );
  Favicon copyWithCompanion(FaviconsCompanion data) {
    return Favicon(
      host: data.host.present ? data.host.value : this.host,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      failed: data.failed.present ? data.failed.value : this.failed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Favicon(')
          ..write('host: $host, ')
          ..write('bytes: $bytes, ')
          ..write('contentType: $contentType, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('failed: $failed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    host,
    $driftBlobEquality.hash(bytes),
    contentType,
    fetchedAt,
    failed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favicon &&
          other.host == this.host &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.contentType == this.contentType &&
          other.fetchedAt == this.fetchedAt &&
          other.failed == this.failed);
}

class FaviconsCompanion extends UpdateCompanion<Favicon> {
  final Value<String> host;
  final Value<Uint8List?> bytes;
  final Value<String?> contentType;
  final Value<int> fetchedAt;
  final Value<bool> failed;
  final Value<int> rowid;
  const FaviconsCompanion({
    this.host = const Value.absent(),
    this.bytes = const Value.absent(),
    this.contentType = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.failed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FaviconsCompanion.insert({
    required String host,
    this.bytes = const Value.absent(),
    this.contentType = const Value.absent(),
    required int fetchedAt,
    this.failed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : host = Value(host),
       fetchedAt = Value(fetchedAt);
  static Insertable<Favicon> custom({
    Expression<String>? host,
    Expression<Uint8List>? bytes,
    Expression<String>? contentType,
    Expression<int>? fetchedAt,
    Expression<bool>? failed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (host != null) 'host': host,
      if (bytes != null) 'bytes': bytes,
      if (contentType != null) 'content_type': contentType,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (failed != null) 'failed': failed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FaviconsCompanion copyWith({
    Value<String>? host,
    Value<Uint8List?>? bytes,
    Value<String?>? contentType,
    Value<int>? fetchedAt,
    Value<bool>? failed,
    Value<int>? rowid,
  }) {
    return FaviconsCompanion(
      host: host ?? this.host,
      bytes: bytes ?? this.bytes,
      contentType: contentType ?? this.contentType,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      failed: failed ?? this.failed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (failed.present) {
      map['failed'] = Variable<bool>(failed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FaviconsCompanion(')
          ..write('host: $host, ')
          ..write('bytes: $bytes, ')
          ..write('contentType: $contentType, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('failed: $failed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$VaultDatabase extends GeneratedDatabase {
  _$VaultDatabase(QueryExecutor e) : super(e);
  $VaultDatabaseManager get managers => $VaultDatabaseManager(this);
  late final $VaultItemsTable vaultItems = $VaultItemsTable(this);
  late final $KvStoreTable kvStore = $KvStoreTable(this);
  late final $FaviconsTable favicons = $FaviconsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    vaultItems,
    kvStore,
    favicons,
  ];
}

typedef $$VaultItemsTableCreateCompanionBuilder = VaultItemsCompanion Function({
  required String id,
  Value<Uint8List?> payload,
  required int localUpdatedAt,
  Value<int> revision,
  Value<bool> deleted,
  Value<bool> dirty,
  Value<int> rowid,
});
typedef $$VaultItemsTableUpdateCompanionBuilder = VaultItemsCompanion Function({
  Value<String> id,
  Value<Uint8List?> payload,
  Value<int> localUpdatedAt,
  Value<int> revision,
  Value<bool> deleted,
  Value<bool> dirty,
  Value<int> rowid,
});

class $$VaultItemsTableFilterComposer
    extends Composer<_$VaultDatabase, $VaultItemsTable> {
  $$VaultItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localUpdatedAt => $composableBuilder(
    column: $table.localUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VaultItemsTableOrderingComposer
    extends Composer<_$VaultDatabase, $VaultItemsTable> {
  $$VaultItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localUpdatedAt => $composableBuilder(
    column: $table.localUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VaultItemsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $VaultItemsTable> {
  $$VaultItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get localUpdatedAt => $composableBuilder(
    column: $table.localUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$VaultItemsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $VaultItemsTable,
          VaultItem,
          $$VaultItemsTableFilterComposer,
          $$VaultItemsTableOrderingComposer,
          $$VaultItemsTableAnnotationComposer,
          $$VaultItemsTableCreateCompanionBuilder,
          $$VaultItemsTableUpdateCompanionBuilder,
          (
            VaultItem,
            BaseReferences<_$VaultDatabase, $VaultItemsTable, VaultItem>,
          ),
          VaultItem,
          PrefetchHooks Function()
        > {
  $$VaultItemsTableTableManager(_$VaultDatabase db, $VaultItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VaultItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VaultItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VaultItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<Uint8List?> payload = const Value.absent(),
                Value<int> localUpdatedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VaultItemsCompanion(
                id: id,
                payload: payload,
                localUpdatedAt: localUpdatedAt,
                revision: revision,
                deleted: deleted,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<Uint8List?> payload = const Value.absent(),
                required int localUpdatedAt,
                Value<int> revision = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VaultItemsCompanion.insert(
                id: id,
                payload: payload,
                localUpdatedAt: localUpdatedAt,
                revision: revision,
                deleted: deleted,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$VaultItemsTable, VaultItem>(table),
                  BaseReferences<_$VaultDatabase, $VaultItemsTable, VaultItem>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VaultItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $VaultItemsTable,
      VaultItem,
      $$VaultItemsTableFilterComposer,
      $$VaultItemsTableOrderingComposer,
      $$VaultItemsTableAnnotationComposer,
      $$VaultItemsTableCreateCompanionBuilder,
      $$VaultItemsTableUpdateCompanionBuilder,
      (VaultItem, BaseReferences<_$VaultDatabase, $VaultItemsTable, VaultItem>),
      VaultItem,
      PrefetchHooks Function()
    >;
typedef $$KvStoreTableCreateCompanionBuilder = KvStoreCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$KvStoreTableUpdateCompanionBuilder = KvStoreCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$KvStoreTableFilterComposer
    extends Composer<_$VaultDatabase, $KvStoreTable> {
  $$KvStoreTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KvStoreTableOrderingComposer
    extends Composer<_$VaultDatabase, $KvStoreTable> {
  $$KvStoreTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KvStoreTableAnnotationComposer
    extends Composer<_$VaultDatabase, $KvStoreTable> {
  $$KvStoreTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KvStoreTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $KvStoreTable,
          KvStoreData,
          $$KvStoreTableFilterComposer,
          $$KvStoreTableOrderingComposer,
          $$KvStoreTableAnnotationComposer,
          $$KvStoreTableCreateCompanionBuilder,
          $$KvStoreTableUpdateCompanionBuilder,
          (
            KvStoreData,
            BaseReferences<_$VaultDatabase, $KvStoreTable, KvStoreData>,
          ),
          KvStoreData,
          PrefetchHooks Function()
        > {
  $$KvStoreTableTableManager(_$VaultDatabase db, $KvStoreTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KvStoreTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KvStoreTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KvStoreTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => KvStoreCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => KvStoreCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KvStoreTable, KvStoreData>(table),
                  BaseReferences<_$VaultDatabase, $KvStoreTable, KvStoreData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KvStoreTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $KvStoreTable,
      KvStoreData,
      $$KvStoreTableFilterComposer,
      $$KvStoreTableOrderingComposer,
      $$KvStoreTableAnnotationComposer,
      $$KvStoreTableCreateCompanionBuilder,
      $$KvStoreTableUpdateCompanionBuilder,
      (
        KvStoreData,
        BaseReferences<_$VaultDatabase, $KvStoreTable, KvStoreData>,
      ),
      KvStoreData,
      PrefetchHooks Function()
    >;
typedef $$FaviconsTableCreateCompanionBuilder = FaviconsCompanion Function({
  required String host,
  Value<Uint8List?> bytes,
  Value<String?> contentType,
  required int fetchedAt,
  Value<bool> failed,
  Value<int> rowid,
});
typedef $$FaviconsTableUpdateCompanionBuilder = FaviconsCompanion Function({
  Value<String> host,
  Value<Uint8List?> bytes,
  Value<String?> contentType,
  Value<int> fetchedAt,
  Value<bool> failed,
  Value<int> rowid,
});

class $$FaviconsTableFilterComposer
    extends Composer<_$VaultDatabase, $FaviconsTable> {
  $$FaviconsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get failed => $composableBuilder(
    column: $table.failed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FaviconsTableOrderingComposer
    extends Composer<_$VaultDatabase, $FaviconsTable> {
  $$FaviconsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get failed => $composableBuilder(
    column: $table.failed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FaviconsTableAnnotationComposer
    extends Composer<_$VaultDatabase, $FaviconsTable> {
  $$FaviconsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<bool> get failed =>
      $composableBuilder(column: $table.failed, builder: (column) => column);
}

class $$FaviconsTableTableManager
    extends
        RootTableManager<
          _$VaultDatabase,
          $FaviconsTable,
          Favicon,
          $$FaviconsTableFilterComposer,
          $$FaviconsTableOrderingComposer,
          $$FaviconsTableAnnotationComposer,
          $$FaviconsTableCreateCompanionBuilder,
          $$FaviconsTableUpdateCompanionBuilder,
          (Favicon, BaseReferences<_$VaultDatabase, $FaviconsTable, Favicon>),
          Favicon,
          PrefetchHooks Function()
        > {
  $$FaviconsTableTableManager(_$VaultDatabase db, $FaviconsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FaviconsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FaviconsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FaviconsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> host = const Value.absent(),
                Value<Uint8List?> bytes = const Value.absent(),
                Value<String?> contentType = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<bool> failed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FaviconsCompanion(
                host: host,
                bytes: bytes,
                contentType: contentType,
                fetchedAt: fetchedAt,
                failed: failed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String host,
                Value<Uint8List?> bytes = const Value.absent(),
                Value<String?> contentType = const Value.absent(),
                required int fetchedAt,
                Value<bool> failed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FaviconsCompanion.insert(
                host: host,
                bytes: bytes,
                contentType: contentType,
                fetchedAt: fetchedAt,
                failed: failed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FaviconsTable, Favicon>(table),
                  BaseReferences<_$VaultDatabase, $FaviconsTable, Favicon>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FaviconsTableProcessedTableManager =
    ProcessedTableManager<
      _$VaultDatabase,
      $FaviconsTable,
      Favicon,
      $$FaviconsTableFilterComposer,
      $$FaviconsTableOrderingComposer,
      $$FaviconsTableAnnotationComposer,
      $$FaviconsTableCreateCompanionBuilder,
      $$FaviconsTableUpdateCompanionBuilder,
      (Favicon, BaseReferences<_$VaultDatabase, $FaviconsTable, Favicon>),
      Favicon,
      PrefetchHooks Function()
    >;

class $VaultDatabaseManager {
  final _$VaultDatabase _db;
  $VaultDatabaseManager(this._db);
  $$VaultItemsTableTableManager get vaultItems =>
      $$VaultItemsTableTableManager(_db, _db.vaultItems);
  $$KvStoreTableTableManager get kvStore =>
      $$KvStoreTableTableManager(_db, _db.kvStore);
  $$FaviconsTableTableManager get favicons =>
      $$FaviconsTableTableManager(_db, _db.favicons);
}
