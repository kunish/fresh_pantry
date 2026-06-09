# domain-models (`models`)

**Effort:** M

## 概述

The domain-models layer is the data backbone of Fresh Pantry: plain immutable Dart value types plus a handful of pure rule helpers. There are three families: (1) synced persistent entities (Ingredient, Recipe/RecipeIngredient, ShoppingItem, MealPlanEntry, FoodLogEntry) which all embed a SyncMetadata triplet (remoteVersion/clientUpdatedAt/deletedAt) and round-trip via toJson/fromJson; (2) ephemeral/UI/config value types (Proposal hierarchy, IngredientDraft, RecipeDraft, DraftField, FoodDetails/NutritionFacts, FrequentItem, StorageArea, AiSettings, ReminderSettings, ScheduledNotification); and (3) the IngredientIdentity rule (ADR-0001) which is the single arbiter of whether an intake merges into an existing inventory row or starts a new batch. Persistence is via Drift, where every entity is stored as its full toJson() in a `payloadJson` TEXT column with a few denormalized indexable columns hoisted out (id, householdId, name, remoteVersion, deletedAt, plus entity-specific sort keys). For Swift this maps to @Model SwiftData types (or Codable value types + a thin persistence record) preserving the exact JSON keys, default values, and identity rules so sync parity holds.

## 组件(21)

### lib/models/sync_metadata.dart

_Shared optimistic-concurrency/soft-delete triplet embedded by every synced entity; plus two free DateTime<->JSON helpers._

Top-level functions: `DateTime? dateTimeFromJsonValue(Object? value)` — returns null if value is not a String or is blank/whitespace, else DateTime.tryParse(value) (may still return null). `String? dateTimeToJsonValue(DateTime? value)` — value?.toIso8601String(). Class SyncMetadata (const, value-equal): fields `int remoteVersion=0`, `DateTime? clientUpdatedAt`, `DateTime? deletedAt`. Equality + hashCode over all three. No toJson on the class itself; entities inline these three fields into their own JSON. CRITICAL semantics: remoteVersion = last server-acked version (0 = never synced/local-only); clientUpdatedAt = local mutation timestamp for LWW; deletedAt non-null = soft-deleted (tombstone). Swift: a struct SyncMetadata { var remoteVersion: Int = 0; var clientUpdatedAt: Date?; var deletedAt: Date? } flattened into each @Model.

### lib/models/ingredient.dart

_Core inventory item (one pantry/fridge row / batch). Backbone entity._

enum FreshnessState { fresh, expiringSoon, urgent, expired } (order least->most severe; `urgent` = near-expiry refinement of expiringSoon). Class Ingredient (immutable, full value equality over ALL fields incl. sync triplet). Fields with Dart type / nullability / default: `String id=''` (empty = local-only, no server id), `String name` (req), `String quantity` (req, FREE TEXT e.g. '1','半','500'), `String unit` (req), `String imageUrl` (req), `double freshnessPercent` (req, 0..1), `FreshnessState state` (req), `String? expiryLabel`, `String? category`, `String? barcode`, `IconType storage=IconType.fridge`, `DateTime? expiryDate`, `DateTime? addedAt`, `int? shelfLifeDays`, `int remoteVersion=0`, `DateTime? clientUpdatedAt`, `DateTime? deletedAt`. Computed: `SyncMetadata get syncMetadata`. copyWith has all fields plus `bool clearClientUpdatedAt=false`, `bool clearDeletedAt=false` (these force the field to null, overriding the ?? fallback). toJson keys (exact): id, name, quantity, unit, imageUrl, freshnessPercent, state(=state.name string), expiryLabel, category, barcode, storage(=storage.name), expiryDate(=ISO8601 or null), addedAt(=ISO8601 or null), shelfLifeDays, remoteVersion, clientUpdatedAt(via dateTimeToJsonValue), deletedAt(via dateTimeToJsonValue). fromJson defaults: id'', name'', quantity'1', unit'份', imageUrl'', freshnessPercent 1.0, state parsed via FreshnessState.values.byName with fallback FreshnessState.fresh on any error, storage via iconTypeFromName, expiryDate/addedAt via DateTime.tryParse only when value is String (else null), shelfLifeDays via num.toInt, remoteVersion num.toInt?? 0. NOTE freshnessPercent default differs: toJson always writes it but fromJson default 1.0.

