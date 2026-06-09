import Foundation

/// Pure (de)serialization for backup blobs — no storage, network, or DI access.
/// It converts `BackupData` (live domain models) to/from a versioned,
/// pretty-printed JSON envelope. The orchestration that reads the live stores on
/// export and writes them on import lives in `BackupController`.
///
/// Version 2 stores structured domain-model lists. Version 1 stored raw
/// SharedPreferences string blobs keyed by legacy keys; after the offline-first
/// migration those keys are no longer the source of truth, so v1 export/import
/// silently lost data. v2 reads/writes the live repository-backed stores instead.
///
/// PARITY (invariant #8): `version == 2` ONLY (v1 + any other rejected); strict
/// decode-before-write so a malformed import can never partially overwrite live
/// data; `addHistory` round-trips as an opaque map; the food-details cache is
/// intentionally excluded. Envelope/payload key names + error messages mirror the
/// Flutter `BackupService` exactly.
enum BackupService {
    static let backupVersion = 2

    /// Typed failures mirroring the Flutter `BackupVersionException` +
    /// `FormatException`s, with the same human-readable messages.
    enum BackupError: Error, Equatable {
        /// Missing / non-int / unsupported `version` (the version negotiation).
        case version(String)
        /// Malformed JSON or a wrong payload shape (the structural validation).
        case format(String)
    }

    // MARK: Encode

    /// Serializes live app data into a versioned, pretty-printed JSON blob.
    ///
    /// `exportedAt` is injectable so tests can pin the timestamp; production
    /// passes the default `Date()` and it is written as ISO8601 UTC.
    static func encode(_ data: BackupData, exportedAt: Date = Date()) -> String {
        var payload: [String: JSONValue] = [
            "inventory": list(data.inventory),
            "addHistory": map(data.addHistory),
            "shopping": list(data.shopping),
            "customRecipes": list(data.customRecipes),
            "mealPlan": list(data.mealPlan),
        ]
        if let aiSettings = data.aiSettings {
            payload["aiSettings"] = object(aiSettings)
        }

        let envelope: JSONValue = .object([
            "version": .int(backupVersion),
            "exportedAt": .string(JSONDate.iso8601(exportedAt)),
            "data": .object(payload),
        ])

        return prettyPrinted(envelope)
    }

    // MARK: Decode

    /// Parses and structurally validates a backup blob into typed `BackupData`.
    ///
    /// Throws `BackupError.version` for a missing/unsupported version and
    /// `BackupError.format` for malformed JSON or wrong payload shapes. Because
    /// all parsing happens here BEFORE any caller writes, a failed decode can
    /// never partially overwrite existing data.
    static func decode(_ string: String) throws -> BackupData {
        guard let data = string.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data)
        else {
            throw BackupError.format("Backup blob is not valid JSON")
        }
        guard let root = raw as? [String: Any] else {
            throw BackupError.format("Backup blob is not a JSON object")
        }
        guard let version = intValue(root["version"]) else {
            throw BackupError.version(
                "Missing or invalid version (got: \(describe(root["version"])))"
            )
        }
        guard version == backupVersion else {
            throw BackupError.version(
                "Unsupported backup version \(version) (expected \(backupVersion))"
            )
        }
        guard let payload = root["data"] as? [String: Any] else {
            throw BackupError.format("Backup data is not a JSON object")
        }

