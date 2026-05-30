// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $_BootstrapTable extends _Bootstrap
    with TableInfo<$_BootstrapTable, _BootstrapData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $_BootstrapTable(this.attachedDatabase, [this._alias]);
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
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bootstrap';
  @override
  VerificationContext validateIntegrity(
    Insertable<_BootstrapData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  _BootstrapData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return _BootstrapData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
    );
  }

  @override
  $_BootstrapTable createAlias(String alias) {
    return $_BootstrapTable(attachedDatabase, alias);
  }
}

class _BootstrapData extends DataClass implements Insertable<_BootstrapData> {
  final int id;
  const _BootstrapData({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    return map;
  }

  _BootstrapCompanion toCompanion(bool nullToAbsent) {
    return _BootstrapCompanion(id: Value(id));
  }

  factory _BootstrapData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return _BootstrapData(id: serializer.fromJson<int>(json['id']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'id': serializer.toJson<int>(id)};
  }

  _BootstrapData copyWith({int? id}) => _BootstrapData(id: id ?? this.id);
  _BootstrapData copyWithCompanion(_BootstrapCompanion data) {
    return _BootstrapData(id: data.id.present ? data.id.value : this.id);
  }

  @override
  String toString() {
    return (StringBuffer('_BootstrapData(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _BootstrapData && other.id == this.id);
}

class _BootstrapCompanion extends UpdateCompanion<_BootstrapData> {
  final Value<int> id;
  const _BootstrapCompanion({this.id = const Value.absent()});
  _BootstrapCompanion.insert({this.id = const Value.absent()});
  static Insertable<_BootstrapData> custom({Expression<int>? id}) {
    return RawValuesInsertable({if (id != null) 'id': id});
  }

  _BootstrapCompanion copyWith({Value<int>? id}) {
    return _BootstrapCompanion(id: id ?? this.id);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('_BootstrapCompanion(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $_BootstrapTable bootstrap = $_BootstrapTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [bootstrap];
}

typedef $$_BootstrapTableCreateCompanionBuilder =
    _BootstrapCompanion Function({Value<int> id});
typedef $$_BootstrapTableUpdateCompanionBuilder =
    _BootstrapCompanion Function({Value<int> id});

class $$_BootstrapTableFilterComposer
    extends Composer<_$AppDatabase, $_BootstrapTable> {
  $$_BootstrapTableFilterComposer({
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
}

class $$_BootstrapTableOrderingComposer
    extends Composer<_$AppDatabase, $_BootstrapTable> {
  $$_BootstrapTableOrderingComposer({
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
}

class $$_BootstrapTableAnnotationComposer
    extends Composer<_$AppDatabase, $_BootstrapTable> {
  $$_BootstrapTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$_BootstrapTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $_BootstrapTable,
          _BootstrapData,
          $$_BootstrapTableFilterComposer,
          $$_BootstrapTableOrderingComposer,
          $$_BootstrapTableAnnotationComposer,
          $$_BootstrapTableCreateCompanionBuilder,
          $$_BootstrapTableUpdateCompanionBuilder,
          (
            _BootstrapData,
            BaseReferences<_$AppDatabase, $_BootstrapTable, _BootstrapData>,
          ),
          _BootstrapData,
          PrefetchHooks Function()
        > {
  $$_BootstrapTableTableManager(_$AppDatabase db, $_BootstrapTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$_BootstrapTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$_BootstrapTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$_BootstrapTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({Value<int> id = const Value.absent()}) =>
              _BootstrapCompanion(id: id),
          createCompanionCallback: ({Value<int> id = const Value.absent()}) =>
              _BootstrapCompanion.insert(id: id),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$_BootstrapTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $_BootstrapTable,
      _BootstrapData,
      $$_BootstrapTableFilterComposer,
      $$_BootstrapTableOrderingComposer,
      $$_BootstrapTableAnnotationComposer,
      $$_BootstrapTableCreateCompanionBuilder,
      $$_BootstrapTableUpdateCompanionBuilder,
      (
        _BootstrapData,
        BaseReferences<_$AppDatabase, $_BootstrapTable, _BootstrapData>,
      ),
      _BootstrapData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$_BootstrapTableTableManager get bootstrap =>
      $$_BootstrapTableTableManager(_db, _db.bootstrap);
}
