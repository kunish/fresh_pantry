import Foundation
import Testing
@testable import FreshPantry

/// Tests for the secret-backed AI-settings store. Uses an in-memory
/// `SecretStore` fake (NEVER the real Keychain, which is entitlement-gated in the
/// unit-test host) to exercise the round-trip, `isConfigured`, defensive decode,
/// the wire shape, and `clear`.
@MainActor
struct AiSettingsStoreTests {
    // MARK: Defaults

    @Test func freshStoreIsEmptyAndUnconfigured() {
        let store = AiSettingsStore(secrets: InMemorySecretStore())
        #expect(store.settings == .empty)
        #expect(!store.isConfigured)
    }

    // MARK: Round-trip through the SecretStore fake

    @Test func saveRoundTripsThroughSecretStore() {
        let secrets = InMemorySecretStore()
        let store = AiSettingsStore(secrets: secrets)

        let settings = AiSettings(baseUrl: "https://x/v1", apiKey: "sk-123", model: "gpt-4o", timeout: 90)
        store.save(settings)
        #expect(store.settings == settings)
        #expect(store.isConfigured)

        // A new store over the same secret store reads the persisted blob.
        let reloaded = AiSettingsStore(secrets: secrets)
        #expect(reloaded.settings == settings)
        #expect(reloaded.settings.timeout == 90)
        #expect(reloaded.isConfigured)
    }

    // MARK: isConfigured

    @Test func isConfiguredRequiresAllThreeCoreFields() {
        let store = AiSettingsStore(secrets: InMemorySecretStore())
        store.save(AiSettings(baseUrl: "https://x/v1", apiKey: "", model: "gpt-4o"))
        #expect(!store.isConfigured) // missing apiKey
        store.save(AiSettings(baseUrl: "https://x/v1", apiKey: "sk", model: "gpt-4o"))
        #expect(store.isConfigured)
    }

    // MARK: Wire shape (Flutter-compatible keys)

    @Test func persistedBlobUsesFlutterKeys() throws {
        let secrets = InMemorySecretStore()
        let store = AiSettingsStore(secrets: secrets)
        store.save(AiSettings(baseUrl: "https://x/v1", apiKey: "sk", model: "m", timeout: 45))

        let data = try #require(secrets.get(AiSettingsStore.storageKey))
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["baseUrl"] as? String == "https://x/v1")
        #expect(object["apiKey"] as? String == "sk")
        #expect(object["model"] as? String == "m")
        // timeout serializes as an Int `timeoutSeconds`.
        #expect(object["timeoutSeconds"] as? Int == 45)
    }

    // MARK: clear

    @Test func clearResetsToEmpty() {
        let secrets = InMemorySecretStore()
        let store = AiSettingsStore(secrets: secrets)
        store.save(AiSettings(baseUrl: "https://x/v1", apiKey: "sk", model: "m"))
        store.clear()
        #expect(store.settings == .empty)
        #expect(secrets.get(AiSettingsStore.storageKey) == nil)
        // A reload also sees the cleared state.
        #expect(AiSettingsStore(secrets: secrets).settings == .empty)
    }

    // MARK: Defensive decode

    @Test func decodeHandlesNilAndMalformed() {
        #expect(AiSettingsStore.decode(nil) == .empty)
        #expect(AiSettingsStore.decode(Data("not json".utf8)) == .empty)
        // Partial blob: present keys honored, missing fall back via the model.
        let partial = AiSettingsStore.decode(Data(#"{"model":"gpt-4o"}"#.utf8))
        #expect(partial.model == "gpt-4o")
        #expect(partial.baseUrl.isEmpty)
        #expect(partial.timeout == 60) // model default
    }

    // MARK: Seeded read

    @Test func readsPreSeededSecret() {
        let blob = Data(#"{"baseUrl":"https://y/v1","apiKey":"k","model":"m","timeoutSeconds":30}"#.utf8)
        let secrets = InMemorySecretStore(seed: [AiSettingsStore.storageKey: blob])
        let store = AiSettingsStore(secrets: secrets)
        #expect(store.settings.baseUrl == "https://y/v1")
        #expect(store.settings.timeout == 30)
        #expect(store.isConfigured)
    }
}
