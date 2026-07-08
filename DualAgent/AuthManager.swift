import Foundation
import SwiftUI
import LocalAuthentication

/// Manages authentication and the currently active backend for DualAgent.
/// Coordinates between the UI and the Backend protocol (Hermes or OpenClaw).
///
/// **Authentication model — no usernames, no API keys.**
/// - Hermes-webui: a single server password (POSTed to `/api/auth/login`).
///   If the server reports `authEnabled == false`, the password may be empty
///   and we connect anonymously.
/// - OpenClaw: a single gateway token (sent as `Authorization: Bearer …`).
///   Comes from the gateway host via `openclaw config get gateway.auth.token`,
///   not an "API key" in the model-provider sense.
@MainActor
final class AuthManager: ObservableObject {
    // MARK: - Singleton

    static let shared = AuthManager()

    // MARK: - Dependencies

    private let keychain = KeychainStore()

    // MARK: - Published State

    @Published private(set) var isAuthenticated: Bool = false

    /// Convenience alias for isAuthenticated — used by RootView for auth routing.
    var isLoggedIn: Bool { isAuthenticated }
    @Published private(set) var currentBackendType: BackendType = .hermes

    // MARK: - Backend

    /// The currently active backend. Use `switchBackend(to:)` to change.
    private(set) var backend: Backend

    // MARK: - Keychain Keys

    private let serverURLKey = "dualagent_server_url"
    private let backendTypeKey = "dualagent_backend_type"
    /// One credential per backend. Hermes = password, OpenClaw = gateway token.
    private let hermesCredentialKey = "dualagent_hermes_credential"
    private let openClawCredentialKey = "dualagent_openclaw_credential"
    private let biometricEnabledKey = "dualagent_biometric_enabled"

    // MARK: - Init

    init() {
        let savedBackendType: BackendType
        if let saved = Self.loadBackendType(), let type = BackendType(rawValue: saved) {
            savedBackendType = type
        } else {
            savedBackendType = .hermes
        }

        let savedURL: URL
        if let urlString = keychain.read(forKey: serverURLKey),
           let url = URL(string: urlString) {
            savedURL = url
        } else {
            savedURL = savedBackendType == .hermes ? AppConfig.hermesBaseURL : AppConfig.openClawBaseURL
        }

        let backend: Backend
        switch savedBackendType {
        case .hermes:
            backend = HermesBackend(baseURL: savedURL)
        case .openclaw:
            backend = OpenClawBackend(baseURL: savedURL)
        }

        self.backend = backend
        self.currentBackendType = savedBackendType
        self.isAuthenticated = backend.isAuthenticated

        // Attempt silent login if we have a stored credential for the active backend
        Task {
            await attemptSilentLogin()
        }
    }

    /// Convenience initializer for previews and testing.
    init(backend: Backend) {
        self.backend = backend
        self.isAuthenticated = backend.isAuthenticated
        self.currentBackendType = backend.backendType
    }

    // MARK: - Silent Login

    private func attemptSilentLogin() async {
        guard let serverURL = keychain.read(forKey: serverURLKey),
              let backendTypeRaw = keychain.read(forKey: backendTypeKey),
              let backendType = BackendType(rawValue: backendTypeRaw) else { return }

        let credentialKey = backendType == .hermes ? hermesCredentialKey : openClawCredentialKey
        guard let credential = keychain.read(forKey: credentialKey) else { return }

        do {
            let success = try await backend.login(credential: credential)
            isAuthenticated = success
        } catch {
            // Silent login failed — clear the stale credential so the user
            // isn't stuck behind a bad password/token in the keychain.
            keychain.delete(forKey: credentialKey)
        }
    }

    // MARK: - Connect (used by Onboarding)

    /// Connect to whichever backend is currently selected.
    /// - Parameters:
    ///   - serverURL: The full base URL of the server (e.g. `https://hermes.example`).
    ///   - credential: The single credential — Hermes password OR OpenClaw gateway token.
    func connect(serverURL: String, credential: String) async throws -> Bool {
        guard let url = URL(string: serverURL) else {
            throw LoginError.invalidURL
        }

        // If the URL changed, rebuild the backend for the new host so the
        // configured auth and baseURL all line up.
        if backend.baseURL != url {
            rebuildBackend(for: currentBackendType, baseURL: url)
        }

        keychain.save(serverURL, forKey: serverURLKey)
        keychain.save(currentBackendType.rawValue, forKey: backendTypeKey)

        let credentialKey = currentBackendType == .hermes ? hermesCredentialKey : openClawCredentialKey
        keychain.save(credential, forKey: credentialKey)

        let success = try await backend.login(credential: credential)
        isAuthenticated = success
        return success
    }

