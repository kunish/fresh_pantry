/// Safely cast [value] to [Map<String, dynamic>], returning null if it isn't.
Map<String, dynamic>? asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  return null;
}

/// Safely cast [value] to [List<dynamic>], returning null if it isn't.
List<dynamic>? asJsonList(dynamic value) {
  if (value is List<dynamic>) return value;
  return null;
}

/// Safely cast [value] to [String], returning null if it isn't.
String? asJsonString(dynamic value) {
  if (value is String) return value;
  return null;
}