### lib/models/ingredient_identity.dart

_ADR-0001 identity rule: the SINGLE arbiter of merge-vs-new-batch. Stateless static class._

class IngredientIdentity (private ctor). identity rule = name × unit × StorageArea × (Batch for Perishables). Two static methods: (1) `bool isPerishable({String? category, required String name})` => FoodCategories.isPerishable(category) || FoodKnowledge.isPerishableName(name). (2) `int resolveMergeTarget({required String name, required String unit, required IconType storage, String? category, required List<Ingredient> inventory})`: returns index of row to merge into, or -1 = create new row. Algorithm exactly: if isPerishable -> return -1 (every perishable intake is a new batch). normalizedName = name.trim().toLowerCase(); normalizedUnit = unit.trim(); if either empty -> -1. Loop inventory by index: skip rows whose name.trim() is empty; skip if row.name.trim().toLowerCase() != normalizedName; skip if row.unit.trim() != normalizedUnit; skip if row.storage != storage; if double.tryParse(row.quantity.trim()) == null -> return -1 (non-numeric qty: merging would discard stock); else return i. Fall through -> -1. NOTE: name match is case-insensitive+trimmed; unit match is trimmed but CASE-SENSITIVE; storage exact enum match. Perishability is decided by BOTH category alias-normalization AND name-keyword knowledge base (so a perishable named '猪肉' with category '其他' still gets a new batch).

### lib/models/storage_area.dart

_Storage location enum + helpers + a derived per-area summary view-model._

enum IconType { fridge, freezer, pantry }. `IconType iconTypeFromName(String? name)`: 'pantry'->pantry, 'freezer'->freezer, 'fridge'|null->fridge, default->fridge (any unknown -> fridge). `String storageAreaLabel(IconType)`: fridge->'冰箱', freezer->'冷冻室', pantry->'食品柜' (single source of truth for chips/providers). Class StorageArea (value-equal; `name` is the business key but equality covers all 4 fields): `String name` (req), `IconType icon` (req), `int itemCount` (req), `double capacityPercent` (req). copyWith all fields. toJson: name, icon(=icon.name), itemCount, capacityPercent. fromJson defaults: name'', icon via iconTypeFromName, itemCount num.toInt??0, capacityPercent num.toDouble??0.0. This is a derived/aggregate view-model, not a persisted entity (no sync triplet).

### lib/models/recipe.dart

_Recipe entity + RecipeIngredient sub-value + recipe-ingredient dedupe rule._

Class RecipeIngredient (value-equal over name/quantity/unit/amount; NOT const ctor): `String name` (req), `String quantity=''`, `String unit=''`, `String amount` (derived in ctor if not supplied via `_composeAmount(quantity,unit)`). _composeAmount: trim both; both empty->''; q empty->u; u empty->q; else '$q$u' (concatenated, no space). Legacy parse: `_parseLegacyAmount(amount)` trims, if empty -> ('',''); uses parseLeadingQuantity (regex ^(\d+(?:\.\d+)?)\s*(.*)$): null -> ('', wholeTrimmed) i.e. all goes to unit; else (magnitude, remainder). Computed `bool get isScalable` = double.tryParse(quantity.trim())!=null. `RecipeIngredient scaledBy(double factor)`: factor==1 -> this (preserves explicit amount); non-numeric quantity -> this unchanged; else new RecipeIngredient(name, quantity=formatQuantity(magnitude*factor), unit) [amount recomposed]. copyWith preserves `amount` only when neither quantity nor unit changes. toJson: name, quantity, unit, amount. fromJson: if json has 'quantity' OR 'unit' key -> new shape (read quantity/unit/amount, defaults ''); else legacy: parse amount into quantity/unit, keep original amount. 

Top-level `List<RecipeIngredient> dedupeRecipeIngredients(Iterable)`: keeps FIRST occurrence keyed by name.trim().toLowerCase() (matches shoppingItemNameKey). Applied at EVERY recipe entry point (parser, custom, JSON).

