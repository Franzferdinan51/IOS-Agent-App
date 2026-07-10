import Foundation
import KeychainAccess

/// A simple wrapper around KeychainAccess for storing and retrieving strings and data.
///
/// Every entry is created with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// and `synchronizable = false`. That has two effects we care about:
///   1. The credential is *not* available until the user has unlocked the
///      device once after boot — so background processes and pre-login
///      launches can't read it.
///   2. The credential is *not* synced to iCloud Keychain and *not*
///      included in device-to-device migrations, so a stolen iCloud
///      backup or a swap to a new phone does not leak the secret.
final class KeychainStore {
    private let keychain: Keychain

    /// Creates a KeychainStore with a given service name.
    /// - Parameter service: The service identifier used as a prefix for all keys.
    init(service: String = "com.dualagent") {
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
            .synchronizable(false)
    }

    /// Saves a string value to the keychain.
    /// - Parameters:
    ///   - value: The string to save.
    ///   - key: The key to associate with the value.
    func save(_ value: String, forKey key: String) {
        try? keychain.set(value, key: key)
    }

    /// Retrieves a string value from the keychain.
    /// - Parameter key: The key associated with the value.
    /// - Returns: The stored string, or nil if not found.
    func read(forKey key: String) -> String? {
        return try? keychain.get(key)
    }

    /// Deletes a value from the keychain.
    /// - Parameter key: The key to delete.
    func delete(forKey key: String) {
        try? keychain.remove(key)
    }

    /// Saves raw data to the keychain.
    /// - Parameters:
    ///   - data: The data to save.
    ///   - key: The key to associate with the data.
    func saveData(_ data: Data, forKey key: String) {
        try? keychain.set(data, key: key)
    }

    // MARK: - Known key names

    /// Jupiter aggregator API key for SOL token lookups and swaps.
    static let jupiterAPIKey = "jupiter-api-key"

    /// Retrieves the Jupiter API key from the keychain.
    /// - Returns: The stored key, or nil if not found.
    func readJupiterAPIKey() -> String? {
        read(forKey: Self.jupiterAPIKey)
    }

    /// Saves the Jupiter API key to the keychain.
    func saveJupiterAPIKey(_ key: String) {
        save(key, forKey: Self.jupiterAPIKey)
    }
}
