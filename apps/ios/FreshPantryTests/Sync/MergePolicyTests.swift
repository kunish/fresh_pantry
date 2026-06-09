import Foundation
import Testing
@testable import FreshPantry

/// Byte-faithful parity with Flutter `lib/sync/merge_policy.dart`
/// (`mergeRemotePatch` + `MergeResult`): fast path, divergent-base conflict
/// detection, deep equality on nested structures, and the absent-key-vs-null
/// edge case (`_jsonValueEquals` treats a missing key as `null`).
struct MergePolicyTests {
    // MARK: Fast path (baseVersion nil / baseVersion == remoteVersion)

    @Test func fastPathNilBaseTakesRemoteOverlaidWithPatch() {
        // {...remote, ...patch}: patch wins overlapping keys, remote-only keys
        // survive, patch-only keys are added.
        let result = MergePolicy.mergeRemotePatch(
            local: ["name": .string("old")],
            remote: ["name": .string("remote"), "qty": .int(3)],
            patch: ["name": .string("patched"), "note": .string("hi")],
            baseVersion: nil,
            remoteVersion: 7
        )
        #expect(result.value == [
            "name": .string("patched"), // patch wins overlap
            "qty": .int(3),             // remote-only preserved
            "note": .string("hi"),      // patch-only added
        ])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    @Test func fastPathEqualVersionTakesRemoteOverlaidWithPatch() {
        // baseVersion == remoteVersion: server hasn't moved, no reconciliation.
        let result = MergePolicy.mergeRemotePatch(
            local: ["name": .string("base")],
            remote: ["name": .string("serverDiverged"), "extra": .bool(true)],
            patch: ["name": .string("clientWrite")],
            baseVersion: 5,
            remoteVersion: 5
        )
        // Even though remote diverged from local, the equal version short-circuits
        // to the fast path with NO conflict (parity: Dart checks version first).
        #expect(result.value == [
            "name": .string("clientWrite"),
            "extra": .bool(true),
        ])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    // MARK: Divergent base — no conflict

    @Test func divergentBaseRemoteUnchangedFromLocalIsNoConflict() {
        // Remote == local base (server never moved this field from the client's
        // base), so applying the patch is safe and not a conflict.
        let result = MergePolicy.mergeRemotePatch(
            local: ["name": .string("apple")],
            remote: ["name": .string("apple"), "qty": .int(2)],
            patch: ["name": .string("apricot")],
            baseVersion: 4,
            remoteVersion: 9
        )
        #expect(result.value == [
            "name": .string("apricot"),
            "qty": .int(2),
        ])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    @Test func divergentBaseRemoteEqualsPatchIsNoConflict() {
        // Remote already matches what the client is writing — no real divergence.
        let result = MergePolicy.mergeRemotePatch(
            local: ["name": .string("base")],
            remote: ["name": .string("converged")],
            patch: ["name": .string("converged")],
            baseVersion: 1,
            remoteVersion: 2
        )
        #expect(result.value == ["name": .string("converged")])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    // MARK: Divergent base — conflict reported, patch still wins

    @Test func divergentBaseRemoteDiffersFromBothIsConflict() {
        // Remote differs from BOTH local base and patch -> genuine conflict.
        // Value still takes the patch (last-writer wins).
        let result = MergePolicy.mergeRemotePatch(
            local: ["name": .string("base")],
            remote: ["name": .string("someoneElse")],
            patch: ["name": .string("mine")],
            baseVersion: 1,
            remoteVersion: 2
        )
        #expect(result.value == ["name": .string("mine")]) // patch wins
        #expect(result.conflict == true)
        #expect(result.conflictFields == ["name"])
    }

    // MARK: Multiple fields — mixed conflict / no-conflict

    @Test func multipleFieldsMixedConflictReportsOnlyDivergent() {
        // a: remote == local -> ok; b: remote == patch -> ok; c: remote differs
        // from both -> conflict. All three take their patch value.
        let result = MergePolicy.mergeRemotePatch(
            local: ["a": .int(1), "b": .int(10), "c": .int(100)],
            remote: ["a": .int(1), "b": .int(20), "c": .int(999), "keep": .string("x")],
            patch: ["a": .int(2), "b": .int(20), "c": .int(200)],
            baseVersion: 3,
            remoteVersion: 8
        )
        #expect(result.value == [
            "a": .int(2),          // patch
            "b": .int(20),         // patch (== remote)
            "c": .int(200),        // patch (conflict)
            "keep": .string("x"),  // remote-only preserved
        ])
        #expect(result.conflict == true)
        #expect(result.conflictFields == ["c"]) // only the genuinely divergent field
    }

    // MARK: Deep equality — nested object / array

    @Test func nestedObjectDeepEqualityNoConflict() {
        // Remote nested object deep-equals local -> no conflict despite being a
        // distinct value (JSONValue `==` is deep).
        let nested: JSONValue = .object(["k": .array([.int(1), .int(2)])])
        let result = MergePolicy.mergeRemotePatch(
            local: ["cfg": nested],
            remote: ["cfg": .object(["k": .array([.int(1), .int(2)])])],
            patch: ["cfg": .object(["k": .array([.int(9)])])],
            baseVersion: 1,
            remoteVersion: 4
        )
        #expect(result.value == ["cfg": .object(["k": .array([.int(9)])])])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    @Test func nestedArrayDiffersFromBothIsConflict() {
        // Remote array differs from both local and patch at a deep position.
        let result = MergePolicy.mergeRemotePatch(
            local: ["tags": .array([.string("a"), .string("b")])],
            remote: ["tags": .array([.string("a"), .string("z")])],
            patch: ["tags": .array([.string("a"), .string("c")])],
            baseVersion: 2,
            remoteVersion: 5
        )
        #expect(result.value == ["tags": .array([.string("a"), .string("c")])])
        #expect(result.conflict == true)
        #expect(result.conflictFields == ["tags"])
    }

    // MARK: Absent-key vs null edge case

    @Test func absentLocalKeyMatchingNullPatchIsNoConflict() {
        // local has no "deletedAt" key (reads as null in Dart); remote is null;
        // patch writes null. Two nulls compare equal -> no conflict.
        let result = MergePolicy.mergeRemotePatch(
            local: [:],
            remote: ["deletedAt": .null],
            patch: ["deletedAt": .null],
            baseVersion: 1,
            remoteVersion: 2
        )
        #expect(result.value == ["deletedAt": .null])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    @Test func absentRemoteKeyTreatedAsNullEqualsAbsentLocal() {
        // Neither local nor remote carry the key (both read as null); patch sets
        // a value. remote(null) != patch and remote(null) == local(null) -> the
        // base-match branch fires first -> no conflict.
        let result = MergePolicy.mergeRemotePatch(
            local: [:],
            remote: [:],
            patch: ["flag": .bool(true)],
            baseVersion: 1,
            remoteVersion: 2
        )
        #expect(result.value == ["flag": .bool(true)])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    @Test func absentLocalButRemotePresentDiffersFromPatchIsConflict() {
        // local absent (null base); remote present and differs from patch ->
        // remote(value) != local(null) and remote(value) != patch -> conflict.
        let result = MergePolicy.mergeRemotePatch(
            local: [:],
            remote: ["name": .string("server")],
            patch: ["name": .string("client")],
            baseVersion: 1,
            remoteVersion: 2
        )
        #expect(result.value == ["name": .string("client")])
        #expect(result.conflict == true)
        #expect(result.conflictFields == ["name"])
    }

    @Test func emptyPatchOnDivergentBaseIsNoConflict() {
        // No patched fields -> nothing to reconcile, value is the remote as-is.
        let result = MergePolicy.mergeRemotePatch(
            local: ["a": .int(1)],
            remote: ["a": .int(2)],
            patch: [:],
            baseVersion: 1,
            remoteVersion: 9
        )
        #expect(result.value == ["a": .int(2)])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    // MARK: Cross-type numeric equality (Dart `2 == 2.0`)

    @Test func divergentBaseIntRemoteVsDoublePatchIsNoConflict() {
        // jsonb decodes a whole-number `quantity` as `.int(2)` (JSONValue tries
        // Int before Double); the local domain map carries `.double(2.0)`. Dart's
        // `_jsonValueEquals` compares numbers cross-type so this is NOT a conflict.
        // The synthesized `JSONValue.==` would mis-flag it — the bridge prevents that.
        let result = MergePolicy.mergeRemotePatch(
            local: ["quantity": .double(2.0)],
            remote: ["quantity": .int(2)],
            patch: ["quantity": .double(2.0)],
            baseVersion: 1,
            remoteVersion: 4
        )
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    @Test func divergentBaseDoubleRemoteEqualsIntBaseIsNoConflict() {
        // Symmetric: remote `.double(1.0)` matches local base `.int(1)` cross-type,
        // so applying the patch is safe (no real divergence from base).
        let result = MergePolicy.mergeRemotePatch(
            local: ["freshness": .int(1)],
            remote: ["freshness": .double(1.0)],
            patch: ["freshness": .double(0.5)],
            baseVersion: 2,
            remoteVersion: 6
        )
        #expect(result.value == ["freshness": .double(0.5)])
        #expect(result.conflict == false)
        #expect(result.conflictFields.isEmpty)
    }

    @Test func crossTypeNumericBridgesInsideNestedArray() {
        // The bridge must recurse: remote `[1, 2.0]` deep-equals patch `[1.0, 2]`.
        let result = MergePolicy.mergeRemotePatch(
            local: ["v": .array([.int(9)])],
            remote: ["v": .array([.int(1), .double(2.0)])],
            patch: ["v": .array([.double(1.0), .int(2)])],
            baseVersion: 1,
            remoteVersion: 3
        )
        #expect(result.conflict == false) // remote == patch cross-type
        #expect(result.conflictFields.isEmpty)
    }

    @Test func boolAndIntStayDistinct() {
        // Dart keeps bool and num distinct (`true != 1`); the bridge must NOT
        // collapse them. remote `.bool(true)` differs from both base and patch.
        let result = MergePolicy.mergeRemotePatch(
            local: ["flag": .int(1)],
            remote: ["flag": .bool(true)],
            patch: ["flag": .int(0)],
            baseVersion: 1,
            remoteVersion: 2
        )
        #expect(result.conflict == true)
        #expect(result.conflictFields == ["flag"])
    }
}
