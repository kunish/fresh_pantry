enum SyncEntityType {
  inventoryItem,
  shoppingItem,
  customRecipe,
  mealPlanEntry,
  householdConfig,
}

enum SyncOperationType {
  create,
  update,
  delete,
  intake,
  deduction,
  toggleChecked,
}

class SyncOperation {
  SyncOperation({
    required this.id,
    required this.householdId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required Map<String, dynamic> patch,
    this.baseVersion,
    required this.clientId,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastError,
  }) : patch = _deepFreezeObject(patch);

  final String id;
  final String householdId;
  final SyncEntityType entityType;
  final String entityId;
  final SyncOperationType operation;
  final Map<String, dynamic> patch;
  final int? baseVersion;
  final String clientId;
  final DateTime createdAt;
  final int attemptCount;
  final String? lastError;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'householdId': householdId,
      'entityType': entityType.name,
      'entityId': entityId,
      'operation': operation.name,
      'patch': _deepCloneObject(patch),
      'baseVersion': baseVersion,
      'clientId': clientId,
      'createdAt': createdAt.toIso8601String(),
      'attemptCount': attemptCount,
      'lastError': lastError,
    };
  }

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    try {
      return SyncOperation(
        id: _requiredString(json, 'id'),
        householdId: _requiredString(json, 'householdId'),
        entityType: _requiredEnum(
          json,
          'entityType',
          SyncEntityType.values.byName,
        ),
        entityId: _requiredString(json, 'entityId'),
        operation: _requiredEnum(
          json,
          'operation',
          SyncOperationType.values.byName,
        ),
        patch: _requiredObject(json, 'patch'),
        baseVersion: _optionalInt(json, 'baseVersion'),
        clientId: _requiredString(json, 'clientId'),
        createdAt: _requiredDateTime(json, 'createdAt'),
        attemptCount: _optionalInt(json, 'attemptCount') ?? 0,
        lastError: _optionalString(json, 'lastError'),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid sync operation: $error');
    }
  }

  @override
  bool operator ==(Object other) {
    return other is SyncOperation &&
        id == other.id &&
        householdId == other.householdId &&
        entityType == other.entityType &&
        entityId == other.entityId &&
        operation == other.operation &&
        _jsonValueEquals(patch, other.patch) &&
        baseVersion == other.baseVersion &&
        clientId == other.clientId &&
        createdAt == other.createdAt &&
        attemptCount == other.attemptCount &&
        lastError == other.lastError;
  }

  @override
  int get hashCode => Object.hash(
    id,
    householdId,
    entityType,
    entityId,
    operation,
    _jsonValueHash(patch),
    baseVersion,
    clientId,
    createdAt,
    attemptCount,
    lastError,
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Missing required sync operation field: $key');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Invalid sync operation field: $key');
}

T _requiredEnum<T>(
  Map<String, dynamic> json,
  String key,
  T Function(String) parse,
) {
  return parse(_requiredString(json, key));
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toInt();
  throw FormatException('Invalid sync operation field: $key');
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _requiredString(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed != null) return parsed;
  throw FormatException('Invalid sync operation field: $key');
}

Map<String, dynamic> _requiredObject(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('Invalid sync operation field: $key');
  }
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _deepFreezeObject(Map<String, dynamic> value) {
  return Map.unmodifiable(
    value.map((key, nested) => MapEntry(key, _deepFreezeValue(nested))),
  );
}

Object? _deepFreezeValue(Object? value) {
  if (value is Map) {
    return _deepFreezeObject(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return List.unmodifiable(value.map(_deepFreezeValue));
  }
  return value;
}

Map<String, dynamic> _deepCloneObject(Map<String, dynamic> value) {
  return value.map((key, nested) => MapEntry(key, _deepCloneValue(nested)));
}

Object? _deepCloneValue(Object? value) {
  if (value is Map) {
    return _deepCloneObject(Map<String, dynamic>.from(value));
  }
  if (value is List) {
    return value.map(_deepCloneValue).toList(growable: true);
  }
  return value;
}

bool _jsonValueEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) return false;
      if (!_jsonValueEquals(entry.value, right[entry.key])) return false;
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i += 1) {
      if (!_jsonValueEquals(left[i], right[i])) return false;
    }
    return true;
  }
  return left == right;
}

int _jsonValueHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) => Object.hash(entry.key, _jsonValueHash(entry.value)),
      ),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_jsonValueHash));
  }
  return value.hashCode;
}
