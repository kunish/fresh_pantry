# persistence-drift (`storage`)

**Effort:** L

## 概述

The local persistence layer has two halves. (1) A Drift/SQLite database (`fresh_pantry`, schemaVersion 5) backs the four sync-able domain entities (inventory, shopping, custom recipes, meal-plan entries), an append-only food-departure log, the sync outbox, and a non-synced add-history (frequency memory) table. Every sync entity table stores a denormalized JSON payload column plus a handful of queryable/indexable columns (id, householdId, name, version, deletedAt, plus entity-specific date columns). All rows are household-scoped by a `householdId` text column where `''` means local-only/not-yet-shared. (2) A simpler key-value layer (`StorageAdapter` over SharedPreferences, or in-memory for tests) backs settings-style blobs (AI settings, reminder settings, favorites, dietary exclusions, scheduled notification ids, the food-details cache, and the in-progress intake-review draft). Each Drift repo follows an identical pattern: a one-shot synchronous `hydrate`/`loadAll` seed (read once at startup so Riverpod notifier `build()` stays sync) plus async `loadAllFor(householdId)` / `saveItems(householdId, ...)` that replace the entire scope inside a transaction. A one-time `blob_to_drift_migration` imports legacy SharedPreferences JSON blobs into Drift. For the Swift rewrite these map to SwiftData @Model types (one per table) plus a small UserDefaults-backed settings store, with the JSON payload retained for sync parity.

## 组件(21)

### lib/storage/drift/app_database.dart

_Drift database definition: all 7 tables, schemaVersion, full migration strategy (v1→v5), index creation, and inventory dedup SQL._

schemaVersion = 5. DB file name 'fresh_pantry' in applicationSupportDirectory (native). 7 tables. SQL column names are snake_case of the Dart getter.

TABLE inventory_items (class InventoryItems): rowPk INTEGER AUTOINCREMENT PRIMARY KEY (surrogate — sync id is NOT the PK because local-only rows share an empty id and an id-PK would collapse them); id TEXT NOT NULL; household_id TEXT NOT NULL DEFAULT ''; name TEXT NOT NULL DEFAULT ''; storage_area TEXT NULLABLE; expiry_date INTEGER NULLABLE (epoch ms); remote_version INTEGER NOT NULL DEFAULT 0; deleted_at INTEGER NULLABLE (epoch ms); payload_json TEXT NOT NULL. Indexes: inventory_household_idx ON (household_id); PARTIAL UNIQUE inventory_id_unique ON (id) WHERE id != '' (local-only blank ids allowed to repeat).

TABLE shopping_items (ShoppingItems): id TEXT PRIMARY KEY; household_id TEXT NOT NULL DEFAULT ''; name TEXT NOT NULL DEFAULT ''; is_checked BOOLEAN NOT NULL DEFAULT 0(false); remote_version INTEGER NOT NULL DEFAULT 0; deleted_at INTEGER NULLABLE; payload_json TEXT NOT NULL. Index: shopping_household_idx ON (household_id).

TABLE custom_recipes (CustomRecipes): id TEXT PRIMARY KEY; household_id TEXT NOT NULL DEFAULT ''; name TEXT NOT NULL DEFAULT ''; remote_version INTEGER NOT NULL DEFAULT 0; deleted_at INTEGER NULLABLE; payload_json TEXT NOT NULL. Index: recipes_household_idx ON (household_id).

TABLE meal_plan_entries (MealPlanEntries, @DataClassName('MealPlanRow')): id TEXT PRIMARY KEY; household_id TEXT NOT NULL DEFAULT ''; name TEXT NOT NULL DEFAULT '' (holds recipeName); remote_version INTEGER NOT NULL DEFAULT 0; deleted_at INTEGER NULLABLE; payload_json TEXT NOT NULL. Index: meal_plan_household_idx ON (household_id).

TABLE food_log_entries (FoodLogEntries, @DataClassName('FoodLogRow')): id TEXT PRIMARY KEY; household_id TEXT NOT NULL DEFAULT ''; name TEXT NOT NULL DEFAULT ''; logged_at INTEGER NULLABLE (epoch ms, queryable for bounded recent-window stats); remote_version INTEGER NOT NULL DEFAULT 0; deleted_at INTEGER NULLABLE; payload_json TEXT NOT NULL. Composite index food_log_household_logged_idx ON (household_id, logged_at). Append-only / unbounded growth.

