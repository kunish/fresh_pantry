import Foundation
import SwiftData
import Testing
@testable import FreshPantry

struct ProfileRepositoryTests {
    private func container() throws -> ModelContainer { try ModelContainerFactory.makeInMemory() }

    @Test func loadNilWhenEmpty() async throws {
        let repo = ProfileRepository(modelContainer: try container())
        #expect(try await repo.load() == nil)
    }

    @Test func saveThenLoadRoundTrip() async throws {
        let repo = ProfileRepository(modelContainer: try container())
        let profile = UserProfile(id: "u1", email: "a@b.com", displayName: "小明", nickname: "明", avatarPath: "u1/x.jpg")
        try await repo.save(profile, pendingUpload: true)
        let loaded = try await repo.load()
        #expect(loaded?.profile == profile)
        #expect(loaded?.pendingUpload == true)
    }

    @Test func saveIsSingleRow() async throws {
        let repo = ProfileRepository(modelContainer: try container())
        try await repo.save(UserProfile(id: "u1", displayName: "A"), pendingUpload: false)
        try await repo.save(UserProfile(id: "u1", displayName: "B"), pendingUpload: false)
        let loaded = try await repo.load()
        #expect(loaded?.profile.displayName == "B")
        #expect(try await repo.count() == 1)
    }
}
