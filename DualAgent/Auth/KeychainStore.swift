import Foundation
import KeychainAccess

/// A simple wrapper around KeychainAccess for storing and retrieving strings and data.
final class KeychainStore {
    private let keychain: Keychain

    /// Creates a KeychainStore with a given service name.
    /// - Parameter service: The service identifier used as a prefix for all keys.
    init(service: String = "com.dualagent") {
        self.keychain = Keychain(service: service)
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

    /// Retrieves raw data from the keychain.
    /// - Parameter key: The key associated with the data.
    /// - Returns: The stored data, or nil if not found.
    func readData(forKey key: String) -> Data? {
        return try? keychain.getData(key)
    }
}