TABLE sync_outbox (SyncOutbox): id TEXT PRIMARY KEY; household_id TEXT NOT NULL; entity_type TEXT NOT NULL; entity_id TEXT NOT NULL; operation TEXT NOT NULL; base_version INTEGER NULLABLE; client_id TEXT NOT NULL; created_at DATETIME NOT NULL (stored as epoch seconds by Drift default); payload_json TEXT NOT NULL (full SyncOperation.toJson()). Index: outbox_created_idx ON (created_at).

TABLE add_history_entries (AddHistoryEntries): name TEXT PRIMARY KEY (frequency-memory key); payload_json TEXT NOT NULL ({count,category,storage,unit}). NOT synced. No household scope.

MIGRATION STRATEGY:
- onCreate: createAll() then _createIndexes() (all six index statements).
- onUpgrade(from,to):
  * from<2: v1 used sync id as inventory PK (collided for blank-id local rows). Rename inventory_items→inventory_items_v1, recreate inventory_items (new surrogate rowPk), INSERT...SELECT copying id,household_id,name,storage_area,expiry_date,remote_version,deleted_at,payload_json (each gets fresh rowPk so colliding blank-id rows all survive), DROP inventory_items_v1, create inventory_household_idx.
  * from<3: _dedupeInventory() then _createInventoryIdUniqueIndex().
  * from<4: createTable(mealPlanEntries) + meal_plan_household_idx.
  * from<5: createTable(foodLogEntries) + food_log_household_logged_idx.

_dedupeInventory() runs 4 SQL statements (smallest id / earliest rowPk wins to match server cleanup):
  1a. DELETE FROM inventory_items WHERE household_id='' AND id!='' AND id IN (SELECT id FROM inventory_items WHERE household_id!='') — drop '' orphans whose id exists in a real household.
  1a'. DELETE '' orphans that duplicate a household item by name + payload_json $.addedAt (only when addedAt present), via EXISTS against a household row with matching name and addedAt.
  1b. DELETE WHERE id!='' AND row_pk NOT IN (SELECT MIN(row_pk) ... GROUP BY id) — collapse exact-id dups keeping earliest.
  2. Collapse re-minted clones: self-join on same household_id + name + json_extract addedAt (addedAt must be non-null), delete the row whose paired b.id < a.id (keep smallest id).

_createInventoryIdUniqueIndex(): CREATE UNIQUE INDEX IF NOT EXISTS inventory_id_unique ON inventory_items (id) WHERE id != ''.

### lib/storage/drift/entity_row_codec.dart

_Pure functions mapping each domain model <-> its Drift companion/row. Owns the column-vs-payload split and epoch-ms conversion._

Helper: _epochMs(DateTime?) => value?.toUtc().millisecondsSinceEpoch (UTC, nullable passthrough).

Inventory: inventoryCompanionFor(householdId, Ingredient i) -> InventoryItemsCompanion.insert(id: i.id, householdId, name: i.name, storageArea: i.storage.name, expiryDate: _epochMs(i.expiryDate), remoteVersion: i.remoteVersion, deletedAt: _epochMs(i.deletedAt), payloadJson: jsonEncode(i.toJson())). ingredientFromRow(row) = Ingredient.fromJson(jsonDecode(row.payloadJson)). (rowPk left absent -> autoincrement.)

Shopping: shoppingCompanionFor(householdId, ShoppingItem s) sets id,householdId,name,isChecked: s.isChecked,remoteVersion,deletedAt,payloadJson. shoppingFromRow(db.ShoppingItem row) = ShoppingItem.fromJson(payloadJson). Note name collision: the generated Drift row class is ShoppingItem too — handled with `hide ShoppingItem` + `as db` prefix.

Custom recipe: recipeCompanionFor(householdId, Recipe r) sets id,householdId,name,remoteVersion,deletedAt,payloadJson. recipeFromRow(CustomRecipe row) = Recipe.fromJson(payloadJson).

Meal plan: mealPlanCompanionFor(householdId, MealPlanEntry e) sets id,householdId, name: e.recipeName (note: column 'name' stores recipeName), remoteVersion,deletedAt,payloadJson. mealPlanFromRow(MealPlanRow row) = MealPlanEntry.fromJson(payloadJson).

Food log: foodLogCompanionFor(householdId, FoodLogEntry e) sets id,householdId,name, loggedAt: _epochMs(e.loggedAt), remoteVersion,deletedAt,payloadJson. foodLogFromRow(FoodLogRow row) = FoodLogEntry.fromJson(payloadJson).

