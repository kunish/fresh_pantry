import Foundation
import Supabase

/// A `UserDefaults`-backed Supabase auth-session store, used ONLY in the
/// simulator. The SDK's default `KeychainLocalStorage` cannot persist the session
/// on an unsigned simulator build (no keychain entitlement / access group), so
/// `store` throws, `auth.session` never resolves, and every authenticated request
/// silently falls back to the anon key (RLS then returns empty → the app behaves
/// as if the user has no household and sync never starts).
///
/// The signed device / TestFlight build keeps `KeychainLocalStorage` (encrypted
/// at rest); this is wired in `SupabaseClientProvider` behind
/// `#if targetEnvironment(simulator)`. `UserDefaults.standard` is documented as
/// thread-safe, so the store needs no stored state to satisfy `Sendable`.
struct UserDefaultsAuthStorage: AuthLocalStorage {
    private static let prefix = "supabase.auth."

    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: Self.prefix + key)
    }

    func retrieve(key: String) throws -> Data? {
        UserDefaults.standard.data(forKey: Self.prefix + key)
    }

    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: Self.prefix + key)
    }
}
