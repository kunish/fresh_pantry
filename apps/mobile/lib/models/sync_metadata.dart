DateTime? dateTimeFromJsonValue(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}

String? dateTimeToJsonValue(DateTime? value) => value?.toIso8601String();

class SyncMetadata {
  const SyncMetadata({
    this.remoteVersion = 0,
    this.clientUpdatedAt,
    this.deletedAt,
  });

  final int remoteVersion;
  final DateTime? clientUpdatedAt;
  final DateTime? deletedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncMetadata &&
          runtimeType == other.runtimeType &&
          remoteVersion == other.remoteVersion &&
          clientUpdatedAt == other.clientUpdatedAt &&
          deletedAt == other.deletedAt;

  @override
  int get hashCode => Object.hash(
    remoteVersion,
    clientUpdatedAt,
    deletedAt,
  );
}
