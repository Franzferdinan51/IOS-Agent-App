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
        // Atomically replace the existing entry. SecItemUpdate is safer than
        // delete-then-add because there's no window where the key is missing
        // (which would let another thread see the absence and re-create with
        // a different value).
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            // No prior entry — add it.
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
                // Best-effort logging — production should use os_log.
                NSLog("OpenClawPairingKeychain: SecItemAdd failed (status=\(addStatus)) for key=\(key)")
            }
        } else if updateStatus != errSecSuccess {
            NSLog("OpenClawPairingKeychain: SecItemUpdate failed (status=\(updateStatus)) for key=\(key)")
        }
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