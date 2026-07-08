import Foundation

/// Secure storage helpers for the QR pairing flow.
///
/// What we persist, per OpenClawGatewaySettingsStore.swift:
///   - The instance ID (a UUID generated once per install)
///   - For each paired gateway: the deviceToken (NOT the bootstrap token)
///   - Optional operator token for the bounded operator-scope handoff
///
/// The bootstrap token is **never** persisted past a successful pairing.
enum OpenClawPairingKeychain {

    private enum Key {
        static let instanceID = "openclaw_instance_id"
        static func token(_ stableID: OpenClawPairing.StableID) -> String { "openclaw_token_\(stableID.storageKey)" }
        static func operatorToken(_ stableID: OpenClawPairing.StableID) -> String { "openclaw_operator_\(stableID.storageKey)" }
    }

    private static let service = "ai.openclawfoundation.app.gateway"

    // MARK: - Instance ID

    /// Persistent install ID — one per app install, never per gateway.
    static func loadOrCreateInstanceID() -> String {
        if let existing = read(forKey: Key.instanceID), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        save(new, forKey: Key.instanceID)
        return new
    }

    // MARK: - Tokens

    /// Persist a successfully paired device token. Replaces any prior token
    /// for the same gateway. Bootstrap token is intentionally NOT persisted.
    static func saveDeviceToken(_ token: String, for stableID: OpenClawPairing.StableID) {
        save(token, forKey: Key.token(stableID))
    }

    static func loadDeviceToken(for stableID: OpenClawPairing.StableID) -> String? {
        read(forKey: Key.token(stableID))
    }

    static func saveOperatorToken(_ token: String, for stableID: OpenClawPairing.StableID) {
        save(token, forKey: Key.operatorToken(stableID))
    }

    static func loadOperatorToken(for stableID: OpenClawPairing.StableID) -> String? {
        read(forKey: Key.operatorToken(stableID))
    }

    static func clearAll(for stableID: OpenClawPairing.StableID) {
        delete(forKey: Key.token(stableID))
        delete(forKey: Key.operatorToken(stableID))
    }

    // MARK: - Keychain wrapper (matches the local KeychainStore shape)

    private static func save(_ value: String, forKey key: String) {
        // Prefer Security framework directly so we don't depend on the app's
        // own KeychainStore API surface.
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func read(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}