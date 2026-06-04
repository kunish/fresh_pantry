import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../utils/ingredient_normalizer.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';

class InventoryRepo {
  InventoryRepo(this._db);

  final AppDatabase _db;
  List<Ingredient>? _hydratedSeed;
  Map<String, dynamic> _history = const {};

  /// 预读种子(main.dart 预读注入)，保持 Notifier.build() 同步契约。
  void hydrate(List<Ingredient> seed) => _hydratedSeed = seed;

  /// 同步取一次种子；无种子时返回空(切换 household 走异步 loadAllFor)。
  List<Ingredient> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  /// 按 household 作用域异步读取(并按现有规则归一化)。
  Future<List<Ingredient>> loadAllFor(String householdId) async {
    final rows = await (_db.select(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId)))
        .get();
    final items = <Ingredient>[];
    for (final row in rows) {
      try {
        items.add(normalizeInventoryIngredient(ingredientFromRow(row)));
      } catch (_) {
        // 跳过单条坏数据，保留其余。
      }
    }
    return items;
  }

  /// 删除某 household 作用域的全部行。接管本地数据(`''` 作用域)进入家庭后
  /// 调用,清除被迁移走的原始本地行,避免它们残留为重复孤儿。
  Future<void> deleteHouseholdScope(String householdId) {
    return (_db.delete(_db.inventoryItems)
          ..where((t) => t.householdId.equals(householdId)))
        .go();
  }

  /// 事务内替换该 household 的全部行(删除 + 批量 upsert)。
  Future<void> saveItems(String householdId, List<Ingredient> items) {
    return _db.transaction(() async {
      await (_db.delete(_db.inventoryItems)
            ..where((t) => t.householdId.equals(householdId)))
          .go();
      await _db.batch((b) {
        b.insertAll(
          _db.inventoryItems,
          items.map((i) => inventoryCompanionFor(householdId, i)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  // --- add_history (本地频次记忆，非同步) ---
  Map<String, dynamic> loadHistory() => _history;

  /// 预读 history 到内存(main.dart 调用)。
  Future<void> hydrateHistory() async {
    final rows = await _db.select(_db.addHistoryEntries).get();
    _history = {
      for (final r in rows) r.name: jsonDecode(r.payloadJson),
    };
  }

  Future<void> saveHistory(Map<String, dynamic> history) async {
    _history = Map<String, dynamic>.from(history);
    await _db.transaction(() async {
      await _db.delete(_db.addHistoryEntries).go();
      await _db.batch((b) {
        b.insertAll(
          _db.addHistoryEntries,
          history.entries.map(
            (e) => AddHistoryEntriesCompanion.insert(
              name: e.key,
              payloadJson: jsonEncode(e.value),
            ),
          ),
        );
      });
    });
  }

  Future<void> clearHistory() => saveHistory(const {});

  // --- frequent-item derivation (raw history map -> domain FrequentItem) ---
  // Lives here, beside the persistence it reads, so the Notifier holds only UI
  // state and never touches the raw history-map shape — matching how inventory/
  // shopping rows are decoded in the repo (entity_row_codec), not in providers.

  /// Decodes the in-memory add-history map into domain [FrequentItem]s,
  /// enriching each with remembered category/storage/unit plus shelf-life
  /// defaults from [FoodKnowledge].
  List<FrequentItem> loadFrequentItems() => _frequentItemsFromHistory(_history);

  /// Records one intake against the frequency memory: bumps the name's count and
  /// remembers its category/storage/unit for next time.
  Future<void> recordAddition(Ingredient item) async {
    final history = Map<String, dynamic>.from(_history);
    final key = item.name;
    final existing = history[key];
    final existingCount = switch (existing) {
      {'count': final num count} => count.toInt(),
      num count => count.toInt(),
      _ => 0,
    };
    history[key] = {
      'count': existingCount + 1,
      'category': FoodCategories.normalize(item.category) ?? '',
      'storage': item.storage.name,
      'unit': item.unit,
    };
    await saveHistory(history);
  }

  /// Removes a name from the frequency memory (manual delete). No-op if absent.
  Future<void> forgetAddition(String name) async {
    final history = Map<String, dynamic>.from(_history);
    if (history.remove(name) == null) return;
    await saveHistory(history);
  }

  List<FrequentItem> _frequentItemsFromHistory(Map<String, dynamic> history) {
    return history.entries.map((e) {
      final value = e.value;
      final data = value is Map<String, dynamic> ? value : const {};
      final count = switch (value) {
        {'count': final num count} => count.toInt(),
        num count => count.toInt(),
        _ => 1,
      };
      final category = data['category'];
      final storageValue = data['storage'];
      final unit = data['unit'];
      final storageName = storageValue is String ? storageValue : 'fridge';
      final defaults = FoodKnowledge.lookup(e.key);
      final storage = iconTypeFromName(storageName);
      final rememberedCategory = category is String
          ? category
          : defaults?.category;

      return FrequentItem(
        name: e.key,
        category: FoodCategories.dropdownValue(rememberedCategory),
        storage: storage,
        unit: unit is String ? unit : '个',
        shelfLifeDays: defaults?.shelfLifeDays,
        count: count,
      );
    }).toList();
  }
}
