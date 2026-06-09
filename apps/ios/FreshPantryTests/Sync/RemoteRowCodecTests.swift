import Foundation
import Testing
@testable import FreshPantry

/// Round-trip + default parity for the Supabase ⇄ domain row codec, pinned
/// against `lib/sync/remote_row_codec.dart`. Asserts the exact column key set
/// per entity (so a dropped/renamed column is caught), the per-direction
/// defaults from the Dart `_orX`/`_toX` helpers, the version-never-zero rule, and
/// the UUID-gated `id` handling.
struct RemoteRowCodecTests {
    private static let uuid = "11111111-2222-4333-8444-555555555555"

    // MARK: - Inventory

    @Test func inventoryRowFromJsonAppliesDefaultsForAbsentColumns() {
        // A sparse DB row: only id + name present. Every other mapped key must
        // still appear, with the decode default (or null) filled in.
        let row: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("牛奶"),
        ]
        let domain = RemoteRowCodec.inventoryRowFromJson(row)

        #expect(domain["id"] == .string(Self.uuid))
        #expect(domain["name"] == .string("牛奶"))
        #expect(domain["quantity"] == .null) // no decode default
        #expect(domain["unit"] == .null)
        #expect(domain["imageUrl"] == .string("")) // _orEmpty
        #expect(domain["freshnessPercent"] == .double(1.0)) // _toDouble1
        #expect(domain["state"] == .string("fresh")) // _orFresh
        #expect(domain["expiryLabel"] == .null) // nullable, no default
        #expect(domain["category"] == .null)
        #expect(domain["barcode"] == .null)
        #expect(domain["storage"] == .null) // NO decode default (asymmetry)
        #expect(domain["expiryDate"] == .null)
        #expect(domain["addedAt"] == .null)
        #expect(domain["shelfLifeDays"] == .null)
        #expect(domain["remoteVersion"] == .int(0)) // _toInt0
        #expect(domain["clientUpdatedAt"] == .null)
        #expect(domain["deletedAt"] == .null)