Outbox: outboxCompanionFor(SyncOperation op) sets id, householdId, entityType: op.entityType.name, entityId, operation: op.operation.name, baseVersion, clientId, createdAt, payloadJson: jsonEncode(op.toJson()). outboxFromRow(SyncOutboxData row) = SyncOperation.fromJson(payloadJson).

KEY INVARIANT: the indexed columns (name, storage_area, expiry_date, is_checked, remote_version, deleted_at, logged_at, entity_type, etc.) are projections of the JSON payload; payload_json is the source of truth for the full object. On decode, only payload_json is read — the scalar columns exist purely for querying/indexing/sorting.

### lib/storage/inventory_repo.dart

_Inventory CRUD + non-synced add-history (frequency memory) persistence + FrequentItem derivation._

InventoryRepo(AppDatabase). State: _hydratedSeed (List<Ingredient>?), _history (Map<String,dynamic>).
Public API:
- hydrate(List<Ingredient> seed): one-shot seed for sync notifier build().
- loadAll() -> List<Ingredient>: returns seed once then nulls it (empty otherwise).
- loadAllFor(String householdId) async -> List<Ingredient>: SELECT WHERE household_id = householdId; per-row try { normalizeInventoryIngredient(ingredientFromRow(row)) } catch skip; returns survivors. (normalizeInventoryIngredient lives in utils/ingredient_normalizer.dart.)
- deleteHouseholdScope(String householdId): DELETE WHERE household_id = householdId (used when adopting local '' data into a household).
- saveItems(String householdId, List<Ingredient>): transaction { DELETE scope; batch insertAll(insertOrReplace) all items via inventoryCompanionFor }.
- loadHistory() -> Map (in-memory _history).
- hydrateHistory() async: SELECT add_history_entries; build map {row.name: jsonDecode(row.payloadJson)}.
- saveHistory(Map) async: sets _history then transaction { DELETE all add_history_entries; batch insertAll AddHistoryEntriesCompanion.insert(name, payloadJson: jsonEncode(value)) }.
- clearHistory() = saveHistory({}).
- loadFrequentItems() -> List<FrequentItem>: derive from _history.
- recordAddition(Ingredient item) async: bump history[name].count (+1), store {count, category: FoodCategories.normalize(item.category)??'', storage: item.storage.name, unit: item.unit}; existing count read tolerant of either {count:n} map or bare number.
- forgetAddition(String name) async: history.remove(name); no-op if absent.
_frequentItemsFromHistory: each entry -> FrequentItem(name, category: FoodCategories.dropdownValue(rememberedCategory ?? FoodKnowledge defaults.category), storage: iconTypeFromName(storage||'fridge'), unit: unit||'个', shelfLifeDays: FoodKnowledge.lookup(name)?.shelfLifeDays, count). count fallback 1 when value is a plain non-count map.

### lib/storage/shopping_repo.dart

_Shopping-list CRUD with category normalization + name-based dedup on load._

ShoppingRepo(AppDatabase). _hydratedSeed (List<ShoppingItem>?).
- hydrate / loadAll: same one-shot seed pattern.
- loadAllFor(householdId) async: SELECT WHERE household_id; per-row try { normalizeShoppingItemCategory(shoppingFromRow(row)) } catch skip; then return deduplicateShoppingItems(items) (see shopping_item_normalizer).
- deleteHouseholdScope(householdId): DELETE scope.
- saveItems(householdId, items): transaction { DELETE scope; batch insertAll(insertOrReplace, shoppingCompanionFor) }.
Imports drift/app_database.dart with `hide ShoppingItem` to avoid the generated-row name collision.

### lib/storage/custom_recipe_repo.dart

_User-created recipe CRUD; filters out rows with empty id or name._

CustomRecipeRepo(AppDatabase). _hydratedSeed (List<Recipe>?).
- hydrate / loadAll: one-shot seed.
- loadAllFor(householdId) async: SELECT WHERE household_id; per-row try { recipe=recipeFromRow(row); add only if recipe.id.isNotEmpty && recipe.name.isNotEmpty } catch skip.
- deleteHouseholdScope(householdId): DELETE scope.
- saveRecipes(householdId, recipes): transaction { DELETE scope; batch insertAll(insertOrReplace) of recipes WHERE id.isNotEmpty && name.isNotEmpty via recipeCompanionFor }. Both load and save enforce the non-empty id+name guard.

