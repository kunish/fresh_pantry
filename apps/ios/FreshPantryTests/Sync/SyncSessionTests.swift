import Foundation
import Testing
@testable import FreshPantry

/// Tests for the app-root `SyncSession`: stable per-install client id (minted
/// once, persisted, reused) and the mutable `selectedHouseholdId` scope. These
/// exercise only the credential-free surface — no Supabase SDK, no SwiftData.
@MainActor
struct SyncSessionTests {
    /// A fresh isolated suite per test so the persisted client id never leaks
    /// between runs (and never touches `.standard`).
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "test.syncsession.\(UUID().uuidString)")!
    }

    /// Lowercase UUID-v4 shape: the same canonical check the codec uses, so the
    /// minted client id is a valid id wherever ids flow.
    private func isLowercaseUuid(_ value: String) -> Bool {
        value == value.lowercased() && ProposalApply.isUuid(value)
    }

    // MARK: - clientId stability

    @Test func clientIdIsStableAcrossInstancesSharingASuite() {
        let defaults = suite()
        let first = SyncSession(defaults: defaults)
        let second = SyncSession(defaults: defaults)

        // Minted once on first launch, then reused — never re-rolled per instance.
        #expect(first.clientId == second.clientId)
    }

    @Test func clientIdPersistsUnderTheFixedKey() {
        let defaults = suite()
        let session = SyncSession(defaults: defaults)

        // The id is written under the documented key so it survives relaunch.
        #expect(defaults.string(forKey: SyncSession.clientIdKey) == session.clientId)
    }

    @Test func freshSuiteYieldsAFreshClientId() {
        let first = SyncSession(defaults: suite())
        let second = SyncSession(defaults: suite())

        // Distinct installs (distinct suites) get distinct client ids — the whole
        // point of moving off the shared Dart constant "local-client".
        #expect(first.clientId != second.clientId)
    }

    @Test func clientIdIsALowercaseUuid() {
        let session = SyncSession(defaults: suite())
        #expect(isLowercaseUuid(session.clientId))
        // Not the Dart constant.
        #expect(session.clientId != "local-client")
    }

    // MARK: - selectedHouseholdId

    @Test func selectedHouseholdIdDefaultsToLocalOnly() {
        let session = SyncSession(defaults: suite())
        #expect(session.selectedHouseholdId == "")
    }

    @Test func selectedHouseholdIdIsMutable() {
        let session = SyncSession(defaults: suite())
        session.selectedHouseholdId = "home"
        #expect(session.selectedHouseholdId == "home")
    }

    @Test func initialHouseholdIdIsHonored() {
        let session = SyncSession(selectedHouseholdId: "home", defaults: suite())
        #expect(session.selectedHouseholdId == "home")
        // Switching it back to local-only mode works too.
        session.selectedHouseholdId = ""
        #expect(session.selectedHouseholdId == "")
    }

    // MARK: - selectedHouseholdId persistence (offline-first launch scope)

    @Test func selectedHouseholdIdSurvivesRelaunch() {
        let defaults = suite()
        let first = SyncSession(defaults: defaults)
        first.selectedHouseholdId = "home"

        // A relaunch (new instance, same suite, default initial id) restores the
        // last scope so household-scoped SwiftData is readable before any network.
        let second = SyncSession(defaults: defaults)
        #expect(second.selectedHouseholdId == "home")
    }

    @Test func assignmentPersistsUnderTheFixedKey() {
        let defaults = suite()
        let session = SyncSession(defaults: defaults)
        session.selectedHouseholdId = "home"
        #expect(defaults.string(forKey: SyncSession.selectedHouseholdIdKey) == "home")
    }

    @Test func signOutResetPersistsLocalOnlyScope() {
        let defaults = suite()
        let first = SyncSession(defaults: defaults)
        first.selectedHouseholdId = "home"
        // Sign-out projects "" into the session; the next launch must NOT
        // resurrect the old household scope.
        first.selectedHouseholdId = ""

        let second = SyncSession(defaults: defaults)
        #expect(second.selectedHouseholdId == "")
    }

    @Test func explicitInitialIdWinsOverPersistedWithoutOverwritingIt() {
        let defaults = suite()
        let first = SyncSession(defaults: defaults)
        first.selectedHouseholdId = "old"

        // An explicit non-empty initial id (tests, previews) is a seed: it wins
        // for this instance but never writes through — a seeded test container
        // must not pollute the persisted scope of the suite it shares.
        let second = SyncSession(selectedHouseholdId: "explicit", defaults: defaults)
        #expect(second.selectedHouseholdId == "explicit")
        #expect(defaults.string(forKey: SyncSession.selectedHouseholdIdKey) == "old")
    }
}