    /// Legacy single-arg entry point used in a few call sites.
    func connect(serverURL: String) async throws -> Bool {
        let credentialKey = currentBackendType == .hermes ? hermesCredentialKey : openClawCredentialKey
        let stored = keychain.read(forKey: credentialKey) ?? ""
        return try await connect(serverURL: serverURL, credential: stored)
    }

    /// Called by the QR pairing flow after the WebSocket pairing handshake
    /// completes. The pairing already issued a device token, so we persist
    /// it, mark the backend authenticated, and stay signed in across launches.
    func completeOpenClawPairing(deviceToken: String, stableID: OpenClawPairing.StableID) async throws {
        guard let openClaw = backend as? OpenClawBackend else {
            throw LoginError.invalidCredentials
        }
        openClaw.markPaired(deviceToken: deviceToken, stableID: stableID)
        keychain.save(deviceToken, forKey: openClawCredentialKey)
        isAuthenticated = true
    }

    // MARK: - Logout

    func logout() {
        Task {
            try? await backend.logout()
            isAuthenticated = false
            clearCredentials()
        }
    }

    func logoutSync() {
        isAuthenticated = false
        clearCredentials()
    }

    func logout() async {
        try? await backend.logout()
        isAuthenticated = false
        clearCredentials()
    }

    // MARK: - Switch Backend

    func switchBackend(to type: BackendType) {
        // Use the saved URL if present, otherwise fall back to the type's default.
        let url: URL
        if let stored = keychain.read(forKey: serverURLKey),
           let parsed = URL(string: stored),
           storedMatchesBackend(storedURLString: stored, backend: type) {
            url = parsed
        } else {
            url = type == .hermes ? AppConfig.hermesBaseURL : AppConfig.openClawBaseURL
        }

        rebuildBackend(for: type, baseURL: url)
        currentBackendType = type
        keychain.save(type.rawValue, forKey: backendTypeKey)

        // Re-attempt silent login on the new backend if a credential is stored.
        let credentialKey = type == .hermes ? hermesCredentialKey : openClawCredentialKey
        if let credential = keychain.read(forKey: credentialKey) {
            Task {
                do {
                    let success = try await backend.login(credential: credential)
                    isAuthenticated = success
                } catch {
                    isAuthenticated = false
                }
            }
        }
    }

    private func storedMatchesBackend(storedURLString: String, backend: BackendType) -> Bool {
        // We don't have a strict per-backend tag in the keychain, but we can
        // accept any stored URL when switching and let the user re-enter if
        // it's wrong for the selected backend.
        return true
    }

    private func rebuildBackend(for type: BackendType, baseURL: URL) {
        let newBackend: Backend
        switch type {
        case .hermes:
            newBackend = HermesBackend(baseURL: baseURL)
        case .openclaw:
            newBackend = OpenClawBackend(baseURL: baseURL)
        }
        self.backend = newBackend
    }

    // MARK: - Biometric Auth

    var isBiometricEnabled: Bool {
        keychain.read(forKey: biometricEnabledKey) == "true"
    }

    func enableBiometricAuth(_ enabled: Bool) {
        keychain.save(enabled ? "true" : "false", forKey: biometricEnabledKey)
    }

    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateWithBiometrics(completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false, error)
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Authenticate to access DualAgent"
        ) { success, evalError in
            DispatchQueue.main.async {
                completion(success, evalError)
            }
        }
    }

    // MARK: - Private Helpers

    private func clearCredentials() {
        keychain.delete(forKey: serverURLKey)
        keychain.delete(forKey: backendTypeKey)
        keychain.delete(forKey: hermesCredentialKey)
        keychain.delete(forKey: openClawCredentialKey)
    }

    private static func loadBackendType() -> String? {
        let store = KeychainStore()
        return store.read(forKey: "dualagent_backend_type")
    }
}

// MARK: - BackendType RawRepresentable

extension BackendType: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "hermes": self = .hermes
        case "openclaw": self = .openclaw
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .hermes: return "hermes"
        case .openclaw: return "openclaw"
        }
    }
}

// MARK: - LoginError

enum LoginError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case transportRefused(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .invalidCredentials: return "Invalid credentials"
        case .transportRefused(let detail): return detail
        }
    }
}
