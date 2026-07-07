import Foundation
import Security

/// A simple wrapper around the Keychain for storing and retrieving passwords.
class KeychainStore {
    /// Shared instance.
    static let shared = KeychainStore()
    
    private init() {}
    
    /// Save a value for the given key.
    /// - Parameters:
    ///   - value: The string value to save.
    ///   - key: The key to store the value under.
    /// - Returns: True if successful.
    func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete any existing item.
        SecItemDelete(query as CFDictionary)
        
        // Add the new item.
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Load the value for the given key.
    /// - Parameter key: The key to look up.
    /// - Returns: The stored string, or nil if not found.
    func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }
    
    /// Delete the value for the given key.
    /// - Parameter key: The key to delete.
    /// - Returns: True if successful.
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
    
    /// Clear all keychain items for this app (use with caution).
    func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword]
        SecItemDelete(query as CFDictionary)
    }
}