Class Recipe (immutable; equality/hashCode by `id` ONLY): `String id` (req), `String name` (req), `String category` (req), `int difficulty` (req), `int cookingMinutes` (req), `String description` (req), `List<RecipeIngredient> ingredients` (req), `List<String> steps` (req), `List<String> tags=const[]`, `String? imageUrl`, `int remoteVersion=0`, `DateTime? clientUpdatedAt`, `DateTime? deletedAt`. syncMetadata getter. copyWith all fields + clearClientUpdatedAt/clearDeletedAt flags. toJson: id, name, category, difficulty, cookingMinutes, description, ingredients(list of maps), steps(copy), tags(copy), imageUrl, remoteVersion, clientUpdatedAt, deletedAt. fromJson defaults: id'', name'', category'', difficulty num.toInt??0, cookingMinutes num.toInt??30, description'', ingredients run through dedupeRecipeIngredients (filters non-map entries via whereType), steps/tags via whereType<String>, imageUrl nullable, sync triplet defaults. extension RecipeDifficultyLabel: difficultyLabel = '难度未设置' when <=0, else '难度 N/5' where N=difficulty.clamp(1,5).

### lib/models/shopping_item.dart

_Shopping list entry; convertible from Ingredient._

Class ShoppingItem (immutable; equality/hashCode by `id` ONLY): `String id` (req), `String name` (req), `String detail` (req), `String? imageUrl`, `String category` (req), `bool isChecked=false`, `int remoteVersion=0`, `DateTime? clientUpdatedAt`, `DateTime? deletedAt`. syncMetadata getter. Static `String newId()` = 'si_${DateTime.now().millisecondsSinceEpoch}' (canonical id format). factory `ShoppingItem.fromIngredient(Ingredient, {String? id})`: id ?? newId(), name=ingredient.name, detail='${quantity} ${unit}' (space-joined), imageUrl = ingredient.imageUrl.isEmpty ? null : it, category = ingredient.category ?? FoodCategories.other ('其他'). copyWith all + clear flags. toJson: id, name, detail, imageUrl, category, isChecked, remoteVersion, clientUpdatedAt, deletedAt. fromJson defaults: id'', name'', detail'', imageUrl nullable, category default FoodCategories.other, isChecked false, sync triplet defaults.

### lib/models/food_log_entry.dart

_Append-only food departure log (consumed vs wasted) — the truth source for waste-reduction stats._

enum FoodLogOutcome { consumed, wasted } with static `FoodLogOutcome fromName(String?)` matching by .name, fallback consumed (unknown/dirty -> consumed, conservative). Class FoodLogEntry (NOT const ctor; equality/hashCode by `id` ONLY): `String id` (req), `String name` (req, snapshot), `String category=FoodCategories.other` (snapshot), `FoodLogOutcome outcome` (req), `DateTime loggedAt` (req — ctor normalizes via `loggedAt.toUtc()`; stored UTC, stats convert toLocal), `bool wasExpiring=false`, `int remoteVersion=0`, `DateTime? clientUpdatedAt`, `DateTime? deletedAt`. Static `String newId()` = 'fl_${ms}'. Computed: `bool isConsumed`, `bool isWasted`, `bool rescuedExpiring` (=isConsumed && wasExpiring). copyWith all + clear flags. toJson: id, name, category, outcome(=outcome.name), loggedAt(=toIso8601String of the UTC value), wasExpiring, remoteVersion, clientUpdatedAt, deletedAt. fromJson: loggedAt parsed via dateTimeFromJsonValue; if null -> THROWS FormatException('FoodLogEntry.loggedAt missing or unparseable') (repo layer try/catch skips dirty row — NO silent fallback). Other defaults: id'', name'', category default other, outcome via fromName, wasExpiring false, sync triplet defaults. Note: quantity intentionally NOT logged (count-based stats).

### lib/models/meal_plan_entry.dart

_Weekly meal-plan record: one planned dish on one local calendar day. One record = one dish (not one row per day)._