### lib/storage/meal_plan_repo.dart

_Weekly meal-plan entry CRUD; filters rows missing id or recipeId._

MealPlanRepo(AppDatabase). _hydratedSeed (List<MealPlanEntry>?).
- hydrate / loadAll: one-shot seed.
- loadAllFor(householdId) async: SELECT WHERE household_id; per-row try { entry=mealPlanFromRow(row); add only if entry.id.isNotEmpty && entry.recipeId.isNotEmpty } catch skip (e.g. missing/unparseable date).
- deleteHouseholdScope(householdId): DELETE scope.
- saveEntries(householdId, entries): transaction { DELETE scope; batch insertAll(insertOrReplace) of entries WHERE id.isNotEmpty && recipeId.isNotEmpty via mealPlanCompanionFor }.

### lib/storage/food_log_repo.dart

_Append-only food-departure log: append, bounded recent-window load, point delete, full load, replace-all._

FoodLogRepo(AppDatabase). _hydratedSeed (List<FoodLogEntry>?).
- hydrate / loadAll: one-shot seed.
- append(householdId, FoodLogEntry entry) async: NO-OP if entry.id.isEmpty (never write an unaddressable row); else INSERT(insertOrReplace) foodLogCompanionFor. (Single insert, not transactional.)
- loadAllFor(householdId) async: SELECT WHERE household_id; _decode.
- loadRecentFor(householdId, {required int sinceMs}) async: SELECT WHERE household_id == householdId AND logged_at >= sinceMs; _decode. Used by the stats provider to avoid scanning unbounded history.
- deleteEntry(householdId, String id): DELETE WHERE household_id AND id == id. CRITICAL: point-delete (used to reverse a log when a removal is undone); must NOT use saveEntries which would drop window-outside history.
- deleteHouseholdScope(householdId): DELETE scope.
- saveEntries(householdId, entries): transaction { DELETE scope; batch insertAll(insertOrReplace) of entries WHERE id.isNotEmpty } (sync apply / backup import).
- _decode(List<FoodLogRow>): per-row try { entry=foodLogFromRow(row); add if id.isNotEmpty } catch skip.

### lib/storage/food_details_repo.dart

_Online food-details lookup with a versioned JSON cache stored via StorageAdapter; local fallback generation; placeholder-description authority._

