import Foundation
import Testing
@testable import FreshPantry

/// Behavior tests for `DietPreferenceStore` — the local 饮食偏好 preset selection.
@MainActor
struct DietPreferenceStoreTests {
    private func makeStore() -> DietPreferenceStore {
        DietPreferenceStore(defaults: UserDefaults(suiteName: "test.dietpref.\(UUID().uuidString)")!)
    }

    @Test func togglePersistsAndReloads() {
        let suite = "test.dietpref.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DietPreferenceStore(defaults: defaults)
        store.toggle("高蛋白")
        store.toggle("素食")
        store.toggle("高蛋白") // toggling off
        #expect(store.selected == ["素食"])
        // A fresh instance reads the persisted set.
        let reloaded = DietPreferenceStore(defaults: defaults)
        #expect(reloaded.selected == ["素食"])
        #expect(reloaded.isSelected("素食"))
        #expect(!reloaded.isSelected("高蛋白"))
    }

    @Test func setOnOffIsIdempotent() {
        let store = makeStore()
        store.set("快手菜", on: true)
        store.set("快手菜", on: true)
        #expect(store.selected == ["快手菜"])
        store.set("快手菜", on: false)
        #expect(store.selected.isEmpty)
    }

    @Test func blankLabelIsNoOp() {
        let store = makeStore()
        store.toggle("   ")
        #expect(store.selected.isEmpty)
    }

    @Test func allLabelsAreTheSevenPresets() {
        #expect(DietPreferenceStore.allLabels == ["高蛋白", "低脂", "素食", "家常菜", "快手菜", "儿童餐", "低碳水"])
    }

    @Test func decodeIsDefensive() {
        #expect(DietPreferenceStore.decode(nil).isEmpty)
        #expect(DietPreferenceStore.decode("not json").isEmpty)
        #expect(DietPreferenceStore.decode("[\"素食\",\"\",\"高蛋白\"]") == ["素食", "高蛋白"])
    }
}