Class MealPlanEntry (NOT const ctor; equality/hashCode by `id` ONLY): `String id` (req), `DateTime date` (req — ctor normalizes via `dateOnly(date)` = DateTime(y,m,d) local midnight, year/month/day only), `String recipeId` (req), `String recipeName` (req, snapshot), `String? recipeImageUrl` (snapshot), `int servings=1`, `bool done=false`, `int remoteVersion=0`, `DateTime? clientUpdatedAt`, `DateTime? deletedAt`. syncMetadata getter. Statics: `DateTime dateOnly(DateTime)` = DateTime(value.year,value.month,value.day); `String dateKey(DateTime)` = 'yyyy-MM-dd' zero-padded (y padLeft4, m/day padLeft2). copyWith all + clear flags. toJson: id, date(=dateKey, NOT ISO), recipeId, recipeName, recipeImageUrl, servings, done, remoteVersion, clientUpdatedAt, deletedAt. fromJson: date parsed by private `_parseDate(value)` (String non-blank -> DateTime.tryParse(trim) then dateOnly; else null); if null -> THROWS FormatException('MealPlanEntry.date missing or unparseable') (repo skips dirty row). Other defaults: id'', recipeId'', recipeName'', recipeImageUrl nullable, servings num.toInt??1, done false, sync triplet defaults. Memory note: servings is currently functional input for portion scaling (not purely decorative).

### lib/models/proposal.dart

_Ephemeral AI/intake review proposals (sealed hierarchy) — NOT persisted, no sync triplet. Drives the Review UI._

enums: IntakeAction { newRow, mergeInto }; DeductionAction { deduct, skip }; FieldOrigin { ai, system, user } (origin dots in review UI). `sealed class Proposal` { `String id` (req), `bool selected=true` }. 

class IntakeProposal extends Proposal: `String name`(req), `String quantity`(req), `String unit`(req), `String? category`(req-nullable), `IconType storage`(req), `int? shelfLifeDays`(req-nullable), `IntakeAction action=IntakeAction.newRow`, `String? mergeTargetId` (references inventory row to merge into; corresponds to list INDEX at proposal-compute time — callers MUST re-resolve via IngredientIdentity before applying), `String? mergeTargetLabel`, `FieldOrigin origin=FieldOrigin.ai` (ai for AI parse, system for shopping-derived; immutable through copyWith), `bool userEdited=false`. copyWith covers name,quantity,unit,category,storage,shelfLifeDays,action,mergeTargetId,mergeTargetLabel,selected,userEdited (origin preserved, id preserved). No JSON.

class DeductionCandidate (const): `int inventoryRowIndex`(req, positional key NOT apply-time truth), `String displayLabel`(req), `String inventoryRowId=''` (preferred stable identity when non-empty), `String inventoryRowName=''`, `String inventoryRowUnit=''` (name+unit guard for local rows with empty id). 

class DeductionProposal extends Proposal: `String recipeIngredientName`(req), `String requiredQty`(req), `List<DeductionCandidate> candidates` (req, stored List.unmodifiable), `int chosenIndex`(req; -1 when skip), `String deductAmount`(req, string matching Ingredient.quantity shape), `DeductionAction action=deduct`. factory `DeductionProposal.empty({id,recipeIngredientName,requiredQty})` -> candidates const[], chosenIndex -1, deductAmount '0', action skip, selected false. copyWith: chosenIndex,deductAmount,action,selected (others preserved). No JSON.

### lib/models/food_details.dart

_Cached enriched food metadata (from OpenFoodFacts/AI) + per-100g nutrition. Cache value object._

