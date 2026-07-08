import Foundation
import Combine

@MainActor
class OnboardingViewModel: ObservableObject {
    @Published var selectedBackendType: BackendType = .hermes
    @Published var serverURL: String = ""
    /// Single shared credential field:
    ///   - Hermes: server password (POSTed to /api/auth/login)
    ///   - OpenClaw: gateway token (sent as Bearer header; from `openclaw config get gateway.auth.token`)
    /// Hermes never uses a username; OpenClaw never uses an API key.
    @Published var credential: String = ""
    @Published var isLoading: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    // QR pairing state (OpenClaw only).
    @Published var showQRScanner: Bool = false
    @Published var isPairing: Bool = false
    @Published var pairingStatus: String = "Preparing…"
    private var pairingTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    /// The AuthManager instance the UI uses (injected via init(authManager:)).
    /// In the legacy no-arg init path this stays nil and the VM falls back
    /// to AuthManager.shared — which works for previews but causes the UI
    /// to miss state updates in production (see init comment above).
    private var authManager: AuthManager?

    init() {
        // Note: this is the legacy no-arg init used by #Preview. Production
        // code uses init(authManager:) so the same instance the rest of the
        // app uses is also the one driving the auth state.
    }

    /// Production initializer. The same `AuthManager` instance that
    /// `RootView` watches for `isLoggedIn` must be the one we call
    /// `connect` on, otherwise the state flip never reaches the UI.
    init(authManager: AuthManager) {
        self.authManager = authManager
        authManager.$isAuthenticated
            .assign(to: &$isAuthenticated)
        applyDebugLaunchArgs()
    }

    /// Late-bind the AuthManager when `@StateObject` initialization runs
    /// before the `@EnvironmentObject` is available (which is the case
    /// for SwiftUI Views — `@StateObject` initializers are called during
    /// the View's init, but `@EnvironmentObject` is injected later by
    /// the parent). Idempotent — safe to call multiple times.
    func attach(authManager: AuthManager) {
        if self.authManager === authManager { return }
        self.authManager = authManager
        // (Re-)subscribe to its state. Drop any prior subscriptions.
        cancellables.removeAll()
        authManager.$isAuthenticated
            .assign(to: &$isAuthenticated)
    }

    private func applyDebugLaunchArgs() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        func value(forKey key: String) -> String? {
            if let v = env[key], !v.isEmpty { return v }
            // ProcessInfo.arguments looks like ["DualAgent.app/Contents/MacOS/DualAgent", "-DAServerURL", "https://...", ...]
            if let i = args.firstIndex(of: key), i + 1 < args.count {
                return args[i + 1]
            }
            return nil
        }
        if let url = value(forKey: "-DAServerURL") ?? value(forKey: "DA_SERVER_URL") {
            serverURL = url
        }
        if let cred = value(forKey: "-DACredential") ?? value(forKey: "DA_CREDENTIAL") {
            credential = cred
        }
        if let backend = value(forKey: "-DABackend") ?? value(forKey: "DA_BACKEND") {
            if backend.lowercased() == "openclaw" { selectedBackendType = .openclaw }
        }
        // Auto-trigger Connect on launch (debug-only) when DA_AUTO_CONNECT=1
        // is set. Useful for headless simulator testing.
        if (value(forKey: "-DAAutoConnect") ?? value(forKey: "DA_AUTO_CONNECT")) == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.testConnection()
            }
        }
        #endif
    }

    @Published var isAuthenticated: Bool = false

    /// Human-readable label for the credential field, based on the
    /// selected backend — shown in the UI as the SecureField placeholder.
    var credentialLabel: String {
        switch selectedBackendType {
        case .hermes: return "Server Password"
        case .openclaw: return "Gateway Token"
        }
    }

    var credentialHelp: String {
        switch selectedBackendType {
        case .hermes:
            return "Hermes signs in with a single server password. If the server has auth turned off, this field can be left empty."
        case .openclaw:
            return "Paste the token from OpenClaw: run `openclaw config get gateway.auth.token` on the gateway host — or use the QR option below."
        }
    }

    func testConnection() {
        Haptic.tap()
        isLoading = true
        showError = false
        errorMessage = ""

        let manager = authManager ?? AuthManager.shared
        manager.switchBackend(to: selectedBackendType)

        Task {
            do {
                try await manager.connect(
                    serverURL: serverURL,
                    credential: credential
                )
                Haptic.paired()
                isLoading = false
            } catch {
                Haptic.error()
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - QR Pairing

    /// Kick off pairing from a scanned QR payload. Drives the OpenClaw
    /// websocket handshake through `OpenClawBackend.startPairing` and updates
    /// the UI as events arrive.
    func startPairing(from payload: String, authManager: AuthManager) {
        guard selectedBackendType == .openclaw else { return }
        // Force the backend to OpenClaw before we drive the handshake.
        authManager.switchBackend(to: .openclaw)

        isPairing = true
        showError = false
        errorMessage = ""
        pairingStatus = "Connecting to gateway…"

        let backend = OpenClawBackend.shared
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let task = Task { @MainActor in
            let stream = backend.startPairing(from: payload, appVersion: appVersion)
            do {
                for try await event in stream {
                    switch event {
                    case .connecting(let url):
                        pairingStatus = "Connecting to \(url.host ?? "gateway")…"
                    case .challengeReceived:
                        pairingStatus = "Verifying setup code…"
                    case .paired(let result):
                        pairingStatus = "Paired as \(result.role). Signing in…"
                        isPairing = false
                        // Don't call authManager.connect() here — that would call
                        // backend.login(), which opens a SECOND WebSocket and re-pairs
                        // with the just-issued deviceToken. The QR pairing already
                        // established auth; just persist the token and flip state.
                        authManager.switchBackend(to: .openclaw)
                        if let openClaw = authManager.backend as? OpenClawBackend {
                            openClaw.markPaired(deviceToken: result.deviceToken,
                                                stableID: result.stableID)
                        }
                        do {
                            try await authManager.completeOpenClawPairing(
                                deviceToken: result.deviceToken,
                                stableID: result.stableID
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                        return
                    case .failed(let error):
                        isPairing = false
                        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        showError = true
                        return
                    }
                }
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        pairingTask = task
    }

    func cancelPairing() {
        pairingTask?.cancel()
        pairingTask = nil
        isPairing = false
        pairingStatus = "Cancelled"
    }
}