        // Pin the exact key set.
        #expect(Set(domain.keys) == Self.inventoryDomainKeys)
    }

    @Test func inventoryRowFromJsonPassesThroughPresentValues() {
        let row: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("鸡蛋"),
            "quantity": .string("12"),
            "unit": .string("个"),
            "image_url": .string("https://x"),
            "freshness_percent": .int(1), // int encoding coerces to double
            "state": .string("expiring"),
            "expiry_label": .string("还剩 2 天"),
            "category": .string("乳品蛋类"),
            "barcode": .string("6900000000000"),
            "storage": .string("freezer"),
            "expiry_date": .string("2026-06-20T00:00:00.000Z"),
            "added_at": .string("2026-06-09T00:00:00.000Z"),
            "shelf_life_days": .int(7),
            "version": .int(5),
            "client_updated_at": .string("2026-06-09T01:00:00.000Z"),
            "deleted_at": .null,
        ]
        let domain = RemoteRowCodec.inventoryRowFromJson(row)

        #expect(domain["quantity"] == .string("12"))
        #expect(domain["imageUrl"] == .string("https://x"))
        #expect(domain["freshnessPercent"] == .double(1.0)) // num.toDouble()
        #expect(domain["state"] == .string("expiring"))
        #expect(domain["storage"] == .string("freezer"))
        #expect(domain["shelfLifeDays"] == .int(7))
        #expect(domain["remoteVersion"] == .int(5))
        #expect(domain["clientUpdatedAt"] == .string("2026-06-09T01:00:00.000Z"))
        #expect(domain["deletedAt"] == .null)
    }

    @Test func inventoryRowForUpsertAppliesEncodeDefaultsAndHousehold() {
        // A sparse domain map (e.g. a local-only row) upserts with encode
        // defaults — storage defaults to 'fridge' here even though decode has no
        // default for it.
        let item: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("番茄"),
        ]
        let row = RemoteRowCodec.inventoryRowForUpsert(householdID: "hh_1", item: item)

        #expect(row["household_id"] == .string("hh_1"))
        #expect(row["id"] == .string(Self.uuid)) // valid UUID written
        #expect(row["name"] == .string("番茄"))
        #expect(row["quantity"] == .null) // no encode default
        #expect(row["image_url"] == .string("")) // _orEmpty
        #expect(row["freshness_percent"] == .double(1.0)) // _orOne
        #expect(row["state"] == .string("fresh")) // _orFresh
        #expect(row["storage"] == .string("fridge")) // _orFridge (encode default)
        #expect(row["expiry_date"] == .null)
        #expect(row["version"] == .int(1)) // versionForUpsert(null) -> 1
        #expect(row["client_updated_at"] == .null)
        #expect(row["deleted_at"] == .null)

        #expect(Set(row.keys) == Self.inventoryRowKeys)
    }

    @Test func inventoryRoundTripPreservesValues() {
        let item: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("酸奶"),
            "quantity": .string("4"),
            "unit": .string("盒"),
            "imageUrl": .string("https://y"),
            "freshnessPercent": .double(0.8),
            "state": .string("expiring"),
            "expiryLabel": .string("还剩 3 天"),
            "category": .string("乳品蛋类"),
            "barcode": .string("123"),
            "storage": .string("freezer"),
            "expiryDate": .string("2026-06-12T00:00:00.000Z"),
            "addedAt": .string("2026-06-09T00:00:00.000Z"),
            "shelfLifeDays": .int(3),
            "remoteVersion": .int(7),
            "clientUpdatedAt": .string("2026-06-09T02:00:00.000Z"),
            "deletedAt": .null,
        ]
        let row = RemoteRowCodec.inventoryRowForUpsert(householdID: "hh_1", item: item)
        // The DB read-back also carries id as a column; merge it in to simulate.
        var readBack = row
        readBack["id"] = .string(Self.uuid)
        let domain = RemoteRowCodec.inventoryRowFromJson(readBack)

        // Domain map equals the original (sans household_id, which is row-only).
        var expected = item
        expected["storage"] = .string("freezer")
        #expect(domain == expected)
    }

    // MARK: - Shopping

    @Test func shoppingRowFromJsonAppliesDefaults() {
        let row: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("酱油"),
        ]
        let domain = RemoteRowCodec.shoppingRowFromJson(row)

        #expect(domain["id"] == .string(Self.uuid))
        #expect(domain["name"] == .string("酱油"))
        #expect(domain["detail"] == .string("")) // _orEmpty
        #expect(domain["imageUrl"] == .null) // nullable, no default
        #expect(domain["category"] == .string("其他")) // _orOther
        #expect(domain["isChecked"] == .bool(false)) // _orFalse
        #expect(domain["remoteVersion"] == .int(0)) // _toInt0
        #expect(domain["clientUpdatedAt"] == .null)
        #expect(domain["deletedAt"] == .null)

        #expect(Set(domain.keys) == Self.shoppingDomainKeys)
    }

    @Test func shoppingRowForUpsertAppliesDefaultsAndKeySet() {
        let item: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("盐"),
        ]
        let row = RemoteRowCodec.shoppingRowForUpsert(householdID: "hh_2", item: item)

        #expect(row["household_id"] == .string("hh_2"))
        #expect(row["id"] == .string(Self.uuid))
        #expect(row["detail"] == .string("")) // _orEmpty
        #expect(row["image_url"] == .null) // nullable passthrough
        #expect(row["category"] == .string("其他")) // _orOther
        #expect(row["is_checked"] == .bool(false)) // _orFalse
        #expect(row["version"] == .int(1)) // versionForUpsert(null)

        #expect(Set(row.keys) == Self.shoppingRowKeys)
    }

    @Test func shoppingRoundTripPreservesValues() {
        let item: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("黄油"),
            "detail": .string("1 块"),
            "imageUrl": .string("https://z"),
            "category": .string("乳品蛋类"),
            "isChecked": .bool(true),
            "remoteVersion": .int(2),
            "clientUpdatedAt": .string("2026-06-09T03:00:00.000Z"),
            "deletedAt": .null,
        ]
        var readBack = RemoteRowCodec.shoppingRowForUpsert(householdID: "hh_2", item: item)
        readBack["id"] = .string(Self.uuid)
        #expect(RemoteRowCodec.shoppingRowFromJson(readBack) == item)
    }

    // MARK: - Version-never-zero rule

    @Test func versionForUpsertNeverReturnsZero() {
        #expect(RemoteRowCodec.versionForUpsert(nil) == 1)
        #expect(RemoteRowCodec.versionForUpsert(.null) == 1)
        #expect(RemoteRowCodec.versionForUpsert(.int(0)) == 1)
        #expect(RemoteRowCodec.versionForUpsert(.int(-3)) == 1)
        #expect(RemoteRowCodec.versionForUpsert(.string("nope")) == 1) // non-numeric -> 0 -> 1
        #expect(RemoteRowCodec.versionForUpsert(.int(4)) == 4)
        #expect(RemoteRowCodec.versionForUpsert(.double(6.9)) == 6) // truncates, then > 0
    }

    @Test func versionZeroUpsertsAsOne() {
        let item: [String: JSONValue] = ["id": .string(Self.uuid), "remoteVersion": .int(0)]
        #expect(RemoteRowCodec.inventoryRowForUpsert(householdID: "hh", item: item)["version"] == .int(1))
        #expect(RemoteRowCodec.shoppingRowForUpsert(householdID: "hh", item: item)["version"] == .int(1))
    }

    // MARK: - applyLocalId / id gating

    @Test func upsertOmitsNonUuidId() {
        // A non-UUID id must be OMITTED so the DB gen_random_uuid() default fills it.
        for badId: JSONValue in [.string("inv_local_1"), .string(""), .int(42), .null] {
            let item: [String: JSONValue] = ["id": badId, "name": .string("x")]
            let inv = RemoteRowCodec.inventoryRowForUpsert(householdID: "hh", item: item)
            let shop = RemoteRowCodec.shoppingRowForUpsert(householdID: "hh", item: item)
            #expect(inv["id"] == nil)
            #expect(shop["id"] == nil)
        }
    }

    @Test func upsertWritesValidUuidId() {
        let item: [String: JSONValue] = ["id": .string(Self.uuid), "name": .string("x")]
        #expect(RemoteRowCodec.inventoryRowForUpsert(householdID: "hh", item: item)["id"] == .string(Self.uuid))
        #expect(RemoteRowCodec.shoppingRowForUpsert(householdID: "hh", item: item)["id"] == .string(Self.uuid))
    }

    @Test func applyLocalIdMutatesInPlaceOnlyForUuid() {
        var row: [String: JSONValue] = [:]
        RemoteRowCodec.applyLocalId(&row, id: .string("not-a-uuid"))
        #expect(row["id"] == nil)
        RemoteRowCodec.applyLocalId(&row, id: .string(Self.uuid))
        #expect(row["id"] == .string(Self.uuid))
    }

    // MARK: - storage decode/encode asymmetry

    @Test func storageHasEncodeDefaultButNoDecodeDefault() {
        // Decode: absent storage stays null (no default).
        let decoded = RemoteRowCodec.inventoryRowFromJson(["id": .string(Self.uuid)])
        #expect(decoded["storage"] == .null)
        // Encode: absent storage defaults to 'fridge'.
        let encoded = RemoteRowCodec.inventoryRowForUpsert(
            householdID: "hh", item: ["id": .string(Self.uuid)]
        )
        #expect(encoded["storage"] == .string("fridge"))
    }

    // MARK: - Custom recipe payload

    @Test func customRecipeFromJsonSpreadsPayloadAndOverridesSyncFields() {
        let payload: [String: JSONValue] = [
            "id": .string("r_payload_id"),
            "name": .string("番茄炒蛋"),
            "ingredients": .array([.object(["name": .string("番茄")])]),
            "remoteVersion": .int(99), // stale value inside payload, overridden below
            "clientUpdatedAt": .string("stale"),
        ]
        let row: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "payload": .object(payload),
            "version": .int(4),
            "client_updated_at": .string("2026-06-09T04:00:00.000Z"),
            "deleted_at": .null,
        ]
        let domain = RemoteRowCodec.customRecipeRowFromJson(row)

        // Whole payload round-trips.
        #expect(domain["name"] == .string("番茄炒蛋"))
        #expect(domain["ingredients"] == .array([.object(["name": .string("番茄")])]))
        // Sync fields overlaid from the real columns, not the payload.
        #expect(domain["id"] == .string(Self.uuid)) // row id wins over payload id
        #expect(domain["remoteVersion"] == .int(4)) // _toInt0(row.version)
        #expect(domain["clientUpdatedAt"] == .string("2026-06-09T04:00:00.000Z"))
        #expect(domain["deletedAt"] == .null)
    }

    @Test func customRecipeFromJsonFallsBackToPayloadIdWhenRowIdAbsent() {
        let row: [String: JSONValue] = [
            "payload": .object(["id": .string("payload_only_id"), "name": .string("汤")]),
            "version": .int(0),
        ]
        let domain = RemoteRowCodec.customRecipeRowFromJson(row)
        #expect(domain["id"] == .string("payload_only_id")) // row['id'] ?? payload['id']
        #expect(domain["remoteVersion"] == .int(0))
        #expect(domain["clientUpdatedAt"] == .null)
        #expect(domain["deletedAt"] == .null)
    }

    @Test func customRecipeFromJsonHandlesMissingPayload() {
        // No payload at all -> empty base, only id + sync fields present.
        let row: [String: JSONValue] = ["id": .string(Self.uuid), "version": .int(2)]
        let domain = RemoteRowCodec.customRecipeRowFromJson(row)
        #expect(Set(domain.keys) == ["id", "remoteVersion", "clientUpdatedAt", "deletedAt"])
        #expect(domain["id"] == .string(Self.uuid))
        #expect(domain["remoteVersion"] == .int(2))
    }

    @Test func customRecipeForUpsertWrapsWholeDomainInPayload() {
        let recipe: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("红烧肉"),
            "steps": .array([.string("切肉"), .string("焯水")]),
            "remoteVersion": .int(0), // -> versionForUpsert -> 1
            "clientUpdatedAt": .string("2026-06-09T05:00:00.000Z"),
            "deletedAt": .null,
        ]
        let row = RemoteRowCodec.customRecipeRowForUpsert(householdID: "hh_3", recipe: recipe)

        #expect(row["household_id"] == .string("hh_3"))
        #expect(row["payload"] == .object(recipe)) // ENTIRE object lives in payload
        #expect(row["version"] == .int(1)) // versionForUpsert(0)
        #expect(row["client_updated_at"] == .string("2026-06-09T05:00:00.000Z"))
        #expect(row["deleted_at"] == .null)
        #expect(row["id"] == .string(Self.uuid)) // valid UUID written
        #expect(Set(row.keys) == Self.payloadRowKeys)
    }

    @Test func customRecipeRoundTripWholeObject() {
        let recipe: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "name": .string("麻婆豆腐"),
            "difficulty": .int(2),
            "tags": .array([.string("快手")]),
            "remoteVersion": .int(5),
            "clientUpdatedAt": .string("2026-06-09T06:00:00.000Z"),
            "deletedAt": .null,
        ]
        var readBack = RemoteRowCodec.customRecipeRowForUpsert(householdID: "hh", recipe: recipe)
        readBack["id"] = .string(Self.uuid) // DB read-back carries id column
        #expect(RemoteRowCodec.customRecipeRowFromJson(readBack) == recipe)
    }

    @Test func customRecipeForUpsertOmitsNonUuidId() {
        let recipe: [String: JSONValue] = ["id": .string("r_local"), "name": .string("x")]
        let row = RemoteRowCodec.customRecipeRowForUpsert(householdID: "hh", recipe: recipe)
        #expect(row["id"] == nil) // DB default fills it
        #expect(row["payload"] == .object(recipe)) // local id still preserved INSIDE payload
    }

    // MARK: - Meal plan entry payload

    @Test func mealPlanEntryRoundTripWholeObject() {
        let entry: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "date": .string("2026-06-10"),
            "mealType": .string("dinner"),
            "recipeId": .string("r_1"),
            "servings": .int(2),
            "remoteVersion": .int(3),
            "clientUpdatedAt": .string("2026-06-09T07:00:00.000Z"),
            "deletedAt": .null,
        ]
        let row = RemoteRowCodec.mealPlanEntryRowForUpsert(householdID: "hh_4", entry: entry)

        #expect(row["household_id"] == .string("hh_4"))
        #expect(row["payload"] == .object(entry))
        #expect(row["version"] == .int(3))
        #expect(row["id"] == .string(Self.uuid))
        #expect(Set(row.keys) == Self.payloadRowKeys)

        var readBack = row
        readBack["id"] = .string(Self.uuid)
        #expect(RemoteRowCodec.mealPlanEntryRowFromJson(readBack) == entry)
    }

    @Test func mealPlanEntryFromJsonOverlaysSyncFields() {
        let row: [String: JSONValue] = [
            "id": .string(Self.uuid),
            "payload": .object(["mealType": .string("lunch")]),
            "version": .int(8),
            "client_updated_at": .string("2026-06-09T08:00:00.000Z"),
            "deleted_at": .string("2026-06-09T09:00:00.000Z"),
        ]
        let domain = RemoteRowCodec.mealPlanEntryRowFromJson(row)
        #expect(domain["mealType"] == .string("lunch"))
        #expect(domain["id"] == .string(Self.uuid))
        #expect(domain["remoteVersion"] == .int(8))
        #expect(domain["clientUpdatedAt"] == .string("2026-06-09T08:00:00.000Z"))
        #expect(domain["deletedAt"] == .string("2026-06-09T09:00:00.000Z"))
    }

    // MARK: - Pinned key sets

    private static let inventoryDomainKeys: Set<String> = [
        "id", "name", "quantity", "unit", "imageUrl", "freshnessPercent", "state",
        "expiryLabel", "category", "barcode", "storage", "expiryDate", "addedAt",
        "shelfLifeDays", "remoteVersion", "clientUpdatedAt", "deletedAt",
    ]

    private static let inventoryRowKeys: Set<String> = [
        "household_id", "id", "name", "quantity", "unit", "image_url",
        "freshness_percent", "state", "expiry_label", "category", "barcode",
        "storage", "expiry_date", "added_at", "shelf_life_days", "version",
        "client_updated_at", "deleted_at",
    ]

    private static let shoppingDomainKeys: Set<String> = [
        "id", "name", "detail", "imageUrl", "category", "isChecked",
        "remoteVersion", "clientUpdatedAt", "deletedAt",
    ]

    private static let shoppingRowKeys: Set<String> = [
        "household_id", "id", "name", "detail", "image_url", "category",
        "is_checked", "version", "client_updated_at", "deleted_at",
    ]

    private static let payloadRowKeys: Set<String> = [
        "household_id", "id", "payload", "version", "client_updated_at", "deleted_at",
    ]
}
