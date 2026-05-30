import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/ingredient.dart';
import '../../models/recipe.dart';
import '../../models/shopping_item.dart';
import '../../sync/sync_operation.dart';
// The drift-generated shopping row data class is also named `ShoppingItem`,
// which collides with the model. Hide it from the unprefixed import and reach
// it via the `db.` prefix only where the generated row type is needed.
import 'app_database.dart' hide ShoppingItem;
import 'app_database.dart' as db;

int? _epochMs(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;

// --- Inventory ---
InventoryItemsCompanion inventoryCompanionFor(String householdId, Ingredient i) {
  return InventoryItemsCompanion.insert(
    id: i.id,
    householdId: Value(householdId),
    name: Value(i.name),
    storageArea: Value(i.storage.name),
    expiryDate: Value(_epochMs(i.expiryDate)),
    remoteVersion: Value(i.remoteVersion),
    deletedAt: Value(_epochMs(i.deletedAt)),
    payloadJson: jsonEncode(i.toJson()),
  );
}

Ingredient ingredientFromPayload(String payloadJson) =>
    Ingredient.fromJson(jsonDecode(payloadJson) as Map<String, dynamic>);

Ingredient ingredientFromRow(InventoryItem row) =>
    ingredientFromPayload(row.payloadJson);

// --- Shopping ---
ShoppingItemsCompanion shoppingCompanionFor(String householdId, ShoppingItem s) {
  return ShoppingItemsCompanion.insert(
    id: s.id,
    householdId: Value(householdId),
    name: Value(s.name),
    isChecked: Value(s.isChecked),
    remoteVersion: Value(s.remoteVersion),
    deletedAt: Value(_epochMs(s.deletedAt)),
    payloadJson: jsonEncode(s.toJson()),
  );
}

ShoppingItem shoppingFromRow(db.ShoppingItem row) =>
    ShoppingItem.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>);

// --- Custom recipe ---
CustomRecipesCompanion recipeCompanionFor(String householdId, Recipe r) {
  return CustomRecipesCompanion.insert(
    id: r.id,
    householdId: Value(householdId),
    name: Value(r.name),
    remoteVersion: Value(r.remoteVersion),
    deletedAt: Value(_epochMs(r.deletedAt)),
    payloadJson: jsonEncode(r.toJson()),
  );
}

Recipe recipeFromRow(CustomRecipe row) =>
    Recipe.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>);

// --- Outbox ---
SyncOutboxCompanion outboxCompanionFor(SyncOperation op) {
  return SyncOutboxCompanion.insert(
    id: op.id,
    householdId: op.householdId,
    entityType: op.entityType.name,
    entityId: op.entityId,
    operation: op.operation.name,
    baseVersion: Value(op.baseVersion),
    clientId: op.clientId,
    createdAt: op.createdAt,
    payloadJson: jsonEncode(op.toJson()),
  );
}

SyncOperation outboxFromRow(SyncOutboxData row) =>
    SyncOperation.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>);