        return BackupData(
            inventory: try parseList(payload, "inventory", as: Ingredient.self),
            addHistory: try parseMap(payload, "addHistory"),
            shopping: try parseList(payload, "shopping", as: ShoppingItem.self),
            customRecipes: try parseList(payload, "customRecipes", as: Recipe.self),
            mealPlan: try parseList(payload, "mealPlan", as: MealPlanEntry.self),
            aiSettings: try parseAiSettings(payload)
        )
    }

    // MARK: Decode helpers (mirror the Dart `_parseList` / `_parseMap`)

    private static func parseList<T: Decodable>(
        _ payload: [String: Any],
        _ key: String,
        as type: T.Type
    ) throws -> [T] {
        let raw = payload[key]
        if raw == nil || raw is NSNull { return [] }
        guard let list = raw as? [Any] else {
            throw BackupError.format("Backup payload for \"\(key)\" must be a JSON list")
        }
        // whereType<Map> then fromJson: non-object elements are skipped, and a
        // structurally-valid object that fails to decode is dropped (lenient,
        // matching the per-row tolerance of the live repositories).
        return list.compactMap { element in
            guard let object = element as? [String: Any] else { return nil }
            return DomainJSON.fromValueMap(T.self, from: jsonValueMap(object))
        }
    }

    private static func parseMap(
        _ payload: [String: Any],
        _ key: String
    ) throws -> [String: AddHistoryEntry] {
        let raw = payload[key]
        if raw == nil || raw is NSNull { return [:] }
        guard let dictionary = raw as? [String: Any] else {
            throw BackupError.format("Backup payload for \"\(key)\" must be a JSON object")
        }
        var result: [String: AddHistoryEntry] = [:]
        for (name, value) in dictionary {
            guard let object = value as? [String: Any],
                  let entry = DomainJSON.fromValueMap(AddHistoryEntry.self, from: jsonValueMap(object))
            else { continue }
            result[name] = entry
        }
        return result
    }

    private static func parseAiSettings(_ payload: [String: Any]) throws -> AiSettings? {
        let raw = payload["aiSettings"]
        if raw == nil || raw is NSNull { return nil }
        guard let object = raw as? [String: Any] else {
            throw BackupError.format("Backup payload for \"aiSettings\" must be a JSON object")
        }
        return DomainJSON.fromValueMap(AiSettings.self, from: jsonValueMap(object))
    }

    // MARK: Encode helpers

    /// `[Encodable]` -> a `JSONValue` array of each element's `toJson()` map.
    private static func list<T: Encodable>(_ items: [T]) -> JSONValue {
        .array(items.map { object($0) })
    }

    /// A single `Encodable`'s `toJson()` map as a `JSONValue.object`.
    private static func object<T: Encodable>(_ value: T) -> JSONValue {
        guard let map = DomainJSON.valueMap(value) else { return .object([:]) }
        return .object(map)
    }

    /// The add-history frequency map -> a `JSONValue.object` of each entry's JSON.
    private static func map(_ history: [String: AddHistoryEntry]) -> JSONValue {
        .object(history.mapValues { object($0) })
    }

    /// Pretty-prints a `JSONValue` envelope with 2-space indentation + sorted keys
    /// (Foundation's `.prettyPrinted` uses 2-space indent, matching Dart's
    /// `JsonEncoder.withIndent('  ')`; `.sortedKeys` makes the output stable).
    private static func prettyPrinted(_ value: JSONValue) -> String {
        guard let encoded = try? DomainJSON.encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: encoded),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: pretty, encoding: .utf8)
        else { return "{}" }
        return string
    }

    // MARK: JSON value bridging

    /// Re-decodes a `JSONSerialization` `[String: Any]` object into the strongly
    /// typed `[String: JSONValue]` the domain `fromValueMap` expects.
    private static func jsonValueMap(_ object: [String: Any]) -> [String: JSONValue] {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let map = try? DomainJSON.decoder.decode([String: JSONValue].self, from: data)
        else { return [:] }
        return map
    }

    /// Strict int extraction matching Dart's `version is! int`: a JSON int passes,
    /// a bool / double / string / absent value does NOT.
    private static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        // Reject booleans (NSNumber bridges `true`/`false`) and non-integral doubles.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let type = String(cString: number.objCType)
        // Floating-point JSON numbers (e.g. 2.5) are not ints.
        if type == "d" || type == "f" { return nil }
        return number.intValue
    }

    private static func describe(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "null" }
        return String(describing: value)
    }
}
