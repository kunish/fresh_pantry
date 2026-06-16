import Foundation
import Testing
import FreshPantryWidgetKit
@testable import FreshPantry

struct WidgetSharedDefaultsTests {
    /// 用一个独立的内存 suite,避免污染真实 App Group。
    private func makeSuite(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func writeThenReadIdentityRoundTrips() {
        let suite = makeSuite("test.widgetdefaults.roundtrip")
        WidgetSharedDefaults.writeIdentity(householdID: "hh-1", clientID: "cli-9", into: suite)
        #expect(WidgetSharedDefaults.readHouseholdID(from: suite) == "hh-1")
        #expect(WidgetSharedDefaults.readClientID(from: suite) == "cli-9")
    }

    @Test func readsEmptyHouseholdWhenUnset() {
        let suite = makeSuite("test.widgetdefaults.empty")
        #expect(WidgetSharedDefaults.readHouseholdID(from: suite) == "")
        #expect(WidgetSharedDefaults.readClientID(from: suite) == "")
    }

    @Test func writeOverwritesPrevious() {
        let suite = makeSuite("test.widgetdefaults.overwrite")
        WidgetSharedDefaults.writeIdentity(householdID: "a", clientID: "c1", into: suite)
        WidgetSharedDefaults.writeIdentity(householdID: "b", clientID: "c2", into: suite)
        #expect(WidgetSharedDefaults.readHouseholdID(from: suite) == "b")
        #expect(WidgetSharedDefaults.readClientID(from: suite) == "c2")
    }
}
