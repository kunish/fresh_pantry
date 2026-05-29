import 'sync_ids.dart';

/// The single home for the Supabase ⇄ domain row mapping.
///
/// Each entity's columns are declared once as a [_Column] list; both the
/// decode (Supabase row → domain JSON map) and encode (domain JSON map →
/// Supabase row) directions derive from that one list, so renaming a column is
/// a one-line change instead of two functions to keep in sync. The
/// round-trip is pinned by `remote_row_codec_test.dart`.

/// One column's mapping. [column] is the snake_case Supabase name, [key] the
/// camelCase domain key. [decode]/[encode] apply per-direction defaults and
/// type coercions; a null transform passes the value through unchanged.
class _Column {
  const _Column(this.column, this.key, {this.decode, this.encode});

  final String column;
  final String key;
  final Object? Function(Object? value)? decode;
  final Object? Function(Object? value)? encode;
}

// Per-direction value transforms, named so the column tables read declaratively.
Object? _orEmpty(Object? v) => v ?? '';
Object? _orFresh(Object? v) => v ?? 'fresh';
Object? _orFridge(Object? v) => v ?? 'fridge';
Object? _orOne(Object? v) => v ?? 1.0;
Object? _orOther(Object? v) => v ?? '其他';
Object? _orFalse(Object? v) => v ?? false;
Object? _toDouble1(Object? v) => (v as num?)?.toDouble() ?? 1.0;
Object? _toInt0(Object? v) => (v as num?)?.toInt() ?? 0;

/// Local rows start at version 1; an upsert never writes version 0 (which would
/// be read back as "local-only" and re-uploaded forever).
int versionForUpsert(Object? remoteVersion) {
  final version = remoteVersion is num ? remoteVersion.toInt() : 0;
  return version <= 0 ? 1 : version;
}

// Sync columns common to every entity.
const _versionCol = _Column(
  'version',
  'remoteVersion',
  decode: _toInt0,
  encode: versionForUpsert,
);
const _clientUpdatedCol = _Column('client_updated_at', 'clientUpdatedAt');
const _deletedCol = _Column('deleted_at', 'deletedAt');

/// Decodes/encodes a row whose columns map straight onto domain keys. `id` is
/// handled outside the table: always read on decode, written on encode only
/// when it is a sync UUID (so the database default fills local-only ids).
class _RowMap {
  const _RowMap(this.columns);

  final List<_Column> columns;

  Map<String, dynamic> fromRow(Map<String, dynamic> row) {
    final domain = <String, dynamic>{'id': row['id']};
    for (final c in columns) {
      final raw = row[c.column];
      domain[c.key] = c.decode == null ? raw : c.decode!(raw);
    }
    return domain;
  }

  Map<String, dynamic> toRow(String householdId, Map<String, dynamic> item) {
    final row = <String, dynamic>{'household_id': householdId};
    for (final c in columns) {
      final raw = item[c.key];
      row[c.column] = c.encode == null ? raw : c.encode!(raw);
    }
    _applyLocalId(row, item['id']);
    return row;
  }
}

void _applyLocalId(Map<String, dynamic> row, Object? id) {
  if (id is String && isUuid(id)) row['id'] = id;
}

const _inventoryRowMap = _RowMap([
  _Column('name', 'name'),
  _Column('quantity', 'quantity'),
  _Column('unit', 'unit'),
  _Column('image_url', 'imageUrl', decode: _orEmpty, encode: _orEmpty),
  _Column(
    'freshness_percent',
    'freshnessPercent',
    decode: _toDouble1,
    encode: _orOne,
  ),
  _Column('state', 'state', decode: _orFresh, encode: _orFresh),
  _Column('expiry_label', 'expiryLabel'),
  _Column('category', 'category'),
  _Column('barcode', 'barcode'),
  _Column('storage', 'storage', encode: _orFridge),
  _Column('expiry_date', 'expiryDate'),
  _Column('added_at', 'addedAt'),
  _Column('shelf_life_days', 'shelfLifeDays'),
  _versionCol,
  _clientUpdatedCol,
  _deletedCol,
]);

const _shoppingRowMap = _RowMap([
  _Column('name', 'name'),
  _Column('detail', 'detail', decode: _orEmpty, encode: _orEmpty),
  _Column('image_url', 'imageUrl'),
  _Column('category', 'category', decode: _orOther, encode: _orOther),
  _Column('is_checked', 'isChecked', decode: _orFalse, encode: _orFalse),
  _versionCol,
  _clientUpdatedCol,
  _deletedCol,
]);

Map<String, dynamic> inventoryRowFromJson(Map<String, dynamic> row) =>
    _inventoryRowMap.fromRow(row);

Map<String, dynamic> inventoryRowForUpsert(
  String householdId,
  Map<String, dynamic> item,
) => _inventoryRowMap.toRow(householdId, item);

Map<String, dynamic> shoppingRowFromJson(Map<String, dynamic> row) =>
    _shoppingRowMap.fromRow(row);

Map<String, dynamic> shoppingRowForUpsert(
  String householdId,
  Map<String, dynamic> item,
) => _shoppingRowMap.toRow(householdId, item);

// Custom recipes carry their fields in an opaque `payload` blob rather than as
// columns, so they keep an explicit mapping — only id and the sync columns are
// real columns.
Map<String, dynamic> customRecipeRowFromJson(Map<String, dynamic> row) {
  final payload = row['payload'];
  final recipe = payload is Map
      ? Map<String, dynamic>.from(payload)
      : <String, dynamic>{};
  return {
    ...recipe,
    'id': row['id'] ?? recipe['id'],
    'remoteVersion': _toInt0(row['version']),
    'clientUpdatedAt': row['client_updated_at'],
    'deletedAt': row['deleted_at'],
  };
}

Map<String, dynamic> customRecipeRowForUpsert(
  String householdId,
  Map<String, dynamic> recipe,
) {
  final row = <String, dynamic>{
    'household_id': householdId,
    'payload': recipe,
    'version': versionForUpsert(recipe['remoteVersion']),
    'client_updated_at': recipe['clientUpdatedAt'],
    'deleted_at': recipe['deletedAt'],
  };
  _applyLocalId(row, recipe['id']);
  return row;
}