class NutritionFacts (const; value-equal): all nullable doubles `double? energyKcal`(kcal/100g), `double? protein`(g), `double? carbs`(g), `double? fat`(g). `bool get hasAny` = any field non-null. toJson: energyKcal, protein, carbs, fat. fromJson via static `_toDouble` (num->toDouble, String->double.tryParse(trim), else null). Static `NutritionFacts? fromOffNutriments(Map)`: reads OFF keys 'energy-kcal_100g','proteins_100g','carbohydrates_100g','fat_100g'; returns null if !hasAny (don't store empty). 

class FoodDetails (const): `String displayName`(req), `String description`(req), `String? imageUrl`(req-nullable), `String category`(req), `IconType storage`(req), `int? shelfLifeDays`(req-nullable), `String source`(req), `DateTime fetchedAt`(req), `NutritionFacts? nutrition`. toJson: displayName, description, imageUrl, category, storage(=storage.name), shelfLifeDays, source, fetchedAt(=ISO8601), nutrition(=nutrition?.toJson()), plus literal `'cacheVersion': 5` (must bump in lockstep with _foodDetailsCacheVersion in food_details_repo.dart; older v4 caches treated stale + re-fetched). fromJson: defaults displayName'', description'', imageUrl nullable, category'', storage via iconTypeFromName, shelfLifeDays num.toInt, source'', fetchedAt = DateTime.tryParse OR epoch0-UTC fallback when missing/unparseable, nutrition built when value is a Map else null.

### lib/models/ai_settings.dart

_User AI provider config (OpenAI-compatible). Stored locally; no sync._

@immutable class AiSettings (const; value-equal over all 4): `String baseUrl`(req), `String apiKey`(req), `String model`(req), `Duration timeout=Duration(seconds:60)`. Computed `bool get isConfigured` = baseUrl/apiKey/model all non-empty. copyWith all 4. toJson: baseUrl, apiKey, model, timeoutSeconds(=timeout.inSeconds). fromJson defaults: baseUrl'', apiKey'', model'', timeout=Duration(seconds: timeoutSeconds ?? 60). Static const `empty = AiSettings(baseUrl:'',apiKey:'',model:'')` (timeout defaults to 60s).

### lib/models/draft_field.dart

_Generic provenance-tracked field wrapper for AI/user-edited drafts._

enum DraftSource { ai, user, hybrid }. @immutable class DraftField<T> (const; value-equal over value+source): `T value`(req), `DraftSource source`(req). factories: `DraftField.ai(T)` (source ai), `DraftField.user(T)` (source user). Method `DraftField<T> editedTo(T next)` -> new DraftField(next, source: user). Note `hybrid` enum case is defined but neither factory produces it. No JSON. Swift: generic struct DraftField<T: Equatable> with the same factories.

### lib/models/ingredient_draft.dart

_AI/manual intake draft for one ingredient before confirmation; converts to Ingredient._

@immutable class IngredientDraft (const): `String id`(req), `DraftField<String> name`(req), `DraftField<String> quantity`(req), `DraftField<String> unit`(req), `DraftField<String?> category`(req), `DraftField<IconType?> storage`(req), `DraftField<int?> shelfLifeDays`(req), `bool selected=true`. Method `Ingredient toIngredient()`: days = shelfLifeDays.value; today=DateTime.now(); expiry = days==null ? null : today.add(Duration(days:days)); freshness = expiry==null ? 0.85 : expiryFreshness(expiryDate:expiry, totalShelfLifeDays: days ?? 7); builds Ingredient(name,quantity,unit, imageUrl:'', freshnessPercent:freshness, state: freshnessStateForExpiry(freshness, expiry), category:category.value, storage: storage.value ?? IconType.fridge, expiryDate:expiry, expiryLabel: expiry==null ? '新鲜' : expiryLabelFor(expiry), shelfLifeDays:days). No equality/JSON (transient). Depends on utils/expiry_calculator.dart.

### lib/models/recipe_draft.dart

_AI/manual draft for an imported/authored recipe; converts to Recipe._

@immutable class RecipeIngredientDraft (const): `DraftField<String> name`(req), `DraftField<String> amount`(req). `RecipeIngredient toIngredient()` = RecipeIngredient(name:name.value, amount:amount.value) (quantity/unit derived from amount via legacy parse path inside RecipeIngredient ctor when amount given but no quantity/unit). @immutable class RecipeDraft (const): `String? sourceUrl`, `DraftField<String> name`(req), `DraftField<String> category`(req), `DraftField<int> cookingMinutes`(req), `DraftField<int> difficulty`(req), `DraftField<String> description`(req), `DraftField<String?> imageUrl`(req), `List<RecipeIngredientDraft> ingredients`(req), `List<DraftField<String>> steps`(req). Method `Recipe toRecipe({String Function()? idGenerator})`: id = idGenerator?.call() ?? 'custom_${ms}'; builds Recipe with ingredients mapped to RecipeIngredient, steps mapped to String, tags const[]. No equality/JSON (transient).

### lib/models/frequent_item.dart

_Derived 'frequently added item' with remembered defaults; feeds frequentItemsProvider / lowStockItemsProvider._

class FrequentItem (const; value-equal over ALL fields — needed so the derived list compares by content, otherwise every rebuild re-emits): `String name`(req), `String category`(req), `IconType storage`(req), `String unit`(req), `int? shelfLifeDays`, `int count`(req). No copyWith/JSON. Pure derived view-model (no sync). Backed at persistence by AddHistoryEntries table (name key + payloadJson {count,category,storage,unit}).

### lib/models/reminder_settings.dart

_Expiry-reminder preferences for notification scheduling. Local config._

@immutable class ReminderSettings (const; value-equal): `bool remindD1=true`, `bool remindD3=true`, `bool remindD7=false`, `bool remindDaily=true`. Computed `List<int> get enabledOffsetDays` = [if remindD7 7, if remindD3 3, if remindD1 1] (largest-first, used by ExpiryScheduler for per-item D-N reminders). copyWith all 4. toJson: remindD1, remindD3, remindD7, remindDaily. fromJson defaults: D1 true, D3 true, D7 false, daily true.

### lib/models/scheduled_notification.dart

_A concrete OS-level scheduled local notification descriptor._

@immutable class ScheduledNotification (const; value-equal over all): `int id`(req — integer notification id, not a string), `String title`(req), `String body`(req), `DateTime scheduledAt`(req), `ScheduledNotificationKind kind=ScheduledNotificationKind.expiry`. enum ScheduledNotificationKind { expiry, dailySummary }. No copyWith/JSON. Swift: maps to a UNNotificationRequest builder; kind drives identifier namespacing/content.

### lib/data/food_categories.dart (referenced)

_Category canonicalization + perishability source consumed by IngredientIdentity/ShoppingItem/FoodLog._

class FoodCategories static consts: dairyAndEggs='乳品蛋类', freshProduce='果蔬生鲜', meatAndSeafood='肉类海鲜', herbsAndSpices='香料草本', other='其他', removedPantryStaples='食品柜常备'. `values` = [dairyAndEggs, freshProduce, meatAndSeafood, herbsAndSpices, other]. Large `_aliases` map normalizes many legacy/synonym Chinese labels to the 5 canonical (anything unmapped non-empty -> other; null/empty -> null). `String? normalize(String?)`, `String dropdownValue(String?)` (normalize ?? other). `_perishable` set = {freshProduce, meatAndSeafood, dairyAndEggs}. `bool isPerishable(String? category)` = normalize then membership (null -> false). Swift must port the alias table verbatim for parity.

### lib/data/food_knowledge.dart (referenced)

_Name-keyword knowledge base for smart defaults + name-based perishability (used by IngredientIdentity)._

class FoodDefaults(String category, IconType storage, int shelfLifeDays). class FoodKnowledge: `_entries` map keyword->FoodDefaults (~130 entries), `_englishNames` map. `_keyMatches(lower,key)`: length-1 key must equal whole name; multi-char key = substring contains (avoids '蛋糕'->'蛋'). `lookup(name)`: lowercase+trim, longest matching key wins. `categoryFor(name,{fallback=other})`. `isPerishableName(String name)` = FoodCategories.isPerishable(lookup(name)?.category). Also: shelfLifePresets=[3,7,14,30], units=['个','瓶','袋','盒','包','g','kg','ml','L'].

### lib/utils/quantity_text.dart + expiry_calculator.dart (referenced)

_Pure rules the models call: quantity parse/format and freshness/expiry derivation._

quantity_text: regex `_leadingQuantityRe = ^(\d+(?:\.\d+)?)\s*(.*)$`. `parseLeadingQuantity(input)` -> {magnitude, remainder(trimmed)} or null. `formatQuantity(double n)`: whole -> int string; else double.parse(n.toStringAsFixed(2)).toString() (strips float artifacts to <=2 decimals). expiry_calculator: `calendarDaysBetween(start,end)` on date-only; `daysUntilExpiry(expiry,{now})`; `expiryFreshness({expiryDate, totalShelfLifeDays, now})` = (daysUntil/total).clamp(0,1), returns 0.0 if total<=0; const `urgentWithinDays=2`; `freshnessStateForExpiry({freshness, expiryDate, now})`: if expiry!=null & days<0 -> expired; days<=2 -> urgent; else freshness>0.5 -> fresh else expiringSoon; `expiryLabelFor(expiry,{now})`: days<0 '已过期N天', 0 '今天过期', 1 '明天过期', else 'N天后过期'.

### lib/storage/drift/app_database.dart (persistence shape — referenced)

_Shows how every model is persisted: full toJson() in a payloadJson TEXT column + hoisted indexable columns. schemaVersion=5._

Persistence pattern = JSON blob + denormalized columns. InventoryItems: rowPk(autoinc surrogate PK), id TEXT, householdId TEXT default '', name TEXT default '', storageArea TEXT nullable, expiryDate INT nullable (epoch ms), remoteVersion INT default 0, deletedAt INT nullable (epoch ms), payloadJson TEXT (= Ingredient.toJson()). ShoppingItems: id, householdId, name, isChecked BOOL default false, remoteVersion, deletedAt, payloadJson. CustomRecipes: id, householdId, name, remoteVersion, deletedAt, payloadJson. MealPlanEntries: id, householdId, name(=recipeName), remoteVersion, deletedAt, payloadJson. FoodLogEntries: id, householdId, name, loggedAt INT nullable, remoteVersion, deletedAt, payloadJson. SyncOutbox: id, householdId, entityType, entityId, operation, baseVersion INT nullable, clientId, createdAt DateTime, payloadJson. AddHistoryEntries: name (key), payloadJson ({count,category,storage,unit}) — backs FrequentItem. IMPORTANT for Swift: the canonical serialized form is the JSON (these column values are denormalized copies hoisted for query/sort/sync), so SwiftData @Model property mapping must keep the exact JSON keys to preserve sync parity. Note timestamps stored as epoch-ms ints in columns but ISO8601 strings inside payloadJson.

## 外部集成

- OpenFoodFacts: NutritionFacts.fromOffNutriments reads per-100g keys 'energy-kcal_100g','proteins_100g','carbohydrates_100g','fat_100g' from the OFF product `nutriments` map; FoodDetails caches the enriched result with a literal cacheVersion=5 (bump in lockstep with _foodDetailsCacheVersion in food_details_repo.dart).
- AI provider (OpenAI-compatible): AiSettings holds baseUrl/apiKey/model/timeout(60s default); isConfigured gates AI parse features that feed IngredientDraft/RecipeDraft and IntakeProposal(origin=ai).
- Supabase family-sharing sync: every persisted entity carries SyncMetadata (remoteVersion=last server version, clientUpdatedAt=LWW timestamp, deletedAt=tombstone) + householdId scoping; SyncOutbox table queues operations (entityType/entityId/operation/baseVersion/clientId/payloadJson). Ingredient.id ''='local-only never synced'. ShoppingItem ids 'si_<ms>', FoodLog 'fl_<ms>', custom recipes 'custom_<ms>'.
- UserNotifications: ReminderSettings.enabledOffsetDays (D7/D3/D1) + ScheduledNotification(id:Int, kind: expiry|dailySummary) describe the local notifications ExpiryScheduler must register.

## Swift 映射

Model the five synced entities (Ingredient, Recipe, ShoppingItem, MealPlanEntry, FoodLogEntry) as SwiftData @Model classes, each embedding remoteVersion: Int, clientUpdatedAt: Date?, deletedAt: Date? (flatten SyncMetadata). To preserve sync parity, give each @Model a Codable mirror that reproduces the EXACT toJson/fromJson keys and defaults (the Flutter persistence stores full JSON in payloadJson; the Supabase wire shape == that JSON), e.g. via a Codable struct + a payloadJSON computed property, since the Supabase Swift SDK round-trips JSON. Use String id with the same '' / si_/fl_/custom_<ms> conventions; keep Recipe/ShoppingItem/MealPlanEntry/FoodLogEntry identity == id only (Hashable by id), but Ingredient/StorageArea/FrequentItem/sub-value types use full-field Equatable. Port enums as Swift enum: String (FreshnessState, IconType, FoodLogOutcome with fromName-style fallback to consumed, IntakeAction, DeductionAction, FieldOrigin, DraftSource, ScheduledNotificationKind) keeping rawValues == Dart .name. Implement IngredientIdentity as a stateless enum/struct with static resolveMergeTarget mirroring the exact normalization (name trim+lowercase, unit trim case-sensitive, storage ==, non-numeric quantity -> -1) and isPerishable combining FoodCategories + FoodKnowledge. Port FoodCategories alias map, FoodKnowledge keyword table+_keyMatches, quantity_text (regex + formatQuantity rounding-to-2dp), and expiry_calculator (date-only diff, urgentWithinDays=2, label strings) as pure Swift functions/static members. Ephemeral types (Proposal sealed hierarchy, IngredientDraft, RecipeDraft, DraftField<T>, FoodDetails/NutritionFacts) become plain Swift structs/enums (Proposal as an enum or protocol+structs); FoodDetails is a Codable cache value (keep cacheVersion=5 literal). AiSettings/ReminderSettings persist via a small @Model or UserDefaults+Codable. ScheduledNotification maps to a UNNotificationRequest builder keyed by the Int id (use String identifier derived from id+kind). All view-model aggregates (StorageArea, FrequentItem) are computed, not stored.

## 迁移注意

Parity-critical invariants: (1) IngredientIdentity is the ONLY arbiter of merge-vs-new-batch — perishable (by category alias OR name keyword) always returns -1 (new batch); name match is trim+lowercase, unit match is trim but CASE-SENSITIVE, storage exact; a matched row with non-numeric quantity returns -1 to avoid discarding stock. Both proposal-time default and apply-time re-resolution must call the same code. (2) mergeTargetId in IntakeProposal and inventoryRowIndex in DeductionCandidate are POSITIONAL indices captured at compute time and MUST be re-resolved by stable identity (id preferred, else name+unit) before apply — lists reorder/shrink via sync. (3) JSON keys, default values, and date encodings are sync-wire-critical and must match exactly: Ingredient.quantity default '1', unit default '份', freshnessPercent fromJson default 1.0; FreshnessState/storage parse failures fall back to fresh/fridge; FoodLogOutcome unknown -> consumed; MealPlanEntry.date serialized as 'yyyy-MM-dd' (NOT ISO) and normalized to LOCAL midnight; FoodLogEntry.loggedAt normalized to UTC and serialized ISO8601. (4) Dirty-data policy is fail-loud: MealPlanEntry.fromJson and FoodLogEntry.fromJson THROW FormatException on missing/unparseable date — the repo layer catches and skips the row; do NOT silently default the timestamp (would corrupt stats/calendar). (5) formatQuantity must round to <=2 decimals to prevent float artifacts ('1.2000000000000002') leaking into stored quantities; scaledBy returns the item unchanged for non-numeric quantities and factor==1. (6) dedupeRecipeIngredients (first-wins by name.trim().toLowerCase()) must run at every recipe entry point. (7) Ingredient.id '' marks local-only/never-synced; preserve that semantic for the sync gateway. (8) FoodDetails cacheVersion=5 must bump in lockstep with the repo constant or stale caches won't invalidate. (9) Persistence note: Flutter stores epoch-ms ints in hoisted columns but ISO strings inside payloadJson — Swift should treat the JSON as canonical and derive any index columns.

## 开放问题

- DraftSource has a `hybrid` case that no factory or editedTo() produces — is it dead code or set elsewhere (e.g. when AI value is later partially edited)? Confirm before pruning in Swift.
- RecipeIngredient is NOT a const constructor and has no sync metadata; it lives only inside Recipe.ingredients (serialized as nested JSON). Confirm there is no standalone persistence/identity for it beyond the dedupe key.
- IngredientIdentity.resolveMergeTarget treats unit matching as case-sensitive (trim only) while name is case-insensitive — confirm this asymmetry is intentional for Swift parity (likely yes, but flag).
- FrequentItem persistence: backed by AddHistoryEntries table whose payloadJson is {count,category,storage,unit} keyed by name — confirm the exact JSON keys and how `count` is incremented (logic lives in the repo/providers subsystem, not in models).
- Ingredient.addedAt and barcode have no hoisted DB column and are only in payloadJson — confirm they are not used as sort/sync keys (sorting by addedAt would then require JSON parsing or an added column).
