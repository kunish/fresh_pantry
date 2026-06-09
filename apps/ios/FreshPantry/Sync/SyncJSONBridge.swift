import Supabase

/// Lossless, total conversion between our domain `JSONValue` box and the
/// Supabase SDK's `AnyJSON`.
///
/// This is the shared currency of the sync layer: `RemoteRowCodec` produces and
/// consumes `[String: JSONValue]`, while the SDK's `insert`/`upsert`/`update`
/// take `Encodable` (`[String: AnyJSON]`) and decode responses back into
/// `[String: AnyJSON]`. Both the gateway and the outbox repository route every
/// remote row through here, so the mapping MUST be byte-faithful in both
/// directions or the wire contract drifts.
///
/// Parity note: the only non-obvious mapping is the case name —
/// `JSONValue.int` ⟷ `AnyJSON.integer` (the SDK spells it `.integer`, not
/// `.int`). Every case is handled explicitly with no `default`, so adding a new
/// `JSONValue` case is a compile error here rather than a silent data drop.
enum SyncJSONBridge {
    /// `JSONValue` -> `AnyJSON`, recursing into arrays and objects.
    static func toAnyJSON(_ value: JSONValue) -> AnyJSON {
        switch value {
        case let .string(string): return .string(string)
        case let .int(int): return .integer(int)
        case let .double(double): return .double(double)
        case let .bool(bool): return .bool(bool)
        case let .array(array): return .array(array.map(toAnyJSON))
        case let .object(object): return .object(object.mapValues(toAnyJSON))
        case .null: return .null
        }
    }

    /// `AnyJSON` -> `JSONValue`, recursing into arrays and objects.
    static func fromAnyJSON(_ value: AnyJSON) -> JSONValue {
        switch value {
        case let .string(string): return .string(string)
        case let .integer(int): return .int(int)
        case let .double(double): return .double(double)
        case let .bool(bool): return .bool(bool)
        case let .array(array): return .array(array.map(fromAnyJSON))
        case let .object(object): return .object(object.mapValues(fromAnyJSON))
        case .null: return .null
        }
    }

    /// Bridges a whole row map `[String: JSONValue]` into the `[String: AnyJSON]`
    /// payload the SDK encodes for `insert`/`upsert`/`update`.
    static func toAnyObject(_ map: [String: JSONValue]) -> [String: AnyJSON] {
        map.mapValues(toAnyJSON)
    }

    /// Bridges a decoded SDK response row `[String: AnyJSON]` back into the
    /// `[String: JSONValue]` shape the codec and merge policy operate on.
    static func fromAnyObject(_ map: [String: AnyJSON]) -> [String: JSONValue] {
        map.mapValues(fromAnyJSON)
    }
}
