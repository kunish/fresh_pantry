import Foundation

/// Pure 3-way, field-level conflict resolver for a contended remote write,
/// ported from Flutter `lib/sync/merge_policy.dart` (`mergeRemotePatch` +
/// `MergeResult`).
///
/// POLICY (parity-critical): the client patch is the LAST WRITER and ALWAYS
/// wins at the field level. Conflicts are only *reported* (telemetry) — they
/// never block or alter the written value. The merge never throws.
///
/// The conflict signal answers one question per patched field: did the remote
/// row diverge from BOTH the client's pre-edit base AND the value the client is
/// now writing? If the remote already matches either side there's no real
/// divergence, so it is not flagged.
struct MergeResult: Equatable, Sendable {
    /// The value that will be persisted — remote rebased with the patch applied,
    /// patch winning every overlapping field.
    var value: [String: JSONValue]
    /// Whether any field genuinely diverged (equivalent to
    /// `!conflictFields.isEmpty`); surfaced for callers that only want the flag.
    var conflict: Bool
    /// The patched fields whose remote value differed from both local and patch,
    /// in patch-iteration order — emitted as conflict telemetry.
    var conflictFields: [String]
}

enum MergePolicy {
    /// Resolves `patch` against a contended `remote` row.
    ///
    /// - Parameters:
    ///   - local: the client's snapshot the patch was computed against (its
    ///     pre-edit base values).
    ///   - remote: the authoritative row currently on the server.
    ///   - patch: the client's intended field writes (patch wins, always).
    ///   - baseVersion: the `remoteVersion` the client based its edit on, or nil
    ///     when the write carries no optimistic base (e.g. a create).
    ///   - remoteVersion: the version the server row is at right now.
    static func mergeRemotePatch(
        local: [String: JSONValue],
        remote: [String: JSONValue],
        patch: [String: JSONValue],
        baseVersion: Int?,
        remoteVersion: Int
    ) -> MergeResult {
        // FAST PATH: no optimistic base, or the server hasn't moved since the
        // client read it — nothing to reconcile. Mirrors Dart `{...remote,
        // ...patch}`: start from remote, overlay the patch so the patch wins
        // every shared key. No field can be in conflict.
        if baseVersion == nil || baseVersion == remoteVersion {
            var value = remote
            for (field, patchValue) in patch {
                value[field] = patchValue
            }
            return MergeResult(value: value, conflict: false, conflictFields: [])
        }

        // DIVERGENT BASE: the server moved between the client's read and write.
        // Rebase the patch onto the live remote field by field, flagging only
        // fields where the remote diverged from BOTH the client's base and the
        // value being written.
        var merged = remote
        var conflicts: [String] = []

        for (field, patchValue) in patch {
            // An absent key reads as `null` in Dart, and `_jsonValueEquals`
            // treats two nulls as equal. Normalize a missing Swift key to
            // `.null` so an absent base that the patch also leaves null does not
            // register as a spurious conflict.
            let localValue = local[field] ?? .null
            let remoteValue = remote[field] ?? .null

            // Dart's `_jsonValueEquals` is deep AND compares numbers cross-type
            // (`2 == 2.0`). Swift's synthesized `JSONValue.==` is case-strict
            // (`.int(2) != .double(2.0)`), so a whole-number column decoded from
            // jsonb as `.int` compared against a local `.double` would be
            // mis-flagged as a spurious conflict (quantity / freshness_percent
            // hit this on real data). `jsonEqual` bridges int/double recursively
            // to keep the conflict signal byte-faithful to Flutter.
            let remoteMatchesBase = jsonEqual(remoteValue, localValue)
            let remoteMatchesPatch = jsonEqual(remoteValue, patchValue)

            merged[field] = patchValue
            if remoteMatchesBase || remoteMatchesPatch { continue }
            conflicts.append(field)
        }

        return MergeResult(
            value: merged,
            conflict: !conflicts.isEmpty,
            conflictFields: conflicts
        )
    }

    /// Deep JSON equality mirroring Dart's recursive `_jsonValueEquals`, where
    /// numeric values compare CROSS-TYPE (`2 == 2.0`). This is the one place the
    /// merge must NOT use the synthesized `JSONValue.==`: jsonb whole-numbers
    /// decode as `.int` while the local domain map carries `.double`, and Flutter
    /// reports no conflict for them. Bool/int are kept distinct (Dart `true != 1`).
    private static func jsonEqual(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case let (.int(x), .int(y)): return x == y
        case let (.double(x), .double(y)): return x == y
        case let (.int(x), .double(y)): return Double(x) == y
        case let (.double(x), .int(y)): return x == Double(y)
        case let (.string(x), .string(y)): return x == y
        case let (.bool(x), .bool(y)): return x == y
        case (.null, .null): return true
        case let (.array(x), .array(y)):
            guard x.count == y.count else { return false }
            for (lhs, rhs) in zip(x, y) where !jsonEqual(lhs, rhs) { return false }
            return true
        case let (.object(x), .object(y)):
            guard x.count == y.count else { return false }
            for (key, lhs) in x {
                guard let rhs = y[key], jsonEqual(lhs, rhs) else { return false }
            }
            return true
        default:
            return false
        }
    }
}
