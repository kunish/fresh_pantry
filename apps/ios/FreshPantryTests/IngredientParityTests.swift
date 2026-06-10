import Foundation
import Testing
@testable import FreshPantry

/// Ingredient JSON round-trip + the exact `fromJson` defaults that keep Supabase
/// sync parity with the Flutter model.
struct IngredientParityTests {
    private func decode(_ json: String) throws -> Ingredient {
        try DomainJSON.decode(Ingredient.self, from: json)
    }

    @Test func appliesFromJsonDefaults() throws {
        // Only name present — every other field must take its documented default.
        let ingredient = try decode(#"{"name":"牛奶"}"#)
        #expect(ingredient.id == "")
        #expect(ingredient.quantity == "1")
        #expect(ingredient.unit == "份")
        #expect(ingredient.imageUrl == "")
        #expect(ingredient.freshnessPercent == 1.0)
        #expect(ingredient.state == .fresh)
        #expect(ingredient.storage == .fridge)
        #expect(ingredient.remoteVersion == 0)
        #expect(ingredient.expiryDate == nil)
        #expect(ingredient.shelfLifeDays == nil)
    }

    @Test func unknownStateFallsBackToFresh() throws {
        let ingredient = try decode(#"{"name":"x","state":"bogus"}"#)
        #expect(ingredient.state == .fresh)
    }

    @Test func unknownStorageFallsBackToFridge() throws {
        let ingredient = try decode(#"{"name":"x","storage":"basement"}"#)
        #expect(ingredient.storage == .fridge)
    }

    @Test func toJsonAlwaysWritesFreshnessPercent() throws {
        let ingredient = Ingredient(
            name: "蛋", quantity: "2", unit: "个", imageUrl: "",
            freshnessPercent: 0.5, state: .fresh
        )
        let data = try DomainJSON.encodeToString(ingredient)
        #expect(data.contains("\"freshnessPercent\":0.5"))
    }

    @Test func toJsonAlwaysWritesNullableKeys() throws {
        // Dart toJson writes every key (null value) — confirm the key set.
        let ingredient = Ingredient(
            name: "x", quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh
        )
        let json = try DomainJSON.encodeToString(ingredient)
        for key in ["expiryLabel", "category", "barcode", "expiryDate", "addedAt",
                    "shelfLifeDays", "clientUpdatedAt", "deletedAt"] {
            #expect(json.contains("\"\(key)\""), "missing key \(key)")
        }
    }

    @Test func roundTripsAllFields() throws {
        let original = Ingredient(
            id: "ing_1", name: "鸡胸", quantity: "1.5", unit: "kg", imageUrl: "http://x/y.png",
            freshnessPercent: 0.42, state: .urgent, expiryLabel: "明天过期",
            category: "肉类海鲜", barcode: "690123", storage: .freezer,
            expiryDate: JSONDate.parse("2026-06-10T00:00:00.000Z"),
            addedAt: JSONDate.parse("2026-06-01T08:30:00.000Z"),
            shelfLifeDays: 3, remoteVersion: 7,
            clientUpdatedAt: JSONDate.parse("2026-06-02T10:00:00.000Z"),
            deletedAt: nil
        )
        let json = try DomainJSON.encodeToString(original)
        let decoded = try DomainJSON.decode(Ingredient.self, from: json)
        #expect(decoded == original)
    }

    @Test func localOnlyIdSemanticPreserved() throws {
        let ingredient = try decode(#"{"name":"x"}"#)
        #expect(ingredient.id.isEmpty) // local-only / never-synced
    }

    // MARK: Tags (custom labels)

    @Test func tagsDefaultToEmptyWhenAbsent() throws {
        let ingredient = try decode(#"{"name":"牛奶"}"#)
        #expect(ingredient.tags.isEmpty)
    }

    @Test func tagsDefaultToEmptyWhenNullOrWrongType() throws {
        // Lenient decode: null / non-array both collapse to [] (no throw).
        #expect(try decode(#"{"name":"x","tags":null}"#).tags.isEmpty)
        #expect(try decode(#"{"name":"x","tags":"oops"}"#).tags.isEmpty)
    }

    @Test func tagsRoundTripAndNormalizeOnDecode() throws {
        // Raw blob with padding, a blank, and a case-dup → canonical on read.
        let ingredient = try decode(#"{"name":"x","tags":["  囤货 ","","BBQ","bbq","孩子的"]}"#)
        #expect(ingredient.tags == ["囤货", "BBQ", "孩子的"]) // trimmed, blank dropped, dedup first-casing
    }

    @Test func tagsNormalizationOwnedByModelInit() {
        // The value-type entry point canonicalizes too (not just decode).
        let ingredient = Ingredient(
            name: "x", quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh,
            tags: [" 待用完", "待用完", "  ", "孩子的"]
        )
        #expect(ingredient.tags == ["待用完", "孩子的"])
    }

    @Test func toJsonAlwaysWritesTagsKey() throws {
        let ingredient = Ingredient(
            name: "x", quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, tags: ["囤货"]
        )
        let json = try DomainJSON.encodeToString(ingredient)
        #expect(json.contains("\"tags\":[\"囤货\"]"))
    }

    @Test func tagsSurviveFullRoundTrip() throws {
        let original = Ingredient(
            name: "鸡胸", quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, tags: ["囤货", "孩子的"]
        )
        let decoded = try DomainJSON.decode(Ingredient.self, from: DomainJSON.encodeToString(original))
        #expect(decoded.tags == ["囤货", "孩子的"])
        #expect(decoded == original) // tags participate in value equality
    }

    @Test func copyWithTagsReplacesAndNormalizes() {
        let original = Ingredient(
            name: "x", quantity: "1", unit: "份", imageUrl: "",
            freshnessPercent: 1.0, state: .fresh, tags: ["旧"]
        )
        let updated = original.copyWith(tags: ["新 ", "新", "另一个"])
        #expect(updated.tags == ["新", "另一个"]) // re-normalized through init
        // Omitting tags preserves the existing list.
        #expect(original.copyWith(name: "y").tags == ["旧"])
    }
}
