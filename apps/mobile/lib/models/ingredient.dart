import '../models/storage_area.dart';
import 'sync_metadata.dart';

enum FreshnessState { fresh, expiringSoon, expired }

class Ingredient {
  final String id;
  final String name;
  final String quantity;
  final String unit;
  final String imageUrl;
  final double freshnessPercent;
  final FreshnessState state;
  final String? expiryLabel;
  final String? category;
  final String? barcode;
  final IconType storage;
  final DateTime? expiryDate;
  final DateTime? addedAt;
  final int? shelfLifeDays;
  final int remoteVersion;
  final DateTime? clientUpdatedAt;
  final DateTime? deletedAt;

  SyncMetadata get syncMetadata => SyncMetadata(
    remoteVersion: remoteVersion,
    clientUpdatedAt: clientUpdatedAt,
    deletedAt: deletedAt,
  );

  const Ingredient({
    this.id = '',
    required this.name,
    required this.quantity,
    required this.unit,
    required this.imageUrl,
    required this.freshnessPercent,
    required this.state,
    this.expiryLabel,
    this.category,
    this.barcode,
    this.storage = IconType.fridge,
    this.expiryDate,
    this.addedAt,
    this.shelfLifeDays,
    this.remoteVersion = 0,
    this.clientUpdatedAt,
    this.deletedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ingredient &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          quantity == other.quantity &&
          unit == other.unit &&
          imageUrl == other.imageUrl &&
          freshnessPercent == other.freshnessPercent &&
          state == other.state &&
          expiryLabel == other.expiryLabel &&
          category == other.category &&
          barcode == other.barcode &&
          storage == other.storage &&
          expiryDate == other.expiryDate &&
          addedAt == other.addedAt &&
          shelfLifeDays == other.shelfLifeDays &&
          remoteVersion == other.remoteVersion &&
          clientUpdatedAt == other.clientUpdatedAt &&
          deletedAt == other.deletedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    quantity,
    unit,
    imageUrl,
    freshnessPercent,
    state,
    expiryLabel,
    category,
    barcode,
    storage,
    expiryDate,
    addedAt,
    shelfLifeDays,
    remoteVersion,
    clientUpdatedAt,
    deletedAt,
  );

  Ingredient copyWith({
    String? id,
    String? name,
    String? quantity,
    String? unit,
    String? imageUrl,
    double? freshnessPercent,
    FreshnessState? state,
    String? expiryLabel,
    String? category,
    String? barcode,
    IconType? storage,
    DateTime? expiryDate,
    DateTime? addedAt,
    int? shelfLifeDays,
    int? remoteVersion,
    DateTime? clientUpdatedAt,
    DateTime? deletedAt,
    bool clearClientUpdatedAt = false,
    bool clearDeletedAt = false,
  }) {
    return Ingredient(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      imageUrl: imageUrl ?? this.imageUrl,
      freshnessPercent: freshnessPercent ?? this.freshnessPercent,
      state: state ?? this.state,
      expiryLabel: expiryLabel ?? this.expiryLabel,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      storage: storage ?? this.storage,
      expiryDate: expiryDate ?? this.expiryDate,
      addedAt: addedAt ?? this.addedAt,
      shelfLifeDays: shelfLifeDays ?? this.shelfLifeDays,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      clientUpdatedAt: clearClientUpdatedAt
          ? null
          : clientUpdatedAt ?? this.clientUpdatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'imageUrl': imageUrl,
      'freshnessPercent': freshnessPercent,
      'state': state.name,
      'expiryLabel': expiryLabel,
      'category': category,
      'barcode': barcode,
      'storage': storage.name,
      'expiryDate': expiryDate?.toIso8601String(),
      'addedAt': addedAt?.toIso8601String(),
      'shelfLifeDays': shelfLifeDays,
      'remoteVersion': remoteVersion,
      'clientUpdatedAt': dateTimeToJsonValue(clientUpdatedAt),
      'deletedAt': dateTimeToJsonValue(deletedAt),
    };
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    FreshnessState state;
    try {
      state = FreshnessState.values.byName(json['state'] as String? ?? 'fresh');
    } catch (_) {
      state = FreshnessState.fresh;
    }

    return Ingredient(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      quantity: json['quantity'] as String? ?? '1',
      unit: json['unit'] as String? ?? '份',
      imageUrl: json['imageUrl'] as String? ?? '',
      freshnessPercent: (json['freshnessPercent'] as num?)?.toDouble() ?? 1.0,
      state: state,
      expiryLabel: json['expiryLabel'] as String?,
      category: json['category'] as String?,
      barcode: json['barcode'] as String?,
      storage: iconTypeFromName(json['storage'] as String?),
      expiryDate: json['expiryDate'] is String
          ? DateTime.tryParse(json['expiryDate'] as String)
          : null,
      addedAt: json['addedAt'] is String
          ? DateTime.tryParse(json['addedAt'] as String)
          : null,
      shelfLifeDays: (json['shelfLifeDays'] as num?)?.toInt(),
      remoteVersion: (json['remoteVersion'] as num?)?.toInt() ?? 0,
      clientUpdatedAt: dateTimeFromJsonValue(json['clientUpdatedAt']),
      deletedAt: dateTimeFromJsonValue(json['deletedAt']),
    );
  }
}
