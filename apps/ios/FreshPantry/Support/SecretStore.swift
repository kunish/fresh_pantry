import Foundation

/// Storage seam for secret blobs (API keys, and — in P7 — auth/session tokens).
///
/// A tiny `get/set/delete` `Data` interface keyed by a string. The production
/// impl is `KeychainStore` (encrypted, device-only); tests inject
/// `InMemorySecretStore` so they never touch the real Keychain (which is often
/// unavailable / entitlement-gated in the unit-test host process).
///
/// Mirrors `StorageAdapter` from the Flutter layer but for the *secret* half:
/// non-secret settings (reminders, dietary) stay in `UserDefaults`, secrets
/// (AI key, future auth tokens) live here behind the Keychain.
protocol SecretStore: Sendable {
    /// Returns the stored blob for `key`, or `nil` if absent / unreadable.
    func get(_ key: String) -> Data?
    /// Persists `value` under `key` (replacing any existing blob).
    /// Returns `false` if the backing store rejected the write.
    @discardableResult
    func set(_ value: Data, forKey key: String) -> Bool
    /// Removes any blob stored under `key` (no-op if absent).
    func delete(_ key: String)
}

/// In-memory `SecretStore` for tests and previews — no Keychain access.
///
/// `@unchecked Sendable`: guarded by an internal lock so the reference type can
/// cross actor boundaries safely under Swift 6 strict concurrency.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data]

    init(seed: [String: Data] = [:]) {
        self.storage = seed
    }

    func get(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    @discardableResult
    func set(_ value: Data, forKey key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
        return true
    }

    func delete(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