Constants: foodDetailsCacheStorageKey='food_details_cache'; _localFoodDetailsSource='本地食材知识库'; _foodDetailsCacheVersion=5 (must equal FoodDetails.toJson cacheVersion — bumped when nutrition added in v5; v4 caches re-fetched).
foodDetailsCacheKeyFor(Ingredient): if barcode non-blank -> 'barcode:<barcode>'; else 'name:<normalizeCacheKey(name)>'.
FoodDetailsRepository({StorageAdapter storage, FoodDetailsClient client}). In-memory cache of raw+decoded cache map (_cachedRawCache/_cachedDecodedCache).
- detailsFor(Ingredient) async -> FoodDetails: read cache map; if cached value exists, is current cacheVersion, and is NOT a local fallback -> return it. Else try client.lookup (catch -> null); details = fetched ?? cachedDetails ?? fallbackFoodDetailsFor(ingredient). If details is a local fallback -> return WITHOUT persisting (don't mask missing online data / avoid full-map rewrite). Else cache[key]=details.toJson(); jsonEncode; storage.write(key); update in-mem caches; return.
- _readCache(): read raw blob; empty -> {}; if raw==_cachedRawCache return cached decoded copy; else jsonDecode (Map -> map, else {}).
_isLocalFallback(d) = d.source == '本地食材知识库'. _isCurrentCacheValue(v) = v['cacheVersion']==5.
fallbackFoodDetailsFor(Ingredient, {DateTime? now}): uses FoodKnowledge.lookup(name) for category/storage/shelfLifeDays defaults, builds FoodDetails(displayName, description via _fallbackDescription, imageUrl via _fallbackImageUrl, category, storage, shelfLifeDays, source='本地食材知识库', fetchedAt: now??DateTime.now()).
_fallbackDescription(storage, shelfLifeDays): if shelfLifeDays>0 -> '建议存放在<label>，约 <n> 天内食用。' else '暂无联网详情，已保留本地库存中的食材信息。'.
_fallbackImageUrl: saved imageUrl if non-blank; else FoodKnowledge.englishName -> slug (lowercase, spaces->_) -> 'https://www.themealdb.com/images/ingredients/<slug>.png'; null if no english name.
isPlaceholderFoodDescription(String): the single authority — true if empty, starts with 'Open Food Facts 记录的' & ends '食品。', starts with '建议存放在', or starts with '暂无联网详情'. Must stay in sync with OFF service + _fallbackDescription producers.

### lib/storage/favorite_recipes_repo.dart

_Persist favorited recipe ids as JSON string array via StorageAdapter._

storageKey='favorite_recipe_ids'. FavoriteRecipesRepo(StorageAdapter).
- load() -> Set<String>: read key; null/empty -> {}; jsonDecode; if not List -> {}; keep whereType<String> & non-empty -> toSet; catch -> {}.
- save(Set<String> ids): write(key, jsonEncode(ids.toList())). Synchronous (fire-and-forget write).

### lib/storage/dietary_preferences_repo.dart

_Persist avoided-ingredient keywords (忌口) as JSON string array via StorageAdapter._

storageKey='dietary_exclusions'. DietaryPreferencesRepo(StorageAdapter).
- load() -> Set<String>: same defensive decode as favorites (null/empty/non-List/catch -> {}; keep non-empty strings).
- save(Set<String> keywords): write jsonEncode(toList()). Keywords stored as-is; trim+lowercase normalization owned by the notifier, not here.

### lib/storage/reminder_settings_repo.dart

_Persist ReminderSettings JSON blob via StorageAdapter._

storageKey='reminder_settings_v1'. ReminderSettingsRepo(StorageAdapter).
- load() -> ReminderSettings: null/empty/malformed -> const ReminderSettings(); else ReminderSettings.fromJson(jsonDecode(raw)).
- save(ReminderSettings) async -> Future: write(key, jsonEncode(settings.toJson())). (ReminderSettings shape owned by models subsystem.)

### lib/storage/ai_settings_repo.dart

_Persist AiSettings JSON blob via StorageAdapter._

storageKey='ai_settings_v1'. AiSettingsRepo(StorageAdapter).
- load() -> AiSettings: null/empty/malformed -> AiSettings.empty; else AiSettings.fromJson(jsonDecode(raw)).
- save(AiSettings): write(key, jsonEncode(settings.toJson())). Synchronous. (AiSettings shape owned by models/ai subsystem — likely includes API base url / key / model; treat as secrets in Swift.)

### lib/storage/scheduled_notification_ids_repo.dart

_Persist the set of OS notification ids scheduled this session so a later resync can cancel stale ones._

storageKey='notification_sync_scheduled_ids_v1'. ScheduledNotificationIdsRepo(StorageAdapter).
- load() -> List<int>: null/empty/malformed -> const []; else (jsonDecode as List).cast<int>().
- save(List<int> ids) async -> Future: write jsonEncode(ids).

### lib/storage/intake_review_draft_repo.dart

_Persist the in-progress Intake Review draft (List<IntakeProposal>) as a JSON array; owns the proposal<->JSON codec._

storageKey='intake_review_draft'. IntakeReviewDraftRepo(StorageAdapter).
- load() -> List<IntakeProposal>: null/empty/malformed -> const []; else (jsonDecode as List).cast<Map>().map(_fromJson).
- save(List<IntakeProposal>) async: if empty -> adapter.remove(key) (so no stale draft lingers); else write jsonEncode(map(_toJson)).
_toJson per proposal: {id, name, quantity, unit, category, storage: p.storage.name, shelfLifeDays, action: p.action.name, mergeTargetId, mergeTargetLabel, origin: p.origin.name, userEdited, selected}.
_fromJson defaults: name '' ; quantity '1'; unit '个'; category String?; storage via iconTypeFromName(json['storage']); shelfLifeDays int?; action IntakeAction.values.byName(?? newRow); mergeTargetId/Label String?; origin FieldOrigin.values.byName(?? ai); userEdited bool ?? false; selected bool ?? true. id is required (cast as String).

### lib/storage/local_recipe_repository.dart

_Load bundled HowToCook Chinese recipes from a JSON asset, cached per instance._

howtocookAssetKey='assets/recipes/howtocook.json'. LocalRecipeRepository({Future<String> Function(String)? loadString}) defaults to rootBundle.loadString. _cache (List<Recipe>?).
- loadAll() async -> List<Recipe>: return cache if present; load asset; jsonDecode; must be List else FormatException; per-entry (whereType<Map>) try Recipe.fromJson(entry) catch debugPrint+skip; cache + return. Read-only, no writes. In Swift this becomes a bundled JSON resource decoded once.

### lib/storage/blob_to_drift_migration.dart

_One-time idempotent import of legacy SharedPreferences JSON blobs into Drift._

migratedFlagKey='drift_migrated_v1'. Legacy keys (preserved, not deleted, for one release as rollback): legacyInventoryKey='inventory_items', legacyShoppingKey='shopping_items', legacyRecipesKey='custom_recipes', legacyOutboxKey='sync_outbox_v1', legacyHistoryKey='add_history'.
migratePrefsBlobsToDrift({SharedPreferences prefs, AppDatabase db}) async: if prefs.getBool(migratedFlagKey)==true return. Decode each list leniently (per-entry try/skip):
- inventory: Ingredient.fromJson, then .where(name.trim().isNotEmpty) (filter by NAME not id — local rows legitimately have blank id; blank name = junk blob).
- shopping: ShoppingItem.fromJson, where(name.trim().isNotEmpty).
- recipes: Recipe.fromJson, where(id.isNotEmpty && name.isNotEmpty).
- ops: SyncOperation.fromJson (no filter).
- history: _decodeMap.
Then write into '' (local-only) scope: InventoryRepo(db).saveItems('', inventory); ShoppingRepo(db).saveItems('', shopping); CustomRecipeRepo(db).saveRecipes('', recipes); SyncOutboxRepo(db).replaceAll(ops); if history non-empty InventoryRepo(db).saveHistory(history). Finally prefs.setBool(migratedFlagKey, true) ONLY after all writes succeed (a mid-flight throw leaves flag unset so a later run retries). _decodeList/_decodeMap return const [] / const {} on any decode failure or wrong type.

### lib/storage/storage_adapter.dart

_Abstract KV storage seam: read/write/remove String values._

abstract class StorageAdapter { String? read(String key); Future<void> write(String key, String value); Future<void> remove(String key); }. read is synchronous; write/remove async fire-and-forget (callers don't block). Two impls: SharedPrefs (prod) and InMemory (tests).

### lib/storage/shared_prefs_storage_adapter.dart

_Production StorageAdapter backed by SharedPreferences._

SharedPrefsStorageAdapter(SharedPreferences _prefs). read=_prefs.getString(key); write=await _prefs.setString(key,value); remove=await _prefs.remove(key).

### lib/storage/in_memory_storage_adapter.dart

_Test StorageAdapter backed by a Map<String,String>._

InMemoryStorageAdapter. _store Map<String,String>. read=_store[key]; write sets; remove deletes. All async methods complete synchronously.

### lib/storage/shopping_item_normalizer.dart

_Shared shopping-item normalization, identity keys, unique-id minting, and name-based dedup — single source for repo + provider._

Free functions:
- normalizeShoppingItemCategory(item): category = FoodCategories.normalize(item.category) ?? FoodCategories.other; returns item unchanged if already canonical else copyWith(category).
- normalizeShoppingItem(item): normalizeShoppingItemCategory then trim name & detail (copyWith only if changed).
- shoppingItemNameKey(name) = name.trim().toLowerCase() (case-insensitive identity for dup guards).
- withUniqueShoppingItemId(item, Set<String> existingIds): baseId = trimmed id or ShoppingItem.newId() if blank; suffix collisions as '<baseId>_2','_3'...; adds chosen id to existingIds; returns item (or copyWith(id)).
- deduplicateShoppingItems(Iterable): keep first occurrence per case-insensitive name key, drop blank-name rows, assign unique ids defensively. Applied on load AND replaceFromRemote so in-memory and reloaded lists cannot diverge (the original bug was repo deduping on load while provider didn't).

### lib/sync/sync_outbox_repo.dart (referenced)

_Drift-backed sync outbox queue (lives under sync/ but is a Drift repo used by the migration)._

SyncOutboxRepo(AppDatabase) implements OutboxReader. _cache List<SyncOperation>. hydratePending() async loads all into _cache. loadPending() sync returns _cache. watchPendingCount() -> Stream<int> via selectOnly count().watchSingle(). enqueue(op): insertOnConflictUpdate(outboxCompanionFor) then refresh _cache. removeAcknowledged(Set<String> ids): DELETE WHERE id IN ids (no-op if empty) then refresh. replaceAll(ops): transaction DELETE all + batch insertAll, refresh. _readAll: SELECT ORDER BY created_at; per-row try outboxFromRow catch skip. SyncOperation.toJson keys: id, householdId, entityType(name), entityId, operation(name), patch(deep-cloned Map), baseVersion(int?), clientId, createdAt(ISO8601), attemptCount(int, default 0), lastError(String?). Enums: SyncEntityType{inventoryItem,shoppingItem,customRecipe,mealPlanEntry,householdConfig}; SyncOperationType{create,update,delete,intake,deduction,toggleChecked}.

## 外部集成

- SharedPreferences: prod KV store behind SharedPrefsStorageAdapter; holds all settings/blob keys (favorite_recipe_ids, dietary_exclusions, reminder_settings_v1, ai_settings_v1, notification_sync_scheduled_ids_v1, food_details_cache, intake_review_draft) plus the legacy migration source keys and drift_migrated_v1 flag.
- SQLite via Drift: file named 'fresh_pantry' in applicationSupportDirectory (DriftNativeOptions.databaseDirectory=getApplicationSupportDirectory from path_provider). Backs the 7 tables and the sync outbox.
- FoodDetailsClient (services/food_details_client.dart): online food-details lookup wrapped by FoodDetailsRepository; cache invalidated by cacheVersion 5. Underlying source is Open Food Facts (referenced in isPlaceholderFoodDescription placeholder text).
- themealdb.com: fallback ingredient image URLs built as https://www.themealdb.com/images/ingredients/<english-name-slug>.png.
- Bundled asset assets/recipes/howtocook.json: read-only HowToCook recipe corpus via rootBundle.
- Supabase sync (indirect): household_id scoping and sync_outbox/payload_json shapes exist to drive Supabase family-sharing sync; the actual network layer is in the sync subsystem, not here.

## Swift 映射

Use SwiftData as the local store. Create one @Model per Drift table, each keeping a `payloadJSON: String` (or `Data`) field as the source of truth plus the projected/queryable scalar columns:\n- InventoryItemModel: keep a surrogate identity (SwiftData manages its own PersistentIdentifier — so the blank-id problem disappears; do NOT mark `id` @Attribute(.unique)). Store id, householdID, name, storageArea:String?, expiryDate:Date?, remoteVersion:Int=0, deletedAt:Date?, payloadJSON. Enforce the 'unique non-empty id within a household' invariant in code at upsert time (mirror the partial unique index) rather than via a schema unique constraint, because empty ids may legitimately repeat.\n- ShoppingItemModel, CustomRecipeModel, MealPlanEntryModel, FoodLogEntryModel: id is the natural key (@Attribute(.unique) on id is safe — these tables already use id as PK). FoodLogEntryModel keeps loggedAt:Date? indexed for the recent-window query.\n- SyncOutboxModel: id unique; entityType/operation as String (or Codable enums); createdAt:Date; payloadJSON.\n- AddHistoryModel: name @Attribute(.unique); payloadJSON.\nPersist epoch-ms columns as Date (codec already converts to/from UTC millisecondsSinceEpoch — replicate with Date(timeIntervalSince1970: ms/1000) at the JSON boundary for sync wire-fidelity).\n\nRepos -> actors / structs that take a ModelContext (or a `@ModelActor` for the Drift-backed ones to satisfy Swift 6 strict concurrency). Each exposes loadAllFor(householdID), saveItems(householdID:items:) implemented as a transactional delete-scope-then-insert (SwiftData: fetch+delete predicate, then insert, save once). Keep the per-row try/skip resilience: decode payload in a do/catch and drop malformed rows. FoodLogRepo keeps append(no-op on empty id), loadRecentFor(sinceMs), point deleteEntry, and full saveEntries semantics distinct (do NOT collapse deleteEntry into saveEntries).\n\nThe one-shot hydrate/loadAll seed pattern is a Flutter/Riverpod-sync-build workaround; in SwiftUI with @Observable + async, drop it and load directly (use @Query or an async load in .task). \n\nKV/blob repos (favorites, dietary, reminder, ai settings, scheduled ids, intake draft, food-details cache) -> a thin UserDefaults-backed adapter mirroring StorageAdapter (read/write/remove) with the same JSON keys, OR fold the small typed ones into @AppStorage. Keep ai_settings as a Keychain item if it contains an API key. food_details_cache (a large keyed JSON map) is better as its own SwiftData @Model or a file cache than UserDefaults.\n\nMigration: the blob_to_drift one-time SharedPreferences import is irrelevant to a fresh Swift install (no legacy Flutter prefs on a new native app) UNLESS this rewrite must read existing on-device Flutter data — flag as an open question. The Drift v1→v5 migration history is internal to SQLite and does not need replication; only the final v5 shape matters for the SwiftData schema. Reuse the dedup invariants (smallest-id-wins, '' orphan cleanup, name+addedAt clone collapse) as one-time data-cleanup logic only if importing legacy data.\n\nLocalRecipeRepository -> decode the bundled howtocook.json once at startup, cache in an actor/singleton.

## 迁移注意

PARITY-CRITICAL INVARIANTS:\n1. householdId='' means local-only / not-yet-shared. Adopting local data into a household calls deleteHouseholdScope('') after copying — replicate this re-scoping flow or you get duplicate orphans.\n2. Inventory id is NOT unique when blank: the partial unique index is `WHERE id != ''`. SwiftData must enforce uniqueness for non-empty ids in code, never via a blanket .unique attribute (which would reject duplicate empty ids).\n3. payload_json is the source of truth; scalar columns are derived projections read ONLY for querying/sorting/indexing. On decode the repos read payload_json exclusively. Keep JSON payloads byte-faithful for Supabase sync — the wire format is the model toJson, and remote_version/deleted_at/baseVersion drive conflict resolution.\n4. Date columns are stored as epoch MILLISECONDS in UTC (expiry_date, deleted_at, expiryDate, logged_at). sync_outbox.created_at is a Drift DateTime stored as epoch SECONDS — different unit; mind this if reading raw rows.\n5. meal_plan_entries.name column holds recipeName (not a separate field).\n6. FoodLogRepo.deleteEntry must stay a point-delete — using a replace-all there would silently drop history outside the loaded recent window (documented bug guard).\n7. FoodLog and inventory writes use insertOrReplace; saves are full-scope replace-in-transaction. food_log append is a single non-transactional insert and no-ops on blank id.\n8. Shopping dedup is by case-insensitive name key (keep first), applied on BOTH load and replaceFromRemote — the original divergence bug was deduping in only one path. Replicate in both Swift load and remote-merge paths.\n9. FoodDetails cache version constant (5) must move in lockstep with FoodDetails.toJson cacheVersion; mismatched-version cache entries are treated stale and re-fetched. Local-fallback details (source=='本地食材知识库') are intentionally NOT cached.\n10. isPlaceholderFoodDescription is the single authority for hiding placeholder descriptions; its three template prefixes must stay in sync with their producers (this repo's _fallbackDescription + the OFF service line).\n11. blob_to_drift migration sets its done-flag only after ALL writes succeed (crash-safe retry); legacy keys are preserved one release for rollback. Inventory/shopping import filter is by NAME non-empty (not id), because local rows have blank ids; recipes/mealplan filter by id+name non-empty.\n12. Decode resilience everywhere: a single malformed row/entry is skipped, the rest preserved — preserve this leniency in Swift Codable decode loops.

## 开放问题

- Does the SwiftUI rewrite need to read EXISTING on-device data from the current Flutter install (SharedPreferences plist + the Drift SQLite file in Application Support), or is it a clean install with sync-from-Supabase as the only data source? This determines whether the blob_to_drift legacy import and the v1→v5 inventory dedup logic must be reimplemented for a data-bridge, or can be dropped entirely.
- Exact JSON shapes of the domain models (Ingredient, ShoppingItem, Recipe, MealPlanEntry, FoodLogEntry, FoodDetails, ReminderSettings, AiSettings, IntakeProposal) are owned by the models subsystem — needed verbatim for byte-faithful payload_json so Supabase sync stays compatible. Confirm with that subsystem's map.
- sync_outbox.created_at is a Drift DateTimeColumn (epoch seconds), while all other timestamps in this layer are epoch ms — confirm the Supabase/sync wire format expects ISO8601 (SyncOperation.toJson uses createdAt.toIso8601String) so the column-unit difference is purely internal.
- AiSettings likely contains an API key/base-url; confirm whether it should move to Keychain in the Swift rewrite rather than UserDefaults.
- food_details_cache can grow large (one entry per looked-up ingredient/barcode) as a single JSON blob in SharedPreferences — confirm whether to keep it as one blob or split into a dedicated SwiftData model / file cache in Swift.
