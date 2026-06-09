import Supabase
import Testing
@testable import FreshPantry

/// Lossless, total parity for `SyncJSONBridge`: every scalar case round-trips in
/// both directions, the `.int` ⟷ `.integer` name difference is honored, and a
/// nested object holding an array of mixed scalars (incl. null) survives both
/// `JSONValue -> AnyJSON -> JSONValue` and `AnyJSON -> JSONValue -> AnyJSON`
/// unchanged. Pure value mapping — no live credentials required.
struct SyncJSONBridgeTests {
    // MARK: Scalar round-trips (JSONValue -> AnyJSON -> JSONValue)

    @Test func scalarsRoundTripThroughAnyJSON() {
        let scalars: [JSONValue] = [
            .string("hello"),
            .int(42),
            .double(3.5),
            .bool(true),
            .bool(false),
            .null,
        ]
        for scalar in scalars {
            let bridged = SyncJSONBridge.fromAnyJSON(SyncJSONBridge.toAnyJSON(scalar))
            #expect(bridged == scalar)
        }
    }

    // MARK: Case-name parity (.int <-> .integer)

    @Test func anyJSONIntegerMapsToJSONValueInt() {
        // The SDK spells the whole-number case `.integer`; ours is `.int`. An
        // AnyJSON.integer must bridge to JSONValue.int specifically.
        #expect(SyncJSONBridge.fromAnyJSON(.integer(5)) == .int(5))
    }

    @Test func jsonValueIntMapsToAnyJSONInteger() {
        #expect(SyncJSONBridge.toAnyJSON(.int(5)) == AnyJSON.integer(5))
    }

    @Test func scalarsMapToExpectedAnyJSONCases() {
        #expect(SyncJSONBridge.toAnyJSON(.string("x")) == AnyJSON.string("x"))
        #expect(SyncJSONBridge.toAnyJSON(.double(1.5)) == AnyJSON.double(1.5))
        #expect(SyncJSONBridge.toAnyJSON(.bool(true)) == AnyJSON.bool(true))
        #expect(SyncJSONBridge.toAnyJSON(.null) == AnyJSON.null)
    }

    // MARK: Nested structure round-trips

    /// A nested object containing an array of mixed scalars (null, int, double,
    /// bool, string) plus a nested object survives `JSONValue -> AnyJSON ->
    /// JSONValue` unchanged.
    @Test func nestedStructureRoundTripsJSONValueFirst() {
        let original: JSONValue = .object([
            "mixed": .array([
                .null,
                .int(7),
                .double(2.25),
                .bool(false),
                .string("s"),
            ]),
            "nested": .object([
                "flag": .bool(true),
                "count": .int(0),
            ]),
            "name": .string("row"),
        ])
        let bridged = SyncJSONBridge.fromAnyJSON(SyncJSONBridge.toAnyJSON(original))
        #expect(bridged == original)
    }

    /// The same structure expressed as `AnyJSON` survives `AnyJSON -> JSONValue
    /// -> AnyJSON` unchanged.
    @Test func nestedStructureRoundTripsAnyJSONFirst() {
        let original: AnyJSON = .object([
            "mixed": .array([
                .null,
                .integer(7),
                .double(2.25),
                .bool(false),
                .string("s"),
            ]),
            "nested": .object([
                "flag": .bool(true),
                "count": .integer(0),
            ]),
            "name": .string("row"),
        ])
        let bridged = SyncJSONBridge.toAnyJSON(SyncJSONBridge.fromAnyJSON(original))
        #expect(bridged == original)
    }

    // MARK: Whole-map helpers

    @Test func toAnyObjectAndBackRoundTripsWholeRow() {
        let row: [String: JSONValue] = [
            "id": .string("abc"),
            "version": .int(3),
            "freshness": .double(0.75),
            "checked": .bool(false),
            "deleted_at": .null,
            "tags": .array([.string("a"), .string("b")]),
        ]
        let roundTripped = SyncJSONBridge.fromAnyObject(SyncJSONBridge.toAnyObject(row))
        #expect(roundTripped == row)
    }
}
