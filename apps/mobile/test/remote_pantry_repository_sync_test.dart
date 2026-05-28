import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/remote_pantry_repository.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _itemId = '11111111-1111-1111-1111-111111111111';
const _householdId = '22222222-2222-2222-2222-222222222222';

/// In-memory stand-in for a single PostgREST table, exercised through the real
/// [SupabaseClient] HTTP path so the conditional-write / merge logic in
/// [SupabaseRemotePantryRepository] is covered end to end.
class _FakePostgrest {
  _FakePostgrest(this.table, this.rows);

  final String table;
  final Map<String, Map<String, dynamic>> rows;
  final patches = <Map<String, dynamic>>[];

  MockClient get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final uri = request.url;
    final http.Response response;
    if (!uri.path.endsWith('/$table')) {
      response = http.Response('{}', 404);
    } else {
      response = switch (request.method) {
        'GET' => _select(uri),
        'PATCH' => _update(uri, request),
        'POST' => _upsert(request),
        _ => http.Response('{}', 405),
      };
    }
    // postgrest dereferences response.request when parsing, so echo it back.
    return http.Response(
      response.body,
      response.statusCode,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  int? _eqInt(Uri uri, String column) {
    final raw = uri.queryParameters[column];
    if (raw == null || !raw.startsWith('eq.')) return null;
    return int.tryParse(raw.substring(3));
  }

  String? _eqString(Uri uri, String column) {
    final raw = uri.queryParameters[column];
    if (raw == null || !raw.startsWith('eq.')) return null;
    return raw.substring(3);
  }

  http.Response _select(Uri uri) {
    final id = _eqString(uri, 'id');
    final row = id == null ? null : rows[id];
    return http.Response(jsonEncode(row == null ? [] : [row]), 200);
  }

  http.Response _update(Uri uri, http.Request request) {
    final id = _eqString(uri, 'id');
    final expectedVersion = _eqInt(uri, 'version');
    final row = id == null ? null : rows[id];
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    patches.add(body);
    if (id == null ||
        row == null ||
        (expectedVersion != null && row['version'] != expectedVersion)) {
      return http.Response(jsonEncode(<dynamic>[]), 200);
    }
    final updated = {...row, ...body};
    rows[id] = updated;
    final returnsRows =
        request.headers['Prefer']?.contains('return=representation') ?? false;
    return http.Response(jsonEncode(returnsRows ? [updated] : <dynamic>[]), 200);
  }

  http.Response _upsert(http.Request request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final id = body['id'] as String?;
    final ignoreDuplicates =
        request.headers['Prefer']?.contains('resolution=ignore-duplicates') ??
        false;
    if (id != null && !(ignoreDuplicates && rows.containsKey(id))) {
      rows[id] = {...?rows[id], ...body};
    }
    return http.Response('', 201);
  }
}

SupabaseRemotePantryRepository _repository(MockClient client) {
  return SupabaseRemotePantryRepository(
    SupabaseClient(
      'https://example.supabase.co',
      'publishable',
      httpClient: client,
    ),
  );
}

SyncOperation _updateOp({
  required Map<String, dynamic> patch,
  required int baseVersion,
}) {
  return SyncOperation(
    id: 'op_1',
    householdId: _householdId,
    entityType: SyncEntityType.inventoryItem,
    entityId: _itemId,
    operation: SyncOperationType.update,
    patch: patch,
    baseVersion: baseVersion,
    clientId: 'client_1',
    createdAt: DateTime.utc(2026, 5, 28),
  );
}

void main() {
  test(
    'versioned update succeeds with conditional write when version matches',
    () async {
      final fake = _FakePostgrest('inventory_items', {
        _itemId: {
          'id': _itemId,
          'household_id': _householdId,
          'name': 'Milk',
          'quantity': '1',
          'unit': 'box',
          'version': 3,
        },
      });
      final repository = _repository(fake.client);

      await repository.pushOperations([
        _updateOp(
          patch: {
            'id': _itemId,
            'name': 'Milk',
            'quantity': '2',
            'unit': 'box',
            'remoteVersion': 3,
          },
          baseVersion: 3,
        ),
      ]);

      expect(fake.rows[_itemId]!['quantity'], '2');
      // C43: version advances from the matched base, never backward.
      expect(fake.rows[_itemId]!['version'], 4);
      // Only a single conditional patch was needed (no merge re-fetch).
      expect(fake.patches, hasLength(1));
    },
  );

  test(
    'versioned update re-fetches and merges when the remote row advanced',
    () async {
      // Remote moved to version 5 (a family member edited a different field)
      // while the client still believes it is at version 3.
      final fake = _FakePostgrest('inventory_items', {
        _itemId: {
          'id': _itemId,
          'household_id': _householdId,
          'name': 'Milk',
          'quantity': '1',
          'unit': 'box',
          'category': 'Cold',
          'version': 5,
        },
      });
      final repository = _repository(fake.client);

      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      await repository.pushOperations([
        _updateOp(
          patch: {
            'id': _itemId,
            'name': 'Milk',
            'quantity': '2',
            'unit': 'box',
            'category': 'Cold',
            'remoteVersion': 3,
          },
          baseVersion: 3,
        ),
      ]);

      // Client field wins and is written on top of the latest remote row.
      expect(fake.rows[_itemId]!['quantity'], '2');
      // Remote-only field is preserved by the merge.
      expect(fake.rows[_itemId]!['category'], 'Cold');
      // C43: new version derives from the actual remote version (5 -> 6),
      // never the stale client base (which would have produced 4).
      expect(fake.rows[_itemId]!['version'], 6);
      // First conditional patch missed (version 3 != 5), second one merged.
      expect(fake.patches, hasLength(2));
      // The same-field edit (quantity) was surfaced as a resolved conflict.
      expect(errors, hasLength(1));
      expect(errors.single.exceptionAsString(), contains('quantity'));
    },
  );

  test('create uses an idempotent upsert that never downgrades a version', () async {
    final fake = _FakePostgrest('inventory_items', {
      _itemId: {
        'id': _itemId,
        'household_id': _householdId,
        'name': 'Milk',
        'version': 9,
      },
    });
    final repository = _repository(fake.client);

    await repository.pushOperations([
      SyncOperation(
        id: 'op_create',
        householdId: _householdId,
        entityType: SyncEntityType.inventoryItem,
        entityId: _itemId,
        operation: SyncOperationType.create,
        patch: const {
          'id': _itemId,
          'name': 'Milk',
          'quantity': '1',
          'unit': 'box',
        },
        clientId: 'client_1',
        createdAt: DateTime.utc(2026, 5, 28),
      ),
    ]);

    // ignoreDuplicates leaves the existing higher-version row untouched.
    expect(fake.rows[_itemId]!['version'], 9);
  });

  test(
    'toggleChecked re-fetches and re-applies on contention, bumping version',
    () async {
      final fake = _FakePostgrest('shopping_items', {
        _itemId: {
          'id': _itemId,
          'household_id': _householdId,
          'name': 'Eggs',
          'is_checked': false,
          'version': 7,
        },
      });
      final repository = _repository(fake.client);

      await repository.pushOperations([
        SyncOperation(
          id: 'op_toggle',
          householdId: _householdId,
          entityType: SyncEntityType.shoppingItem,
          entityId: _itemId,
          operation: SyncOperationType.toggleChecked,
          patch: const {'isChecked': true},
          // Stale base: remote is already at 7.
          baseVersion: 4,
          clientId: 'client_1',
          createdAt: DateTime.utc(2026, 5, 28),
        ),
      ]);

      expect(fake.rows[_itemId]!['is_checked'], true);
      expect(fake.rows[_itemId]!['version'], 8);
    },
  );
}
