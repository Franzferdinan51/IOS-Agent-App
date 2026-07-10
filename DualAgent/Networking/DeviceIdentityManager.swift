import Foundation
import Security
import CommonCrypto

/// Manages the device P256 identity for OpenClaw gateway authentication.
///
/// Device identity lifecycle:
///   1. Generate P256 keypair on first launch → store private key in Keychain
///   2. Device ID = SHA256 fingerprint of the raw public key (first 8 hex chars)
///   3. On connect challenge → sign v3 auth payload with private key
///   4. Send device.{id, publicKey, signature, signedAt, nonce} in connect params
///
/// Key reference: `packages/gateway-client/src/device-auth.ts` (TypeScript reference)
/// Protocol ref:   `docs/gateway/protocol.md` §"Device identity and pairing"
final class DeviceIdentityManager: @unchecked Sendable {

    // MARK: - Keychain key

    private static let keychainService = "ai.openclawfoundation.app.gateway"
    private static let privateKeyAccount = "openclaw_device_identity_p256"

    // MARK: - Public Types

    struct DeviceIdentity: Sendable {
        let deviceId: String       // hex fingerprint of public key
        let publicKeyData: Data   // raw uncompressed P256 public key (65 bytes: 0x04 || x || y)
        let privateKeyRef: SecKey // reference to the Keychain-stored private key
    }

    // MARK: - Singleton

    static let shared = DeviceIdentityManager()

    private init() {}

    // MARK: - Load or create identity

    /// Loads the existing device identity from Keychain, or generates and stores
    /// a new P256 keypair on first call.
    func loadOrCreateIdentity() -> DeviceIdentity? {
        // Try to load existing private key
        if let privateKey = loadPrivateKey(),
           let publicKey = SecKeyCopyPublicKey(privateKey) {
            let publicKeyData = exportRawPublicKey(publicKey)
            let deviceId = deriveDeviceId(from: publicKeyData)
            return DeviceIdentity(deviceId: deviceId, publicKeyData: publicKeyData, privateKeyRef: privateKey)
        }

        // Generate new keypair
        guard let privateKey = generateP256KeyPair(),
              let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        let publicKeyData = exportRawPublicKey(publicKey)
        let deviceId = deriveDeviceId(from: publicKeyData)

        // Store private key in Keychain
        guard storePrivateKey(privateKey) else { return nil }

        return DeviceIdentity(deviceId: deviceId, publicKeyData: publicKeyData, privateKeyRef: privateKey)
    }

    // MARK: - Key generation

    /// Generates a new P256 (secp256r1) key pair and returns the private key.
    private func generateP256KeyPair() -> SecKey? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false  // we store manually in Keychain
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            NSLog("DeviceIdentityManager: key generation failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return privateKey
    }

    // MARK: - Keychain storage

    /// Stores the private key in the iOS Keychain (kSecClassKey, accessible after first unlock).
    @discardableResult
    func storePrivateKey(_ privateKey: SecKey) -> Bool {
        // Export private key as Data
        var error: Unmanaged<CFError>?
        guard let privateKeyData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            NSLog("DeviceIdentityManager: export private key failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: Self.privateKeyAccount.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: privateKeyData
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("DeviceIdentityManager: SecItemAdd failed: \(status)")
            return false
        }
        return true
    }

    /// Loads the private key from the iOS Keychain.
    func loadPrivateKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: Self.privateKeyAccount.data(using: .utf8)!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let keyData = result as? Data else {
            return nil
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            NSLog("DeviceIdentityManager: SecKeyCreateWithData failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return privateKey
    }

    /// Deletes the private key from Keychain (for logout/reset).
    func deletePrivateKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: Self.privateKeyAccount.data(using: .utf8)!
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Public key export

    /// Exports the public key as raw uncompressed P256 point (65 bytes: 0x04 || x || y).
    /// This matches the format used by the OpenClaw gateway client.
    private func exportRawPublicKey(_ publicKey: SecKey) -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            NSLog("DeviceIdentityManager: export public key failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return Data()
        }
        // Security.framework already exports raw P256 as 65-byte uncompressed: 0x04 || x || y
        // Some platforms return 64 bytes (raw x||y without 0x04 prefix). Normalize:
        if data.count == 64 {
            return Data([0x04]) + data
        }
        return data
    }

    /// Converts raw public key to base64url (no padding) for wire transmission.
    func publicKeyBase64URL(_ publicKeyData: Data) -> String {
        publicKeyData.base64URLEncodedString()
    }

    // MARK: - Device ID

    /// Derives a stable device ID from the first 8 hex chars of SHA256(public key).
    /// Matches the `deviceId` computation in gateway-client.
    func deriveDeviceId(from publicKeyData: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        publicKeyData.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(ptr.count), &hash)
        }
        let hex = hash.prefix(4).map { String(format: "%02x", $0) }.joined()
        return hex
    }

    // MARK: - Signing

    /// Signs the v3 device auth payload using ECDSA with the P256 private key.
    /// Returns raw signature bytes (DER-encoded r||s, 64 bytes).
    func signPayload(_ payload: String, with privateKey: SecKey) -> Data? {
        guard let payloadData = payload.data(using: .utf8) else { return nil }

        let algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            NSLog("DeviceIdentityManager: algorithm not supported")
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey, algorithm, payloadData as CFData, &error) as Data? else {
            NSLog("DeviceIdentityManager: sign failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
            return nil
        }
        return signature
    }

    // MARK: - v3 Payload builder

    /// Builds the v3 device auth payload string that gets signed.
    /// Mirrors `buildDeviceAuthPayloadV3` in `packages/gateway-client/src/device-auth.ts`.
    ///
    /// Format: v3|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce|platform|deviceFamily
    func buildV3Payload(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int64,
        token: String?,
        nonce: String,
        platform: String,
        deviceFamily: String?
    ) -> String {
        let scopesStr = scopes.joined(separator: ",")
        let tokenStr = token ?? ""
        let familyStr = (deviceFamily ?? "").lowercased()

        return [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopesStr,
            String(signedAtMs),
            tokenStr,
            nonce,
            platform.lowercased(),
            familyStr,
        ].joined(separator: "|")
    }
}

// MARK: - Data extension for base64url

extension Data {
    /// RFC 4648 base64url encoding with no padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
